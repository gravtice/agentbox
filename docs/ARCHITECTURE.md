# AgentBox Architecture Design

This document introduces the core design philosophy and technical architecture of AgentBox.

## 🎯 Design Goals

1. **Simple and Easy to Use** - Start with a single command, automatic container lifecycle management
2. **Shared Configuration** - All containers share OAuth sessions and configurations
3. **Resource Isolation** - Each project runs in its own container, no interference
4. **Flexible Extension** - Support for multiple AI Agents and runtime modes

## 📐 Core Concepts

### Working Directory-Driven

The core philosophy of AgentBox is "working directory-driven":

```
Working Directory → Auto-generate Container Name → Auto-manage Container
```

**Examples:**
```bash
~/projects/my-webapp  → gbox-my-webapp
~/code/api-service    → gbox-api-service
```

**Key principle:** One repository corresponds to one container, regardless of agent or run mode.

**Advantages:**
- No need to manually specify container names
- Natural isolation between multiple projects
- Predictable container names
- Consistent container across all agents (claude, codex, gemini) and modes (local/remote)

### Configuration Sharing Mechanism

All containers share configurations under the `~/.gbox/` directory:

```
~/.gbox/
├── claude/           # Claude Code config (shared)
├── happy/            # Happy config (shared)
├── .gitconfig        # Git config (shared, read-only)
├── cache/            # Dependency caches (shared)
└── containers.json   # Container mapping state
```

**Shared content:**
- OAuth sessions (`claude/.claude.json`)
- MCP server configurations
- Git user information
- Dependency caches (pip, npm, uv)

**Independent content:**
- Working directory (project code)
- Container runtime state
- Temporary files

## 🏗️ Architecture Layers

### 1. User Layer

```
User Commands
   ↓
./gbox claude
./gbox happy claude
./gbox codex
```

**Responsibilities:**
- Provide simple CLI interface
- Parameter parsing and validation
- User-friendly prompts

### 2. Container Management Layer

**lib/container.sh** - Container lifecycle management

Main functions:
- `start_container()` - Create/start container
- `stop_container()` - Stop/delete container
- `generate_container_name()` - Generate container name
- `get_main_repo_dir()` - Git worktree support

**lib/docker.sh** - Docker basic operations

Main functions:
- `ensure_docker_network()` - Ensure network exists
- `is_container_running()` - Check container status
- `get_worktree_dir()` - Worktree directory management

### 3. Agent Session Layer

**lib/agent.sh** - AI Agent session management

Main functions:
- `run_agent_session()` - Start Agent session
- Support for local mode / Happy remote mode
- Parameter pass-through to Agent

### 4. Configuration Management Layer

**lib/state.sh** - State and configuration management

Main functions:
- `init_gbox_config()` - Initialize config directories
- `init_git_config()` - Initialize Git config
- `add_container_mapping()` - Container mapping management
- `remove_container_mapping()` - Clean up mappings

**lib/oauth.sh** - OAuth account management

Main functions:
- `scan_oauth_accounts()` - Scan all accounts
- `switch_oauth_account()` - Switch accounts
- `check_token_expiry()` - Check token expiration

### 5. Image Management Layer

**lib/image.sh** - Image build and management

Main functions:
- `build_image()` - Build image
- `pull_image()` - Pull image
- `push_image()` - Push image

## 🔄 Startup Flow

### Local Mode (`./gbox claude`)

```
1. Parse parameters
   ↓
2. Check Docker environment
   ↓
3. Initialize config (~/.gbox/)
   ↓
4. Generate container name (gbox-{dirname})
   ├─ Detect main repository directory (supports worktrees)
   └─ Same name for all agents and modes
   ↓
5. Check if container exists
   ├─ Exists: Connect to existing container
   └─ Not exists: Create new container
      ↓
6. Mount directories
   - Work directory: ~/projects/myapp
   - Config directory: ~/.gbox/claude → ~/.claude
   - Git config: ~/.gbox/.gitconfig → ~/.gitconfig
   - Cache directories: ~/.gbox/cache → /tmp/.cache
   ↓
7. Start Claude Code
   ↓
8. User interaction
   ↓
9. Clean up container on exit (default)
```

### Happy Remote Mode (`./gbox happy claude`)

```
1-6. Same as local mode
   ↓
7. Start Happy Daemon
   ↓
8. Start Claude Code (managed by Happy)
   ↓
9. Mobile app can connect
   ↓
10. User interaction
   ↓
11. Clean up container on exit (default)
```

## 🌐 Happy Remote Control Architecture

### Component Overview

Happy provides a complete remote control solution, allowing you to control AI Agents on your computer from anywhere using your mobile device.

**Three main components**:

1. **happy-daemon** (`vendor/happy-cli`)
   - Daemon process running inside the container
   - Manages the lifecycle of Claude Code, Codex, and other Agents
   - Handles terminal I/O and command execution
   - Maintains connection with happy-server

2. **happy-server** (`vendor/happy-server`)
   - Cloud relay server
   - Establishes communication channel between daemon and remote-app
   - Handles authentication and session management
   - Supports multiple simultaneous device connections

3. **happy-remote-app** (`vendor/happy`)
   - Mobile client (iOS/Android App)
   - Provides terminal interface and interaction
   - Supports real-time viewing and operation
   - Multi-session management

### Communication Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Host Machine                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                Container (gbox-{project})                  │  │
│  │                                                            │  │
│  │  ┌──────────────────┐         ┌────────────────────┐     │  │
│  │  │  happy-daemon    │←───────→│   Claude Code      │     │  │
│  │  │  (Daemon)        │  Manage │   (AI Agent)       │     │  │
│  │  │                  │         │                    │     │  │
│  │  │  - Terminal I/O  │         │  - Code Analysis   │     │  │
│  │  │  - Cmd Exec      │         │  - File Ops        │     │  │
│  │  │  - Session Mgmt  │         │  - Git Ops         │     │  │
│  │  └────────┬─────────┘         └────────────────────┘     │  │
│  │           │                                               │  │
│  └───────────┼───────────────────────────────────────────────┘  │
│              │ WebSocket / HTTPS                                │
└──────────────┼──────────────────────────────────────────────────┘
               │
               │ Internet
               │
       ┌───────▼────────┐
       │  happy-server  │
       │  (Cloud Relay) │
       │                │
       │  - Auth        │
       │  - Msg Routing │
       │  - Session Mgmt│
       └───────┬────────┘
               │
               │ WebSocket / HTTPS
               │
     ┌─────────▼──────────┐
     │  happy-remote-app  │
     │  (Mobile App)      │
     │                    │
     │  - Terminal UI     │
     │  - Cmd Input       │
     │  - Real-time View  │
     │  - Multi-session   │
     └────────────────────┘
```

### Data Flow

#### 1. Command Execution Flow

```
Mobile app inputs command
    ↓
happy-remote-app sends command
    ↓
happy-server routes message
    ↓
happy-daemon receives command
    ↓
Passes to Claude Code
    ↓
Claude Code executes
    ↓
Returns result to happy-daemon
    ↓
happy-server forwards
    ↓
happy-remote-app displays result
```

#### 2. Session Initialization Flow

```
Container starts
    ↓
happy-daemon starts
    ↓
Reads ~/.happy/ config (OAuth token)
    ↓
Connects to happy-server
    ↓
Authentication successful, establishes WebSocket connection
    ↓
Starts Claude Code
    ↓
Waits for remote-app connection
    ↓
remote-app scans QR code or enters pairing code
    ↓
Establishes remote session
    ↓
Remote control is ready
```

### Configuration Sharing

Happy's configuration also uses the sharing mechanism:

```
~/.gbox/happy/
├── config.json           # Happy daemon config
├── .auth.json            # Authentication token
└── sessions/             # Session cache
```

All containers share the same Happy account, no need to login repeatedly.

### Security Features

1. **End-to-End Encryption**: All communication encrypted via TLS/SSL
2. **OAuth Authentication**: Uses OAuth 2.0 for identity verification
3. **Session Isolation**: Each project has independent session, no interference
4. **Permission Control**: Auto-bypass permission checks via `HAPPY_AUTO_BYPASS_PERMISSIONS=1` (trusted environments only)

### Network Requirements

- **Outbound Connection**: Container needs to access happy-server (HTTPS/WebSocket)
- **Ports**: No inbound ports need to be opened
- **Firewall**: Allow container to access internet
- **Proxy Support**: HTTP/SOCKS5 proxy supported via `--proxy` parameter

### Failure Recovery

Happy provides automatic reconnection mechanism:

```bash
# If happy-daemon disconnects from server
# It will automatically retry connection (exponential backoff)

# Users can see connection status on remote-app
# Shows "Connection Lost" when disconnected
# Automatically resumes session when reconnected
```

### Performance Optimization

1. **Incremental Transmission**: Only transmits changed terminal content
2. **Compression**: WebSocket messages use gzip compression
3. **Heartbeat Keepalive**: Periodic heartbeat to avoid connection timeout
4. **Local Cache**: remote-app caches session history

## 📦 Container Structure

### Mount Points

```
Host                            Container                         Mode    Description
~/.gbox/claude/         →  ~/.claude/                        rw      Claude config shared
~/.gbox/happy/          →  ~/.happy/                         rw      Happy config shared
~/.gbox/.gitconfig      →  ~/.gitconfig                      ro      Git config (read-only)
~/projects/myapp/       →  ~/projects/myapp/                 rw      Working directory
~/.gbox/cache/pip       →  /tmp/.cache/pip                   rw      pip cache
~/.gbox/cache/npm       →  /tmp/.npm                         rw      npm cache
~/.gbox/cache/uv        →  /tmp/.cache/uv                    rw      uv cache
~/.gbox/logs/xxx.log    →  /var/log/gbox.log                 rw      Container logs
```

### Symbolic Links

Claude Code expects config file at `~/.claude.json`, but we store it at `~/.claude/.claude.json`:

```bash
# Automatically created on container startup
~/.claude.json → ~/.claude/.claude.json
```

### Environment Variables

Environment variables injected into the container:

```bash
GBOX_WORK_DIR=/path/to/project        # Working directory
GBOX_MAIN_DIR=/path/to/main-repo      # Main repository (worktree support)
GBOX_RUN_MODE=only-local              # Run mode
ANTHROPIC_API_KEY=xxx                 # API Key (optional)
HAPPY_AUTO_BYPASS_PERMISSIONS=1       # Auto-bypass permission checks
DEBUG=                                # Debug logs (user-controlled)
```

Proxy environment variables (if configured):
```bash
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
# Plus lowercase variants
```

## 🔐 OAuth Management

### File Structure

```
~/.gbox/claude/
├── .claude.json                        # Currently active account
├── .claude.json-user@example.com-001  # Account backup 1
├── .claude.json-other@example.com-001 # Account backup 2
├── .oauth-account-user@example.com-001.json   # Account metadata 1
└── .oauth-account-other@example.com-001.json  # Account metadata 2
```

### Account Switching Flow

```
1. Scan all accounts under ~/.gbox/claude/
   ↓
2. Read metadata for each account
   - Email
   - Usage (used count)
   - Limit (total limit)
   - Reset Time (reset time)
   ↓
3. Display account list for user selection
   ↓
4. Backup current account
   ↓
5. Activate selected account (copy as .claude.json)
   ↓
6. Prompt to restart container for changes to take effect
```

### Auto-Switching (Keepalive)

When account limit is detected, automatically switch to available account:

```bash
# Start keepalive monitoring
./gbox keepalive start

# Auto-switch logic
while true; do
  if account_limit_reached; then
    switch_to_available_account
    restart_container
  fi
  sleep 60
done
```

## 🌐 Network and Ports

### Docker Network

All containers connect to `gbox-network` (bridge mode):

```bash
docker network create gbox-network
```

**Advantages:**
- Containers can communicate via container names
- Isolated from other host containers
- Support for custom DNS resolution

### Port Mapping

**Default behavior:** No port mapping

**Custom mapping:**
```bash
GBOX_PORTS="8000:8000;3000:3000"
```

**Bind address:** All ports bound to `127.0.0.1` (localhost only)

```bash
-p 127.0.0.1:8000:8000
-p 127.0.0.1:3000:3000
```

## 🔧 Git Worktree Support

### Directory Convention

```
/path/to/project/                # Main repository
/path/to/project-worktrees/      # Worktrees directory
  ├── feature-a/                 # Worktree 1
  └── feature-b/                 # Worktree 2
```

### Detection Logic

```bash
# 1. Git command detection
git rev-parse --git-common-dir

# 2. Directory naming inference
if [[ "$parent_dir" == *"-worktrees" ]]; then
  main_dir="${parent_dir%-worktrees}"
fi
```

### Mount Strategy

```bash
# Mount both main directory and worktrees directory
-v /path/to/project:/path/to/project
-v /path/to/project-worktrees:/path/to/project-worktrees
```

**Advantages:**
- Worktree can access main repository .git
- Free switching between worktrees inside container
- Multiple worktrees use the same container

## 📊 Resource Management

### Default Limits

```bash
--memory 4g              # Memory limit
--cpus 2                 # CPU cores
```

### Cache Directories

Dependency caches significantly speed up installation:

```
~/.gbox/cache/
├── pip/       # Python pip cache
├── npm/       # Node.js npm cache
└── uv/        # Python uv cache
```

**Mounted to container:**
```bash
-v ~/.gbox/cache/pip:/tmp/.cache/pip
-v ~/.gbox/cache/npm:/tmp/.npm
-v ~/.gbox/cache/uv:/tmp/.cache/uv
```

## 🎨 Modular Design

### Module Responsibilities

| Module | File | Lines | Responsibility |
|------|------|------|------|
| Common Utils | lib/common.sh | 313 | Constants, colors, help docs |
| State Mgmt | lib/state.sh | 191 | Config init, container mapping |
| Docker Ops | lib/docker.sh | 74 | Network, container status check |
| Container Mgmt | lib/container.sh | 655 | Container lifecycle |
| Agent Session | lib/agent.sh | 365 | Agent startup and params |
| Image Mgmt | lib/image.sh | 173 | Image build, pull |
| OAuth Mgmt | lib/oauth.sh | 659 | Account switching, token check |
| Keepalive | lib/keepalive.sh | 822 | Auto-maintain login sessions |

### Module Dependencies

```
gbox (Main script 238 lines)
 │
 ├─ common.sh          (no dependencies)
 ├─ state.sh           (→ common)
 ├─ docker.sh          (→ common, state)
 ├─ container.sh       (→ docker, state, common)
 ├─ agent.sh           (→ container)
 ├─ image.sh           (→ common)
 ├─ oauth.sh           (→ state, common)
 └─ keepalive.sh       (→ oauth, container, docker)
```

See [Project Structure Documentation](./dev/PROJECT_STRUCTURE.md) for details

## 🚀 Performance Optimization

### 1. Dependency Caching

All containers share dependency caches, avoiding redundant downloads:

```bash
# First installation: Download from network
pip install numpy  # Download + cache

# Subsequent installations: Read from cache
pip install numpy  # Completes in seconds
```

### 2. Image Layering

Uses multi-stage build to optimize image size:

```dockerfile
# Stage 1: Build happy-cli
FROM node:20-slim AS happy-builder
...

# Stage 2: Final image (excludes build dependencies)
FROM python:3.12-slim
COPY --from=happy-builder /build/happy-coder-*.tgz /tmp/
...
```

### 3. Configuration File Sharing

All containers share configuration, avoiding redundant storage:

```bash
# Single OAuth config file
~/.gbox/claude/.claude.json  # Shared by all containers
```

## 🔒 Security Design

### 1. Container Isolation

- Each project has independent container
- Uses non-root user (guser)
- Memory and CPU limits

### 2. Port Binding

- No port mapping by default
- When needed, bind to 127.0.0.1 (localhost only)

### 3. Read-Only Reference Directories

```bash
# Mount reference directories as read-only to prevent accidental modification
-v /path/to/ref:ro
```

### 4. Read-Only Git Config

```bash
# Git config mounted as read-only
-v ~/.gbox/.gitconfig:~/.gitconfig:ro
```

## 📈 Extensibility

### 1. Support for New Agents

Adding a new Agent only requires:

```bash
# Add in lib/agent.sh
case "$agent" in
  claude|codex|gemini)
    ...
  ;;
  new-agent)  # New addition
    ...
  ;;
esac
```

### 2. Custom Images

Users can create custom images based on the standard image:

```dockerfile
FROM gravtice/agentbox:latest

# Install custom tools
RUN apt-get update && apt-get install -y xxx

# Install custom dependencies
RUN pip install xxx
```

See [Custom Image Documentation](../CUSTOM_IMAGE.md) for details

### 3. Pluggable MCP Servers

Extend functionality through MCP configuration:

```bash
./gbox claude -- mcp add -s user my-tool -- npx my-mcp-server
```

## 📚 References

- [Quick Start](../QUICKSTART.md) - 5-minute getting started guide
- [Developer Documentation](./dev/README.md) - Internal implementation details

---

**Design Principles**: Simple, Reliable, Flexible
