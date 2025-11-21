# Gravtice AgentBox

> Containerized AI Agent runtime tool, currently supporting Claude Code, Codex, and Gemini CLI

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![Version](https://img.shields.io/badge/Version-1.0.7-green.svg)](./VERSION)

## ✨ Features

- 🚀 **One-Click Startup** - Automatically creates and manages containers, just like local usage
- 🔐 **Shared OAuth** - All containers share login sessions, no repeated authentication
- 🌐 **Remote Control** - Supports Happy remote mode, control AI Agents from your phone anywhere, anytime
- 📦 **Complete Isolation** - Each project gets its own container with fully isolated directories, processes, and networks
- 🛡️ **Safe Mode** - Automatically skips permission prompts with a safe and harmless YOLO mode
- 🔒 **Git Protection** - Built-in protection prevents AI agents from accidentally deleting `.git` directories
- 🧹 **Optional Cleanup** - Supports automatic container deletion on exit to keep your environment clean
- ⚙️ **Flexible Configuration** - Rich configuration options including port mapping, reference directories, proxy settings, and more
- ⌨️ **Smart Completion** - Provides Zsh auto-completion plugin

## 📋 Prerequisites

- Docker (supports Docker Desktop, OrbStack, etc.)
- bash
- jq (JSON processing tool)

### Installing Dependencies

**macOS:**
```bash
brew install jq
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq
```

## 📦 Installation

AgentBox provides a one-click installation script that automatically:
- Installs `gbox` to `~/.local/bin`
- Configures PATH in your shell
- Installs shell completion (if available)

### Quick Installation

```bash
# Clone the repository
git clone https://github.com/Gravtice/AgentBox.git
cd AgentBox

# Run installation script
./install.sh

# Reload shell configuration
source ~/.zshrc  # or source ~/.bashrc
```

After installation, you can use `gbox` command from anywhere:

```bash
# Verify installation
gbox --version

# Pull or build the image
gbox pull        # Pull pre-built image (recommended)
gbox build       # Or build locally

# Start using it
cd ~/projects/myapp
gbox claude
```

### Manual Installation

If you prefer not to install system-wide, you can use `gbox` directly from the cloned repository:

```bash
cd /path/to/AgentBox
./gbox claude
```

### Uninstallation

To uninstall AgentBox:

```bash
cd /path/to/AgentBox
./uninstall.sh
```

The uninstall script will:
- Stop and remove all AgentBox containers
- Remove `gbox` from `~/.local/bin`
- Clean up PATH configuration
- Optionally remove configuration data from `~/.gbox`

## 🚀 Quick Start

### 1. Pull or Build the Image

```bash
# Option 1: Pull pre-built image (faster, recommended)
gbox pull

# Option 2: Build locally (slower, for custom modifications)
gbox build
```

### 2. Start an AI Agent

```bash
# Local mode: Start Claude Code in current directory
gbox claude

# Remote control mode: Start Happy + Claude Code
gbox happy claude

# Start other AI Agents
gbox codex                            # Start Codex
gbox gemini                           # Start Gemini

# Specify working directory
cd ~/projects/myapp
gbox claude
```

That's it! Containers are automatically created and started, with optional automatic cleanup on exit.

> 💡 **Tip**: If you didn't install system-wide, use `./gbox` instead of `gbox`. Check out the [Quick Start Guide](./QUICKSTART.md) for more usage examples

## 📖 Documentation

### User Documentation
- [Quick Start](./QUICKSTART.md) - 5-minute getting started guide
- [Architecture Design](./docs/ARCHITECTURE.md) - Understand AgentBox's design philosophy
- [Custom Images](./docs/CUSTOM_IMAGE.md) - Build your own Agent images
- [Zsh Completion](./zsh-completion/README.md) - Smart command completion plugin

### Developer Documentation
- [Contributing Guide](./CONTRIBUTING.md) - How to contribute to the project
- [Changelog](./CHANGELOG.md) - Version update history

## 🎯 Use Cases

### Scenario 1: Daily Development

```bash
cd ~/projects/my-webapp
gbox claude
# Claude Code starts, begin coding...
# Ctrl+D to exit, container can auto-cleanup (default: kept)
```

### Scenario 2: Multi-Project Management

```bash
# Project A
cd ~/projects/project-a
gbox claude    # Container: gbox-claude-project-a

# Project B
cd ~/projects/project-b
gbox claude    # Container: gbox-claude-project-b

# View all containers
gbox list
```

### Scenario 3: Remote Control

```bash
cd ~/projects/team-project
gbox happy claude
# 1. Happy daemon starts
# 2. Claude Code starts
# 3. Control remotely via Happy App on your phone
```

### Scenario 4: Custom Resource Configuration

```bash
# Large project requiring more resources
gbox claude --memory 16g --cpu 8

# Need to access services inside container
gbox claude --ports "8000:8000;3000:3000"

# Cross-project reference to other code
gbox claude --ref-dirs "/path/to/reference-project"
```

## 🔧 Common Commands

```bash
# Agent startup
gbox claude               # Start Claude Code
gbox happy claude         # Start Happy + Claude Code
gbox codex                # Start Codex

# Container management
gbox list                 # View running containers
gbox status               # View all container status
gbox stop <container-name>        # Stop container
gbox logs <container-name>        # View container logs
gbox shell <container-name>       # Login to container shell

# Image management
gbox build                # Build image
gbox pull                 # Pull pre-built image

# OAuth management
gbox oauth claude status  # Check account status
gbox oauth claude switch  # Switch account

# MCP server management
gbox claude -- mcp list   # List installed MCP servers
gbox claude -- mcp add <name> -s user -- <command>  # Add MCP server
gbox claude -- mcp remove <name>  # Remove MCP server
```

## 🧩 Common MCP Services

Extend Claude Code's capabilities by installing recommended MCP servers:

```bash
# Playwright - Browser automation and web screenshots
gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox

# Codex CLI - Safe terminal command execution
gbox claude -- mcp add codex-cli -s user -- npx -y @cexll/codex-mcp-server

# Filesystem - File system access
gbox claude -- mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /home/guser

# GitHub - GitHub repository operations
gbox claude -- mcp add github -s user -- npx -y @modelcontextprotocol/server-github
```

> 💡 After installation, you need to exit and re-enter the session for changes to take effect. For more MCP servers, see [Quick Start Guide](./QUICKSTART.md#3-mcp-server-management)

## ⚙️ Configuration Examples

### Environment Variable Configuration

```bash
# Set default resource limits
export GBOX_MEMORY=8g
export GBOX_CPU=4

# Set default port mappings
export GBOX_PORTS="8000:8000;3000:3000"

# Start using environment variable configuration
gbox claude
```

### Command Line Parameters

```bash
# Complete configuration example
gbox claude \
  --memory 16g \
  --cpu 8 \
  --ports "8000:8000;5432:5432" \
  --ref-dirs "/path/to/ref1;/path/to/ref2" \
  --proxy "http://127.0.0.1:7890" \
  -- --model sonnet
```

## 🏗️ Architecture Overview

```
Host Machine                    Container
~/.gbox/
├── claude/         →     ~/.claude/           (Claude config sharing)
├── happy/          →     ~/.happy/            (Happy config sharing)
├── .gitconfig      →     ~/.gitconfig         (Git config)
├── cache/          →     /tmp/.cache/         (Dependency cache)
└── logs/           →     /var/log/gbox.log   (Logs)

~/projects/myapp/   →     ~/projects/myapp/   (Working directory)
```

Container naming convention:
```bash
~/projects/my-webapp     → gbox-claude-my-webapp
~/code/backend-api       → gbox-happy-claude-backend-api
```

See [Architecture Design Documentation](./docs/ARCHITECTURE.md) for details

## 🐛 Troubleshooting

### Container Won't Start

```bash
# View container logs
gbox logs <container-name>

# Check Docker status
docker ps -a | grep gbox
```

### OAuth Login Issues

```bash
# Check account status
gbox oauth claude status

# Switch account
gbox oauth claude switch
```

### Port Conflicts

```bash
# Use different ports
gbox claude --ports "8888:8000"
```

### Playwright MCP Browser Conflicts

```bash
# Uninstall and reinstall with --isolated flag
gbox claude -- mcp remove playwright
gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox
```

For more issues, see [Troubleshooting Documentation](./QUICKSTART.md#troubleshooting)

## 🤝 Contributing

Issues and Pull Requests are welcome!

Please read the [Contributing Guide](./CONTRIBUTING.md) before contributing

## 📄 License

This project is licensed under the [Apache License 2.0](./LICENSE).

### Third-Party Components

This project includes the following third-party components licensed under different terms:

- **happy, happy-cli, happy-server** (vendor/ directory)
  - License: MIT License
  - These components are included as Git submodules and retain their original MIT licenses

See the [NOTICE](./NOTICE) file for complete third-party component information.

## 🙏 Acknowledgments

- [Claude Code](https://claude.ai/code) - Anthropic's AI programming assistant
- [Happy](https://happy.engineering) - Remote control platform for controlling your computer from your phone anywhere, anytime
- [Docker](https://www.docker.com/) - Containerization platform

## 📮 Contact

- Issues: [GitHub Issues](https://github.com/Gravtice/AgentBox/issues)
- Discussions: [GitHub Discussions](https://github.com/Gravtice/AgentBox/discussions)

---

**Enjoy the containerized AI Agent development experience!** 🚀
