# AgentBox MCP 依赖动态管理方案设计

## 目标

实现 MCP 依赖的动态安装和环境快照导出，避免在 Dockerfile 中硬编码所有可能的依赖。

## 核心思路

1. **依赖声明文件**：为每个 MCP 定义依赖清单
2. **动态安装**：安装 MCP 时自动检测并安装依赖
3. **环境快照**：将安装好的容器保存为新镜像
4. **Dockerfile 生成**：从快照反推生成 Dockerfile（可选）

---

## 方案 A：依赖声明 + 动态安装（推荐）

### 1. MCP 依赖声明文件

创建 `~/.gabox/mcp-deps/` 目录存储依赖清单：

```yaml
# ~/.gabox/mcp-deps/playwright.yml
name: playwright
package: "@playwright/mcp@latest"
dependencies:
  system:
    # Playwright 需要的系统包
    - libnss3
    - libnspr4
    - libatk1.0-0
    # ... 更多系统依赖
  npm:
    - "playwright@1.48.0"
  post_install:
    - "npx playwright install chromium"
  env:
    PLAYWRIGHT_DOWNLOAD_HOST: "https://npmmirror.com/mirrors/playwright/"
```

```yaml
# ~/.gabox/mcp-deps/puppeteer.yml
name: puppeteer
package: "@puppeteer/mcp@latest"
dependencies:
  system:
    - chromium
  npm:
    - "puppeteer@latest"
```

### 2. 增强的 `gabox mcp add` 命令

```bash
#!/bin/bash
function handle_mcp_add() {
    local agent="$1"
    local mcp_name="$2"
    shift 2
    local mcp_command=("$@")

    local container_name=$(get_or_create_container "$agent")

    # 1. 检查依赖清单
    local deps_file="$HOME/.gabox/mcp-deps/${mcp_name}.yml"
    if [[ -f "$deps_file" ]]; then
        echo "🔍 检测到 $mcp_name 的依赖清单"

        # 2. 安装系统依赖
        local sys_deps=$(yq '.dependencies.system[]' "$deps_file" 2>/dev/null)
        if [[ -n "$sys_deps" ]]; then
            echo "📦 安装系统依赖..."
            docker exec "$container_name" bash -c "
                apt-get update && \
                apt-get install -y $sys_deps
            "
        fi

        # 3. 设置环境变量
        local env_vars=$(yq '.dependencies.env' "$deps_file" -o=json 2>/dev/null)
        if [[ "$env_vars" != "null" ]]; then
            echo "🔧 配置环境变量..."
            # 将环境变量写入容器的 ~/.bashrc 或创建启动脚本
        fi

        # 4. 安装 npm 包
        local npm_deps=$(yq '.dependencies.npm[]' "$deps_file" 2>/dev/null)
        if [[ -n "$npm_deps" ]]; then
            echo "📦 安装 npm 依赖..."
            docker exec "$container_name" bash -c "
                npm install -g $npm_deps
            "
        fi

        # 5. 执行安装后命令
        local post_install=$(yq '.dependencies.post_install[]' "$deps_file" 2>/dev/null)
        if [[ -n "$post_install" ]]; then
            echo "⚙️  执行安装后配置..."
            docker exec "$container_name" bash -c "$post_install"
        fi
    else
        echo "ℹ️  未找到 $mcp_name 的依赖清单，跳过依赖安装"
    fi

    # 6. 添加 MCP 配置
    docker exec "$container_name" bash -c "$agent mcp add -s user $mcp_name -- ${mcp_command[*]}"

    # 7. 询问是否保存快照
    echo ""
    echo "✅ MCP 安装完成！"
    echo ""
    read -p "是否保存当前环境为新镜像？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        save_container_snapshot "$container_name" "$mcp_name"
    fi
}
```

### 3. 环境快照功能

```bash
function save_container_snapshot() {
    local container_name="$1"
    local mcp_name="$2"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_tag="gabox-dev:snapshot-${mcp_name}-${timestamp}"

    echo "📸 正在创建环境快照..."

    # 使用 docker commit 保存容器状态
    docker commit \
        --author "gabox" \
        --message "Added MCP: $mcp_name" \
        "$container_name" \
        "$snapshot_tag"

    echo "✅ 快照已保存: $snapshot_tag"
    echo ""
    echo "使用快照："
    echo "  1. 修改 gabox 脚本中的 IMAGE_FULL 为 $snapshot_tag"
    echo "  2. 或运行: docker tag $snapshot_tag gabox-dev:latest"
    echo ""

    # 可选：询问是否导出 Dockerfile
    read -p "是否导出 Dockerfile？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        generate_dockerfile_from_snapshot "$snapshot_tag" "$mcp_name"
    fi
}
```

### 4. Dockerfile 生成（可选）

```bash
function generate_dockerfile_from_snapshot() {
    local snapshot_tag="$1"
    local mcp_name="$2"
    local output_file="Dockerfile.${mcp_name}"

    echo "📝 生成 Dockerfile: $output_file"

    # 获取镜像的历史记录
    local history=$(docker history --no-trunc "$snapshot_tag" --format "{{.CreatedBy}}")

    # 基于基础 Dockerfile + 新增的层生成新的 Dockerfile
    cat > "$output_file" <<EOF
# 此文件由 gabox 自动生成
# 基于快照: $snapshot_tag
# 时间: $(date)

FROM python:3.12-slim

# ... 复制基础 Dockerfile 的内容 ...

# === 动态添加的依赖 ===
EOF

    # 从依赖清单重新生成 RUN 指令
    local deps_file="$HOME/.gabox/mcp-deps/${mcp_name}.yml"
    if [[ -f "$deps_file" ]]; then
        yq -r '.dependencies.system[]' "$deps_file" | while read pkg; do
            echo "# System: $pkg" >> "$output_file"
        done

        echo "" >> "$output_file"
        echo "RUN apt-get update && apt-get install -y \\" >> "$output_file"
        yq -r '.dependencies.system[]' "$deps_file" | sed 's/^/    /' >> "$output_file"
        echo "    && rm -rf /var/lib/apt/lists/*" >> "$output_file"
    fi

    echo "✅ Dockerfile 已生成: $output_file"
}
```

---

## 方案 B：完全动态（更激进）

不预定义依赖清单，安装 MCP 时自动检测失败原因并尝试修复：

```bash
function install_mcp_with_retry() {
    local mcp_command="$1"
    local max_retries=3

    for i in $(seq 1 $max_retries); do
        echo "尝试安装 MCP (第 $i 次)..."

        # 执行安装命令并捕获错误
        local output=$(docker exec "$container_name" bash -c "$mcp_command" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "✅ 安装成功"
            return 0
        fi

        # 分析错误信息
        if echo "$output" | grep -q "ENOENT.*playwright"; then
            echo "检测到缺少 Playwright，正在安装..."
            docker exec "$container_name" bash -c "npm install -g playwright && npx playwright install chromium"
        elif echo "$output" | grep -q "libgobject"; then
            echo "检测到缺少系统库，正在安装..."
            docker exec "$container_name" bash -c "apt-get update && apt-get install -y libgobject-2.0-0"
        else
            echo "未知错误: $output"
            return 1
        fi
    done

    echo "❌ 安装失败，已达最大重试次数"
    return 1
}
```

**优点**：完全自动化，无需维护依赖清单
**缺点**：错误检测不可靠，可能进入死循环

---

## 方案 C：混合方案（平衡）

1. **基础镜像**：只包含 Node.js、Python 等通用工具
2. **MCP 模块镜像**：每个重量级 MCP 有独立的镜像层
3. **多阶段选择**：用户根据需要选择加载哪些模块

```dockerfile
# Dockerfile.base - 基础镜像
FROM python:3.12-slim
# ... 基础依赖 ...

# Dockerfile.playwright - Playwright 模块
FROM gabox-dev:base
RUN npm install -g playwright && npx playwright install chromium

# Dockerfile.puppeteer - Puppeteer 模块
FROM gabox-dev:base
RUN npm install -g puppeteer
```

用户使用：
```bash
# 安装时选择模块
gabox build --modules=playwright,puppeteer

# 或动态加载
gabox mcp add --auto-install playwright
```

---

## 推荐实施路径

### 阶段 1：依赖声明（立即可用）

1. 创建 `~/.gabox/mcp-deps/` 目录结构
2. 添加常用 MCP 的依赖清单（YAML 格式）
3. 修改 `gabox mcp add` 读取并安装依赖

**优点**：
- 简单可控
- 用户可自定义依赖清单
- 不破坏现有功能

### 阶段 2：环境快照（增强体验）

1. 添加 `gabox mcp snapshot` 命令
2. 支持 `docker commit` 保存环境
3. 支持快照管理（列出、删除、切换）

**优点**：
- 避免重复安装
- 加快容器启动
- 可分享给团队

### 阶段 3：Dockerfile 导出（可选）

1. 从快照生成 Dockerfile
2. 用于CI/CD或分享

**优点**：
- 可重现的构建
- 版本控制友好

---

## 文件结构

```
~/.gabox/
├── claude/                 # Claude Code 配置
├── happy/                  # Happy 配置
├── mcp-deps/              # MCP 依赖清单（新增）
│   ├── playwright.yml
│   ├── puppeteer.yml
│   ├── brave-search.yml
│   └── ...
├── snapshots/             # 环境快照元数据（新增）
│   └── snapshot-registry.json
└── containers.json        # 容器状态

AgentBox/
├── Dockerfile             # 基础镜像
├── Dockerfile.full        # 完整镜像（废弃或保留作后备）
├── gabox                  # 主脚本
└── scripts/              # 新增脚本目录
    ├── mcp-deps-install.sh
    ├── snapshot-manager.sh
    └── dockerfile-generator.sh
```

---

## 命令示例

```bash
# 1. 安装 MCP（自动检测依赖）
gabox mcp claude add playwright -- npx -y @playwright/mcp@latest
# 输出：
# 🔍 检测到 playwright 的依赖清单
# 📦 安装系统依赖...
# 📦 安装 npm 依赖...
# ⚙️  执行安装后配置...
# ✅ MCP 安装完成！
# 是否保存当前环境为新镜像？(y/N)

# 2. 管理快照
gabox snapshot list
# 输出：
# gabox-dev:snapshot-playwright-20250104-143022  (2.1 GB)
# gabox-dev:snapshot-puppeteer-20250103-091545   (1.8 GB)

gabox snapshot use playwright
# 将容器切换为使用该快照

gabox snapshot export playwright > Dockerfile.custom
# 导出 Dockerfile

# 3. 查看已安装的 MCP 及其依赖
gabox mcp claude info
# 输出：
# 已安装的 MCP:
# - playwright (package: @playwright/mcp@latest)
#   依赖: playwright@1.48.0, chromium
#   大小: ~200 MB
# - filesystem (package: @modelcontextprotocol/server-filesystem)
#   依赖: 无
```

---

## 技术细节

### 依赖检测优先级

1. **本地依赖清单**：`~/.gabox/mcp-deps/{name}.yml`
2. **远程仓库**：从 GitHub 拉取社区维护的清单
3. **fallback**：安装 MCP 但不安装额外依赖

### 快照存储策略

- **本地存储**：使用 Docker 镜像存储
- **标签规范**：`gabox-dev:snapshot-{mcp_name}-{timestamp}`
- **元数据**：JSON 文件记录快照关联的 MCP 和依赖版本

### 安全考虑

1. **依赖验证**：只安装来自可信源的依赖清单
2. **沙箱隔离**：依赖安装在临时容器中测试
3. **回滚机制**：保留上一个可用快照

---

## 待解决的问题

1. **依赖冲突**：不同 MCP 可能需要不同版本的同一依赖
2. **镜像膨胀**：多次快照会占用大量磁盘空间
3. **跨平台**：ARM 和 x86 的依赖可能不同

## 解决方案建议

1. **依赖冲突**：为每个 MCP 使用独立的虚拟环境或容器
2. **镜像膨胀**：实现快照清理机制，保留最近 N 个快照
3. **跨平台**：在依赖清单中区分架构（`system.amd64` vs `system.arm64`）

---

## 总结

**推荐方案 A（依赖声明 + 动态安装）**，理由：

1. ✅ **可控性强**：用户知道安装了什么
2. ✅ **灵活性高**：支持自定义依赖清单
3. ✅ **学习曲线低**：YAML 格式易于理解
4. ✅ **可扩展**：未来可添加远程仓库、自动检测等功能
5. ✅ **向后兼容**：不破坏现有 `gabox mcp` 命令

**实施优先级**：
1. 🔥 阶段 1（依赖声明）- 立即实施
2. 🌟 阶段 2（环境快照）- 下个版本
3. 💡 阶段 3（Dockerfile 导出）- 按需实施
