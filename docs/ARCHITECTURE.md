# AgentBox 架构设计

本文档介绍 AgentBox 的核心设计理念和技术架构。

## 🎯 设计目标

1. **简单易用** - 一个命令启动,自动管理容器生命周期
2. **配置共享** - 所有容器共享 OAuth 登录态和配置
3. **资源隔离** - 每个项目独立容器,互不影响
4. **灵活扩展** - 支持多种 AI Agent 和运行模式

## 📐 核心概念

### 工作目录驱动

AgentBox 的核心思想是"工作目录驱动":

```
工作目录 → 自动生成容器名 → 自动管理容器
```

**示例:**
```bash
~/projects/my-webapp  → gbox-claude-my-webapp
~/code/api-service    → gbox-claude-api-service
```

**优势:**
- 无需手动指定容器名
- 多项目自然隔离
- 容器名可预测

### 配置共享机制

所有容器共享 `~/.gbox/` 目录下的配置:

```
~/.gbox/
├── claude/           # Claude Code 配置 (共享)
├── happy/            # Happy 配置 (共享)
├── .gitconfig        # Git 配置 (共享,只读)
├── cache/            # 依赖缓存 (共享)
└── containers.json   # 容器映射状态
```

**共享内容:**
- OAuth 登录态 (`claude/.claude.json`)
- MCP 服务器配置
- Git 用户信息
- 依赖缓存 (pip, npm, uv)

**独立内容:**
- 工作目录 (项目代码)
- 容器运行时状态
- 临时文件

## 🏗️ 架构分层

### 1. 用户层

```
用户命令
   ↓
./gbox claude
./gbox happy claude
./gbox codex
```

**职责:**
- 提供简洁的 CLI 接口
- 参数解析和验证
- 用户友好的提示

### 2. 容器管理层

**lib/container.sh** - 容器生命周期管理

主要函数:
- `start_container()` - 创建/启动容器
- `stop_container()` - 停止/删除容器
- `generate_container_name()` - 生成容器名
- `get_main_repo_dir()` - Git worktree 支持

**lib/docker.sh** - Docker 基础操作

主要函数:
- `ensure_docker_network()` - 确保网络存在
- `is_container_running()` - 检查容器状态
- `get_worktree_dir()` - Worktree 目录管理

### 3. Agent 会话层

**lib/agent.sh** - AI Agent 会话管理

主要函数:
- `run_agent_session()` - 启动 Agent 会话
- 支持 本地模式 / Happy 远程模式
- 参数透传给 Agent

### 4. 配置管理层

**lib/state.sh** - 状态和配置管理

主要函数:
- `init_gbox_config()` - 初始化配置目录
- `init_git_config()` - 初始化 Git 配置
- `add_container_mapping()` - 容器映射管理
- `remove_container_mapping()` - 清理映射

**lib/oauth.sh** - OAuth 账号管理

主要函数:
- `scan_oauth_accounts()` - 扫描所有账号
- `switch_oauth_account()` - 切换账号
- `check_token_expiry()` - 检查 Token 过期

### 5. 镜像管理层

**lib/image.sh** - 镜像构建和管理

主要函数:
- `build_image()` - 构建镜像
- `pull_image()` - 拉取镜像
- `push_image()` - 推送镜像

## 🔄 启动流程

### 本地模式 (`./gbox claude`)

```
1. 解析参数
   ↓
2. 检查 Docker 环境
   ↓
3. 初始化配置 (~/.gbox/)
   ↓
4. 生成容器名 (gbox-claude-{dir})
   ↓
5. 检查容器是否存在
   ├─ 存在: 连接到已有容器
   └─ 不存在: 创建新容器
      ↓
6. 挂载目录
   - 工作目录: ~/projects/myapp
   - 配置目录: ~/.gbox/claude → ~/.claude
   - Git 配置: ~/.gbox/.gitconfig → ~/.gitconfig
   - 缓存目录: ~/.gbox/cache → /tmp/.cache
   ↓
7. 启动 Claude Code
   ↓
8. 用户交互
   ↓
9. 退出时清理容器 (默认)
```

### Happy 远程模式 (`./gbox happy claude`)

```
1-6. 同本地模式
   ↓
7. 启动 Happy Daemon
   ↓
8. 启动 Claude Code (Happy 管理)
   ↓
9. 手机端可连接
   ↓
10. 用户交互
   ↓
11. 退出时清理容器 (默认)
```

## 📦 容器结构

### 挂载点

```
宿主机                            容器                         权限    说明
~/.gbox/claude/         →  ~/.claude/                        rw    Claude 配置共享
~/.gbox/happy/          →  ~/.happy/                         rw    Happy 配置共享
~/.gbox/.gitconfig      →  ~/.gitconfig                      ro    Git 配置 (只读)
~/projects/myapp/       →  ~/projects/myapp/                 rw    工作目录
~/.gbox/cache/pip       →  /tmp/.cache/pip                   rw    pip 缓存
~/.gbox/cache/npm       →  /tmp/.npm                         rw    npm 缓存
~/.gbox/cache/uv        →  /tmp/.cache/uv                    rw    uv 缓存
~/.gbox/logs/xxx.log    →  /var/log/gbox.log                 rw    容器日志
```

### 符号链接

Claude Code 期望配置文件在 `~/.claude.json`,但我们存储在 `~/.claude/.claude.json`:

```bash
# 容器启动时自动创建
~/.claude.json → ~/.claude/.claude.json
```

### 环境变量

容器内注入的环境变量:

```bash
GBOX_WORK_DIR=/path/to/project        # 工作目录
GBOX_MAIN_DIR=/path/to/main-repo      # 主仓库目录 (worktree 支持)
GBOX_RUN_MODE=only-local              # 运行模式
ANTHROPIC_API_KEY=xxx                 # API Key (可选)
HAPPY_AUTO_BYPASS_PERMISSIONS=1       # 自动跳过权限检查
DEBUG=                                # 调试日志 (用户可控)
```

代理环境变量 (如果设置):
```bash
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
# 及对应的小写变量
```

## 🔐 OAuth 管理

### 文件结构

```
~/.gbox/claude/
├── .claude.json                        # 当前激活的账号
├── .claude.json-user@example.com-001  # 账号备份 1
├── .claude.json-other@example.com-001 # 账号备份 2
├── .oauth-account-user@example.com-001.json   # 账号元数据 1
└── .oauth-account-other@example.com-001.json  # 账号元数据 2
```

### 账号切换流程

```
1. 扫描 ~/.gbox/claude/ 下的所有账号
   ↓
2. 读取每个账号的元数据
   - Email
   - Usage (已用次数)
   - Limit (总限制)
   - Reset Time (重置时间)
   ↓
3. 显示账号列表供用户选择
   ↓
4. 备份当前账号
   ↓
5. 激活选中的账号 (复制为 .claude.json)
   ↓
6. 提示重启容器生效
```

### 自动切换 (Keepalive)

当检测到账号达到限制时,自动切换到可用账号:

```bash
# 启动 keepalive 监控
./gbox keepalive start

# 自动切换逻辑
while true; do
  if account_limit_reached; then
    switch_to_available_account
    restart_container
  fi
  sleep 60
done
```

## 🌐 网络和端口

### Docker 网络

所有容器连接到 `gbox-network` (bridge 模式):

```bash
docker network create gbox-network
```

**优势:**
- 容器间可以通过容器名通信
- 隔离于宿主机其他容器
- 支持自定义 DNS 解析

### 端口映射

**默认行为:** 不映射任何端口

**自定义映射:**
```bash
GBOX_PORTS="8000:8000;3000:3000"
```

**绑定地址:** 所有端口绑定到 `127.0.0.1` (仅本地访问)

```bash
-p 127.0.0.1:8000:8000
-p 127.0.0.1:3000:3000
```

## 🔧 Git Worktree 支持

### 目录规范

```
/path/to/project/                # 主仓库
/path/to/project-worktrees/      # Worktrees 目录
  ├── feature-a/                 # Worktree 1
  └── feature-b/                 # Worktree 2
```

### 检测逻辑

```bash
# 1. Git 命令检测
git rev-parse --git-common-dir

# 2. 目录命名推断
if [[ "$parent_dir" == *"-worktrees" ]]; then
  main_dir="${parent_dir%-worktrees}"
fi
```

### 挂载策略

```bash
# 同时挂载主目录和 worktrees 目录
-v /path/to/project:/path/to/project
-v /path/to/project-worktrees:/path/to/project-worktrees
```

**优势:**
- Worktree 可以访问主仓库 .git
- 容器内可以自由切换 worktree
- 多个 worktree 使用同一个容器

详见 [Worktree 支持文档](./docs/WORKTREE_SUPPORT.md)

## 📊 资源管理

### 默认限制

```bash
--memory 4g              # 内存限制
--cpus 2                 # CPU 核心数
```

### 缓存目录

依赖缓存大幅加速安装:

```
~/.gbox/cache/
├── pip/       # Python pip 缓存
├── npm/       # Node.js npm 缓存
└── uv/        # Python uv 缓存
```

**挂载到容器:**
```bash
-v ~/.gbox/cache/pip:/tmp/.cache/pip
-v ~/.gbox/cache/npm:/tmp/.npm
-v ~/.gbox/cache/uv:/tmp/.cache/uv
```

## 🎨 模块化设计

### 模块职责

| 模块 | 文件 | 行数 | 职责 |
|------|------|------|------|
| 通用工具 | lib/common.sh | 313 | 常量、颜色、帮助文档 |
| 状态管理 | lib/state.sh | 191 | 配置初始化、容器映射 |
| Docker 操作 | lib/docker.sh | 74 | 网络、容器状态检查 |
| 容器管理 | lib/container.sh | 655 | 容器生命周期 |
| Agent 会话 | lib/agent.sh | 365 | Agent 启动和参数 |
| 镜像管理 | lib/image.sh | 173 | 镜像构建、拉取 |
| OAuth 管理 | lib/oauth.sh | 659 | 账号切换、Token 检查 |
| Keepalive | lib/keepalive.sh | 822 | 自动维持登录态 |

### 模块依赖

```
gbox (主脚本 238 行)
 │
 ├─ common.sh          (无依赖)
 ├─ state.sh           (→ common)
 ├─ docker.sh          (→ common, state)
 ├─ container.sh       (→ docker, state, common)
 ├─ agent.sh           (→ container)
 ├─ image.sh           (→ common)
 ├─ oauth.sh           (→ state, common)
 └─ keepalive.sh       (→ oauth, container, docker)
```

详见 [项目结构文档](./docs/dev/PROJECT_STRUCTURE.md)

## 🚀 性能优化

### 1. 依赖缓存

所有容器共享依赖缓存,避免重复下载:

```bash
# 首次安装: 从网络下载
pip install numpy  # 下载 + 缓存

# 后续安装: 从缓存读取
pip install numpy  # 秒级完成
```

### 2. 镜像分层

使用 Multi-stage 构建,优化镜像大小:

```dockerfile
# Stage 1: 构建 happy-cli
FROM node:20-slim AS happy-builder
...

# Stage 2: 最终镜像 (不包含构建依赖)
FROM python:3.12-slim
COPY --from=happy-builder /build/happy-coder-*.tgz /tmp/
...
```

### 3. 配置文件共享

所有容器共享配置,避免重复存储:

```bash
# 单个 OAuth 配置文件
~/.gbox/claude/.claude.json  # 所有容器共享
```

## 🔒 安全设计

### 1. 容器隔离

- 每个项目独立容器
- 使用非 root 用户 (guser)
- 限制内存和 CPU

### 2. 端口绑定

- 默认不映射端口
- 需要时绑定到 127.0.0.1 (仅本地访问)

### 3. 参考目录只读

```bash
# 挂载参考目录为只读,防止误修改
-v /path/to/ref:ro
```

### 4. Git 配置只读

```bash
# Git 配置只读挂载
-v ~/.gbox/.gitconfig:~/.gitconfig:ro
```

## 📈 扩展性

### 1. 支持新 Agent

添加新 Agent 只需:

```bash
# lib/agent.sh 中添加
case "$agent" in
  claude|codex|gemini)
    ...
  ;;
  new-agent)  # 新增
    ...
  ;;
esac
```

### 2. 自定义镜像

用户可以基于标准镜像创建自定义镜像:

```dockerfile
FROM gravtice/agentbox:latest

# 安装自定义工具
RUN apt-get update && apt-get install -y xxx

# 安装自定义依赖
RUN pip install xxx
```

详见 [自定义镜像文档](./CUSTOM_IMAGE.md)

### 3. 插件化 MCP 服务器

通过 MCP 配置扩展功能:

```bash
./gbox claude -- mcp add -s user my-tool -- npx my-mcp-server
```

## 📚 参考资料

- [快速入门](./QUICKSTART.md) - 5分钟上手
- [资源配置](./docs/RESOURCE_CONFIG.md) - 详细配置说明
- [Worktree 支持](./docs/WORKTREE_SUPPORT.md) - Git worktree 文档
- [开发者文档](./docs/dev/README.md) - 内部实现细节

---

**设计原则**: 简单、可靠、灵活
