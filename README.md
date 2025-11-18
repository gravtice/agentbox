# AgentBox

> 容器化的 AI Agent 运行工具，支持 Claude Code、Codex、Gemini 等多种 AI Agent

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![Version](https://img.shields.io/badge/Version-1.0.1-green.svg)](./VERSION)

## ✨ 特性

- 🚀 **一键启动** - 自动创建和管理容器，如同本地使用
- 🔐 **OAuth 共享** - 所有容器共享登录态，无需重复登录
- 🌐 **远程控制** - 支持 Happy 远程模式，随时随地在手机上控制 AI Agent
- 📦 **完全隔离** - 每个项目独立容器，目录、进程、网络完全隔离，互不影响
- 🛡️ **安全模式** - 自动跳过权限询问，安全无害的 YOLO 模式
- 🧹 **可选清理** - 支持退出时自动删除容器，保持环境整洁
- ⚙️ **灵活配置** - 支持端口映射、参考目录、代理等丰富配置
- ⌨️ **智能补全** - 提供 Zsh 自动补全插件

## 📋 前置要求

- Docker（支持 Docker Desktop、OrbStack 等）
- bash
- jq（JSON 处理工具）

### 安装依赖

**macOS:**
```bash
brew install jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq
```

## 🚀 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/Gravtice/AgentBox.git
cd AgentBox
```

### 2. 构建镜像

```bash
./gbox build
```

### 3. 启动 AI Agent

```bash
# 本地模式：在当前目录启动 Claude Code
./gbox claude

# 远程控制模式：启动 Happy + Claude Code
./gbox happy claude

# 启动其他 AI Agent
./gbox codex                            # 启动 Codex
./gbox gemini                           # 启动 Gemini

# 指定工作目录
cd ~/projects/myapp
./gbox claude
```

就这么简单！容器会自动创建、启动，退出时可选择自动清理。

> 💡 **提示**: 查看 [快速入门指南](./QUICKSTART.md) 了解更多使用方法

## 📖 文档

### 用户文档
- [快速入门](./QUICKSTART.md) - 5分钟上手指南
- [架构设计](./docs/ARCHITECTURE.md) - 了解 AgentBox 的设计理念
- [自定义镜像](./docs/CUSTOM_IMAGE.md) - 制作自己的 Agent 镜像
- [资源配置](./docs/RESOURCE_CONFIG.md) - 内存、CPU、端口等配置
- [Worktree 支持](./docs/WORKTREE_SUPPORT.md) - Git worktree 并行开发
- [Zsh 补全](./zsh-completion/README.md) - 智能命令补全插件

### 开发者文档
- [贡献指南](./CONTRIBUTING.md) - 如何参与项目开发
- [变更日志](./CHANGELOG.md) - 版本更新记录

## 🎯 使用场景

### 场景 1: 日常开发

```bash
cd ~/projects/my-webapp
./gbox claude
# Claude Code 启动，开始编码...
# Ctrl+D 退出，容器可自动清理（默认保留）
```

### 场景 2: 多项目管理

```bash
# 项目 A
cd ~/projects/project-a
./gbox claude    # 容器: gbox-claude-project-a

# 项目 B
cd ~/projects/project-b
./gbox claude    # 容器: gbox-claude-project-b

# 查看所有容器
./gbox list
```

### 场景 3: 远程控制

```bash
cd ~/projects/team-project
./gbox happy claude
# 1. Happy daemon 启动
# 2. Claude Code 启动
# 3. 在手机上通过 Happy App 远程控制
```

### 场景 4: 自定义资源配置

```bash
# 大型项目需要更多资源
./gbox claude --memory 16g --cpu 8

# 需要访问容器内服务
./gbox claude --ports "8000:8000;3000:3000"

# 跨项目参考其他代码
./gbox claude --ref-dirs "/path/to/reference-project"
```

## 🔧 常用命令

```bash
# Agent 启动
./gbox claude               # 启动 Claude Code
./gbox happy claude         # 启动 Happy + Claude Code
./gbox codex                # 启动 Codex

# 容器管理
./gbox list                 # 查看运行中的容器
./gbox status               # 查看所有容器状态
./gbox stop <容器名>        # 停止容器
./gbox logs <容器名>        # 查看容器日志
./gbox shell <容器名>       # 登录容器 shell

# 镜像管理
./gbox build                # 构建镜像
./gbox pull                 # 拉取预构建镜像

# OAuth 管理
./gbox oauth claude status  # 查看账号状态
./gbox oauth claude switch  # 切换账号
```

## ⚙️ 配置示例

### 环境变量配置

```bash
# 设置默认资源限制
export GBOX_MEMORY=8g
export GBOX_CPU=4

# 设置默认端口映射
export GBOX_PORTS="8000:8000;3000:3000"

# 启动时使用环境变量配置
./gbox claude
```

### 命令行参数

```bash
# 完整配置示例
./gbox claude \
  --memory 16g \
  --cpu 8 \
  --ports "8000:8000;5432:5432" \
  --ref-dirs "/path/to/ref1;/path/to/ref2" \
  --proxy "http://127.0.0.1:7890" \
  -- --model sonnet
```

## 🏗️ 架构概览

```
宿主机                          容器
~/.gbox/
├── claude/         →     ~/.claude/           (Claude 配置共享)
├── happy/          →     ~/.happy/            (Happy 配置共享)
├── .gitconfig      →     ~/.gitconfig         (Git 配置)
├── cache/          →     /tmp/.cache/         (依赖缓存)
└── logs/           →     /var/log/gbox.log   (日志)

~/projects/myapp/   →     ~/projects/myapp/   (工作目录)
```

容器命名规则:
```bash
~/projects/my-webapp     → gbox-claude-my-webapp
~/code/backend-api       → gbox-happy-claude-backend-api
```

详见 [架构设计文档](./docs/ARCHITECTURE.md)

## 🐛 故障排查

### 容器无法启动

```bash
# 查看容器日志
./gbox logs <容器名>

# 检查 Docker 状态
docker ps -a | grep gbox
```

### OAuth 登录问题

```bash
# 查看账号状态
./gbox oauth claude status

# 切换账号
./gbox oauth claude switch
```

### 端口冲突

```bash
# 使用不同端口
./gbox claude --ports "8888:8000"
```

更多问题请查看 [故障排查文档](./QUICKSTART.md#故障排查)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

参与贡献前请阅读 [贡献指南](./CONTRIBUTING.md)

## 📄 许可证

本项目采用 [Apache License 2.0](./LICENSE) 许可证。

### 第三方组件

本项目包含以下使用不同许可证的第三方组件：

- **happy, happy-cli, happy-server** (vendor/ 目录)
  - 许可证: MIT License
  - 这些组件作为 Git 子模块引入，保持其原有 MIT 许可证

详见 [NOTICE](./NOTICE) 文件了解完整的第三方组件信息。

## 🙏 致谢

- [Claude Code](https://claude.ai/code) - Anthropic 的 AI 编程助手
- [Happy](https://happy.engineering) - 远程控制平台，随时随地在手机上控制电脑
- [Docker](https://www.docker.com/) - 容器化平台

## 📮 联系方式

- Issues: [GitHub Issues](https://github.com/Gravtice/AgentBox/issues)
- Discussions: [GitHub Discussions](https://github.com/Gravtice/AgentBox/discussions)

---

**享受容器化的 AI Agent 开发体验！** 🚀
