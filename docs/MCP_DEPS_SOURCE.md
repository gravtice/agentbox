# MCP 依赖信息来源方案

## 问题：依赖 YAML 从哪里来？

当前设计中需要 `~/.gabox/mcp-deps/playwright.yml` 这样的依赖清单，但这些信息从哪里获取？

---

## 方案对比

### 方案 1：手动维护（初期）⭐ 推荐

**做法：**
1. 项目维护者手动测试每个 MCP
2. 记录安装失败时缺少的依赖
3. 编写 YAML 清单并提交到项目仓库

**流程示例：**
```bash
# 1. 在干净的基础镜像中测试安装
docker run -it gabox-dev:base bash
npm install -g @playwright/mcp@latest
# 错误: Error: Could not find browser binary

# 2. 记录需要的依赖
npx playwright install chromium
# 错误: Missing dependencies: libnss3, libatk1.0-0...

# 3. 安装系统依赖
apt-get install -y libnss3 libatk1.0-0 libgbm1
npx playwright install chromium
# 成功!

# 4. 编写 YAML 清单
cat > mcp-deps/playwright.yml <<EOF
name: playwright
package: "@playwright/mcp@latest"
dependencies:
  system:
    - libnss3
    - libatk1.0-0
    - libgbm1
    # ... 其他依赖
  npm:
    - "playwright@1.48.0"
  post_install:
    - "npx playwright install chromium"
EOF
```

**优点：**
- ✅ 准确可靠（人工验证）
- ✅ 立即可用（无需开发工具）
- ✅ 易于维护（YAML 格式简单）

**缺点：**
- ❌ 需要人工测试每个 MCP
- ❌ 依赖更新需要手动同步

**适用阶段：** MVP 阶段，快速启动项目

---

### 方案 2：从 npm 包自动提取

**做法：**
分析 MCP 包的 `package.json` 获取依赖信息

**实现：**
```bash
# 1. 下载包信息
npm view @playwright/mcp dependencies peerDependencies --json

# 输出:
# {
#   "dependencies": {
#     "playwright": "1.57.0-alpha-1761929702000",
#     "playwright-core": "1.57.0-alpha-1761929702000"
#   }
# }

# 2. 递归查询子依赖
npm view playwright dependencies --json

# 3. 生成依赖清单
gabox mcp analyze @playwright/mcp > mcp-deps/playwright.yml
```

**问题：**
- ❌ npm dependencies 只包含 JS 包，不包含系统依赖
- ❌ Playwright 的浏览器二进制文件在 post-install 脚本中下载，npm 信息不体现
- ❌ 系统依赖（libnss3 等）完全不在 package.json 中

**适用场景：** 仅对于纯 JS 包的 MCP（如 filesystem、memory）

---

### 方案 3：运行时检测（动态） ⭐⭐ 推荐（长期）

**做法：**
在容器中尝试安装 MCP，捕获错误并自动修复

**实现思路：**
```bash
function auto_install_mcp() {
    local mcp_package="$1"
    local max_retries=3
    local installed_deps=()

    for i in $(seq 1 $max_retries); do
        # 尝试安装
        local output=$(npm install -g "$mcp_package" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "✅ 安装成功"

            # 保存依赖清单供将来使用
            save_dependency_profile "$mcp_package" "${installed_deps[@]}"
            return 0
        fi

        # 分析错误并修复
        if echo "$output" | grep -q "Cannot find module 'playwright'"; then
            echo "📦 安装 playwright..."
            npm install -g playwright
            installed_deps+=("npm:playwright")

        elif echo "$output" | grep -q "Could not find browser"; then
            echo "🌐 安装浏览器..."
            npx playwright install chromium
            installed_deps+=("browser:chromium")

        elif echo "$output" | grep -q "error while loading shared libraries: libnss3"; then
            echo "📦 安装系统依赖: libnss3..."
            apt-get update && apt-get install -y libnss3
            installed_deps+=("system:libnss3")

        elif echo "$output" | grep -q "error while loading shared libraries: libgbm"; then
            echo "📦 安装系统依赖: libgbm1..."
            apt-get install -y libgbm1
            installed_deps+=("system:libgbm1")

        else
            echo "❌ 未知错误: $output"
            return 1
        fi
    done
}

function save_dependency_profile() {
    local package="$1"
    shift
    local deps=("$@")

    local yaml_file="mcp-deps/$(basename $package).yml"

    cat > "$yaml_file" <<EOF
name: $(basename $package)
package: "$package"
auto_generated: true
generated_at: $(date -I)
dependencies:
EOF

    # 分类保存依赖
    echo "  system:" >> "$yaml_file"
    for dep in "${deps[@]}"; do
        if [[ "$dep" == system:* ]]; then
            echo "    - ${dep#system:}" >> "$yaml_file"
        fi
    done

    echo "  npm:" >> "$yaml_file"
    for dep in "${deps[@]}"; do
        if [[ "$dep" == npm:* ]]; then
            echo "    - ${dep#npm:}" >> "$yaml_file"
        fi
    done

    echo "✅ 依赖清单已保存: $yaml_file"
}
```

**优点：**
- ✅ 完全自动化
- ✅ 自动适配新的 MCP 包
- ✅ 生成的清单可复用

**缺点：**
- ❌ 错误匹配规则需要维护
- ❌ 可能漏检一些依赖
- ❌ 开发复杂度较高

**适用阶段：** 项目成熟后的增强功能

---

### 方案 4：社区协作（众包）⭐⭐⭐ 最佳长期方案

**做法：**
建立社区仓库，用户贡献 MCP 依赖清单

**实现：**
```bash
# 1. 创建 GitHub 仓库：gabox-mcp-deps
gabox-mcp-deps/
├── playwright.yml
├── puppeteer.yml
├── brave-search.yml
└── README.md

# 2. gabox 自动从仓库拉取清单
gabox mcp add playwright
# 输出：
# 🔍 从社区仓库获取 playwright 依赖清单...
# 📥 下载: https://raw.githubusercontent.com/gravtice/gabox-mcp-deps/main/playwright.yml
# 📦 安装依赖...

# 3. 用户贡献流程
# 用户测试新 MCP -> 提交 PR 到 gabox-mcp-deps -> 合并后所有人受益
```

**GitHub 仓库结构：**
```
gabox-mcp-deps/
├── README.md              # 贡献指南
├── deps/                  # 依赖清单
│   ├── playwright.yml
│   ├── puppeteer.yml
│   ├── brave-search.yml
│   └── ...
├── scripts/              # 验证脚本
│   └── validate.sh       # 验证 YAML 格式
└── .github/
    └── workflows/
        └── validate.yml  # CI 自动验证
```

**优点：**
- ✅ 社区驱动，可持续
- ✅ 覆盖面广（用户贡献）
- ✅ 版本控制（Git）
- ✅ 质量保证（PR review）

**缺点：**
- ❌ 需要社区活跃度
- ❌ 初期清单较少

---

## 推荐实施路径

### 阶段 1：手动维护（立即开始）

1. **初始清单**：项目维护者手动测试 5-10 个常用 MCP，编写 YAML
   ```
   AgentBox/mcp-deps/
   ├── playwright.yml       # 手动测试并编写
   ├── puppeteer.yml
   ├── brave-search.yml
   ├── filesystem.yml
   └── memory.yml
   ```

2. **本地优先**：gabox 优先使用项目自带的清单
   ```bash
   # gabox 查找顺序:
   # 1. ~/.gabox/mcp-deps/playwright.yml  (用户自定义)
   # 2. /path/to/AgentBox/mcp-deps/playwright.yml  (项目自带)
   # 3. 跳过依赖安装
   ```

### 阶段 2：社区协作（2-3 个月后）

1. **创建社区仓库**：`github.com/gravtice/gabox-mcp-deps`
2. **自动同步**：gabox 定期从仓库拉取更新
   ```bash
   gabox mcp update-registry
   # 输出：
   # 📥 从社区仓库更新依赖清单...
   # ✅ 新增: 5 个 MCP
   # ✅ 更新: 3 个 MCP
   ```

3. **用户贡献**：提供模板和文档，鼓励用户提交新 MCP 的清单

### 阶段 3：自动检测（6 个月后）

1. **智能分析**：实现方案 3 的运行时检测
2. **辅助生成**：自动生成初稿清单，人工审核后提交社区
   ```bash
   gabox mcp analyze @some-new-mcp
   # 输出：
   # 🔍 自动分析 MCP 依赖...
   # 📝 生成清单: mcp-deps/some-new-mcp.yml
   # 💡 提示: 请审核清单并提交到社区仓库
   ```

---

## 实际示例：Playwright 依赖清单如何获得

### 手动测试过程（记录）

```bash
# 1. 启动干净的基础容器
docker run -it gabox-dev:base bash

# 2. 尝试安装 @playwright/mcp
npm install -g @playwright/mcp@latest
# ✅ 成功（只是 npm 包）

# 3. 尝试运行
npx @playwright/mcp
# ❌ 错误: playwright 未安装

# 4. 安装 playwright
npm install -g playwright
npx @playwright/mcp
# ❌ 错误: Could not find browser

# 5. 安装浏览器
npx playwright install chromium
# ❌ 错误: Failed to download...
#   Host system is missing dependencies: libnss3, libnspr4, ...

# 6. 安装系统依赖
apt-get update
apt-get install -y \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2

# 7. 再次安装浏览器
npx playwright install chromium
# ✅ 成功！

# 8. 测试 MCP
npx @playwright/mcp
# ✅ 成功运行！

# 9. 记录为 YAML
cat > playwright.yml <<EOF
name: playwright
package: "@playwright/mcp@latest"
tested_date: 2025-01-04
tested_by: gabox-team
dependencies:
  npm:
    - "playwright@1.48.0"
  system:
    - libnss3
    - libnspr4
    - libatk1.0-0
    - libatk-bridge2.0-0
    - libcups2
    - libdrm2
    - libdbus-1-3
    - libxkbcommon0
    - libatspi2.0-0
    - libxcomposite1
    - libxdamage1
    - libxfixes3
    - libxrandr2
    - libgbm1
    - libpango-1.0-0
    - libcairo2
    - libasound2
  post_install:
    - "npx playwright install chromium"
  env:
    PLAYWRIGHT_DOWNLOAD_HOST: "https://npmmirror.com/mirrors/playwright/"
notes: |
  需要约 200MB 下载浏览器二进制文件。
  首次安装较慢，建议使用环境变量配置国内镜像。
EOF
```

### 这个过程可以半自动化

创建测试脚本 `scripts/test-mcp-deps.sh`:

```bash
#!/bin/bash
# 用于测试 MCP 依赖的脚本

MCP_PACKAGE="$1"
LOG_FILE="mcp-test-$(basename $MCP_PACKAGE).log"

echo "🧪 测试 MCP: $MCP_PACKAGE"
echo "📝 日志: $LOG_FILE"

# 在临时容器中测试
docker run --rm -it gabox-dev:base bash -c "
    set -e

    echo '=== 安装 MCP ===' | tee -a $LOG_FILE
    npm install -g $MCP_PACKAGE 2>&1 | tee -a $LOG_FILE

    echo '=== 测试运行 ===' | tee -a $LOG_FILE
    timeout 5 npx $MCP_PACKAGE 2>&1 | tee -a $LOG_FILE || true

    echo '=== 依赖检查 ===' | tee -a $LOG_FILE
    npm list -g --depth=0 2>&1 | tee -a $LOG_FILE
"

echo ""
echo "📊 测试完成！请查看日志: $LOG_FILE"
echo "💡 根据日志中的错误信息编写 YAML 清单"
```

---

## 总结

**当前最佳方案：**

1. **启动阶段**（现在）：手动测试 + 编写 YAML（方案 1）
   - 项目自带 5-10 个常用 MCP 的清单
   - 提供文档教用户如何自己编写清单

2. **成长阶段**（2-3 月后）：社区协作（方案 4）
   - 创建 GitHub 仓库收集社区贡献
   - gabox 自动从仓库同步

3. **成熟阶段**（6 月后）：自动检测（方案 3）
   - 实现智能依赖分析
   - 自动生成清单初稿

**关键点：**
- npm 包信息**不包含系统依赖**，必须通过实际运行测试获得
- 手动维护是不可避免的，但可以通过社区协作分摊工作
- 自动化只能作为辅助，最终还需人工验证
