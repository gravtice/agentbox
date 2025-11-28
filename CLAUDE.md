# Project Guidelines

This file provides guidance to Claude-Code/Codex/Gemini-CLI when working with code in this repository.

## Project Overview

**AgentBox** is a containerized AI Agent runtime environment that provides isolated, sharable execution environments for Claude Code, Codex, and Gemini CLI. It automatically manages Docker containers, OAuth sessions, and provides features like remote control via Happy, dependency caching, and git worktree support.

### Happy Remote Control Components

AgentBox integrates Happy for remote control capabilities, enabling you to control AI Agents from mobile devices:

1. **happy-daemon** (`vendor/happy-cli`)
   - Runs inside the container as a daemon process
   - Manages AI Agent lifecycle (Claude Code, Codex, etc.)
   - Handles terminal I/O and command execution
   - Maintains connection with happy-server
   - Source: Git submodule at `vendor/happy-cli`

2. **happy-server** (`vendor/happy-server`)
   - Cloud relay server for communication
   - Routes messages between daemon and remote-app
   - Handles authentication and session management
   - Supports multiple device connections
   - Source: Git submodule at `vendor/happy-server`

3. **happy-remote-app** (`vendor/happy`)
   - Mobile client (iOS/Android App)
   - Provides terminal interface and interaction
   - Supports real-time viewing and operation
   - Multi-session management
   - Source: Git submodule at `vendor/happy`

**Communication flow**:
```
Mobile App (happy-remote-app)
  ↕ WebSocket/HTTPS ↕
Cloud Server (happy-server)
  ↕ WebSocket/HTTPS ↕
Container Daemon (happy-daemon)
  ↕ Local ↕
AI Agent (Claude Code)
```

See [Happy Architecture](./docs/ARCHITECTURE.md#-happy-remote-control-architecture) for detailed architecture diagrams.

## Core Architecture

### Entry Point and Module System

- **Main script**: `gbox` (322 lines) - Command router that loads all modules
- **Module loading order** (must be maintained):
  1. `lib/common.sh` - Constants, colors, utilities (no dependencies)
  2. `lib/state.sh` - Config initialization, container mappings (→ common)
  3. `lib/docker.sh` - Network, container state checks (→ common, state)
  4. `lib/container.sh` - Container lifecycle (→ docker, state, common)
  5. `lib/agent.sh` - Agent startup and sessions (→ container)
  6. `lib/image.sh` - Image build/pull/push (→ common)
  7. `lib/oauth.sh` - OAuth account management (→ state, common)
  8. `lib/apikey.sh` - API provider management (→ state, common)
  9. `lib/keepalive.sh` - Auto-maintain login sessions (→ oauth, container, docker)

### Directory-Driven Design

AgentBox uses the current working directory to automatically generate container names:

```
~/projects/my-webapp  → gbox-my-webapp
~/code/api-service    → gbox-api-service
```

This enables automatic project isolation without manual container naming. **One repository corresponds to one container**, regardless of which agent (claude, codex, gemini) or run mode (local/remote) you use.

### Shared Configuration

All containers share configurations under `~/.gbox/`:

```
~/.gbox/
├── claude/                   # Claude Code config
│   ├── .claude.json          # OAuth session & MCP servers
│   └── api-providers.json    # API provider configurations
├── happy/                    # Happy config (remote control)
├── .gitconfig                # Git config (read-only mount)
├── .env                      # Shared environment variables (read-only mount)
├── cache/                    # Dependency caches (pip, npm, uv)
└── containers.json           # Container-to-directory mappings
```

**Shared across containers**:
- OAuth login sessions (`claude/.claude.json`)
- API provider configurations (`claude/api-providers.json`)
- MCP server configurations
- Git user information (`.gitconfig`)
- Environment variables (`.env`)
- Dependency caches

**Per-container**:
- Working directory (project code)
- Container runtime state
- Temporary files

### Container Mounts

```
Host                            Container                         Mode    Purpose
~/.gbox/claude/         →  ~/.claude/                        rw      Claude config
~/.gbox/happy/          →  ~/.happy/                         rw      Happy config
~/.gbox/.gitconfig      →  ~/.gitconfig                      ro      Git config
~/.gbox/.env            →  ~/.env                            ro      Environment variables
~/projects/myapp/       →  ~/projects/myapp/                 rw      Work directory
~/.gbox/cache/pip       →  /tmp/.cache/pip                   rw      pip cache
~/.gbox/cache/npm       →  /tmp/.npm                         rw      npm cache
~/.gbox/cache/uv        →  /tmp/.cache/uv                    rw      uv cache
~/.gbox/logs/xxx.log    →  /var/log/gbox.log                 rw      Container logs
```

### Git Worktree Support

AgentBox automatically detects and supports git worktrees:

**Directory convention**:
```
/path/to/project/                # Main repository
/path/to/project-worktrees/      # Worktrees directory
  ├── feature-a/                 # Worktree 1
  └── feature-b/                 # Worktree 2
```

**Detection logic**: See `get_main_repo_dir()` in `lib/docker.sh:67-140`

**Mount strategy**: Both main directory and worktrees directory are mounted, allowing worktrees to access the main `.git` directory.

**Important**: The same container is used whether you start from the main repository or any worktree subdirectory - `get_main_repo_dir()` always returns the main repository path.

## Vendor Directory Structure

AgentBox includes Happy components as git submodules under `vendor/`:

```
vendor/
├── happy-cli/          # Happy daemon (runs in container)
│   ├── src/
│   │   ├── daemon/     # Main daemon implementation
│   │   ├── cli/        # CLI interface
│   │   └── ...
│   └── package.json
│
├── happy-server/       # Happy cloud server
│   ├── src/
│   │   ├── server/     # Server implementation
│   │   ├── auth/       # Authentication
│   │   └── ...
│   └── package.json
│
└── happy/              # Happy mobile app
    ├── ios/            # iOS app source
    ├── android/        # Android app source
    └── ...
```

**Build process**:
- During Docker image build, `happy-cli` is built from source in a multi-stage build
- The compiled package (`happy-coder-*.tgz`) is installed globally in the container
- This ensures the daemon has all necessary patches and modifications

**Submodule management**:
```bash
# Initialize submodules (first time)
git submodule update --init --recursive

# Update submodules to latest
git submodule update --remote

# Check submodule status
git submodule status
```

## Common Development Commands

### Building and Testing

```bash
# Build the Docker image
./gbox build              # Auto-detects timezone, uses China mirrors if in Asia/Shanghai

# Pull pre-built image
./gbox pull

# Test syntax
bash -n gbox
bash -n lib/*.sh

# Test basic functionality
./gbox claude             # Start Claude Code in local mode
./gbox happy claude       # Start Claude Code with Happy remote control
./gbox list               # List running containers
./gbox status             # Show all container status
```

### Container Management

```bash
# List running containers
./gbox list

# Show all container status
./gbox status

# Stop a container
./gbox stop <container-name>

# Stop all containers
./gbox stop-all

# Clean up stopped containers
./gbox clean

# View container logs
./gbox logs <container-name>

# Execute command in container
./gbox exec <container-name> <command>

# Open shell in container
./gbox shell <container-name>
```

### OAuth Management

```bash
# Check current account status
./gbox oauth claude status

# List all accounts
./gbox oauth claude list

# Switch to another account
./gbox oauth claude switch

# Scan for all accounts
./gbox oauth claude scan
```

### API Provider Management

AgentBox supports multiple API providers (Anthropic official, ZhipuAI, DeepSeek, etc.) through persistent configuration management.

```bash
# Add a new API provider
./gbox apikey claude add <name> <api-key> [options]

# Examples:
# Add ZhipuAI provider
./gbox apikey claude add zhipu sk-zhipu-xxx \
  --base-url https://open.bigmodel.cn/api/anthropic \
  --haiku-model glm-4.5-air \
  --sonnet-model glm-4.6 \
  --opus-model glm-4.6 \
  --subagent-model glm-4-flash \
  --timeout 3000000 \
  --description "ZhipuAI API"

# Add Anthropic official (no additional options needed)
./gbox apikey claude add anthropic sk-ant-xxx \
  --description "Anthropic Official"

# List all providers
./gbox apikey claude list

# Switch default provider
./gbox apikey claude switch zhipu

# Check current provider status
./gbox apikey claude status

# Remove a provider
./gbox apikey claude remove <name>
```

**How it works**:
- Provider configurations are stored in `~/.gbox/claude/api-providers.json`
- Default provider config is loaded directly at container startup
- Priority: provider config > OAuth (no CLI override)
- Environment variables are passed to Claude Code via docker run
- Supports custom base URLs, timeouts, and model mappings
- No intermediate configuration file needed (settings.json)

**Supported options**:
- `--base-url <url>` - API endpoint (optional, defaults to Anthropic official)
- `--timeout <ms>` - Request timeout in milliseconds (optional, default: 3000000)
- `--haiku-model <model>` - Override haiku model name (optional)
- `--sonnet-model <model>` - Override sonnet model name (optional)
- `--opus-model <model>` - Override opus model name (optional)
- `--subagent-model <model>` - Override subagent model name (optional)
- `--description <text>` - Provider description (optional)

### Shared Environment Variables

AgentBox supports a shared `.env` file that is automatically mounted to all containers.

**Location**: `~/.gbox/.env` (host) → `~/.env` (container, read-only)

**Usage**:
```bash
# 1. Edit the shared .env file on host
vim ~/.gbox/.env

# 2. Add your environment variables
export MY_API_KEY="sk-xxx"
export DATABASE_URL="postgresql://localhost/mydb"
export DEBUG_MODE="true"

# 3. Source it in container shell or scripts
source ~/.env
```

**Important notes**:
- File is mounted as read-only (`:ro`) for security
- Shared across all containers (same as `.gitconfig`)
- Changes require container restart to take effect
- Automatically created with template on first run
- Do NOT store sensitive credentials in version control

### Agent Startup Options

```bash
# Resource limits
./gbox claude --memory 16g --cpu 8

# Port mapping (binds to 127.0.0.1 only)
# Single port: host_port:container_port
./gbox claude --ports "8000:8000;3000:3000"
# Port range: start-end (same ports on host and container)
./gbox claude --ports "8000-8999;6000-6999"
# Mixed: single ports and ranges
./gbox claude --ports "8080:8080;9000-9100"

# Reference directories (read-only mounts, repeatable, supports tab completion)
./gbox claude --ref-dir /path/to/ref1 --ref-dir /path/to/ref2

# HTTP proxy
./gbox claude --proxy "http://127.0.0.1:7890"

# Debug mode (enable happy:* logs)
./gbox claude --debug

# Keep container on exit (default: delete)
./gbox claude --keep

# Custom container name
./gbox claude --name my-custom-name

# Pass arguments to agent (after --)
./gbox claude -- --model sonnet
```

## Key Functions and Their Locations

### Container Lifecycle (`lib/container.sh`)
- `start_container()` (line 104) - Create/start container with all mounts
- `stop_container()` (line 502) - Stop and optionally delete container

### Docker Utilities (`lib/docker.sh`)
- `get_main_repo_dir()` (line 67) - Detect git worktree main directory (supports both git and non-git worktrees)
- `ensure_network()` (line 24) - Ensure Docker network exists
- `is_container_running()` (line 36) - Check if container is running
- `wait_for_container_ready()` (line 42) - Wait for container to be ready

### Agent Sessions (`lib/agent.sh`)
- `generate_container_name()` (line 43) - Generate container name from working directory (one repo = one container)
- `agent_session()` (line 99) - Main entry point for starting agents
- `parse_port_mappings()` (line 10) - Parse port mapping configuration
- Supports agents: `claude`, `codex`, `gemini`

### OAuth Management (`lib/oauth.sh`)
- `scan_oauth_accounts()` (line 59) - Find all OAuth account files
- `switch_oauth_account()` (line 177) - Interactive account switching
- `check_token_expiry()` (line 365) - Verify token validity
- Account files pattern: `.claude.json-email@example.com-001`

### API Provider Management (`lib/apikey.sh`)
- `load_default_provider_env()` (line 536) - Load default provider config as environment variables
- `apikey_add()` (line 157) - Add new API provider with options
- `apikey_remove()` (line 279) - Remove provider with interactive confirmation
- `apikey_switch()` (line 355) - Switch default provider
- `apikey_list()` (line 386) - List all providers with details
- `apikey_status()` (line 445) - Show current default provider status
- Storage file: `~/.gbox/claude/api-providers.json`
- Note: Provider config is loaded directly at container startup (no settings.json needed)

### State Management (`lib/state.sh`)
- `init_state()` (line 101) - Initialize ~/.gbox/ structure and directories
- `init_gitconfig()` (line 13) - Initialize shared git config for containers
- `init_env_file()` (line 68) - Initialize shared .env file with template
- `generate_state_key()` (line 124) - Generate state key from working directory (main repo path)
- `get_container_by_workdir()` (line 139) - Get container name by working directory
- `save_container_mapping()` (line 167) - Track container-directory mapping
- `remove_container_mapping()` (line 177) - Clean up mapping by directory
- `remove_container_mapping_by_container()` (line 186) - Clean up mapping by container name

### Image Management (`lib/image.sh`)
- `build_image()` (line 21) - Build with auto-detected timezone/mirrors
- `pull_image()` (line 102) - Pull from registry
- `push_image()` (line 135) - Push to registry

## Important Implementation Details

### Environment Variables in Containers

```bash
GBOX_WORK_DIR=/path/to/project        # Working directory
GBOX_MAIN_DIR=/path/to/main-repo      # Main repo (for worktree)
GBOX_RUN_MODE=only-local              # or local-remote
ANTHROPIC_API_KEY=xxx                 # Optional API key
HAPPY_AUTO_BYPASS_PERMISSIONS=1       # Auto-approve Happy permissions
DEBUG=${DEBUG:-}                      # User-controlled debug logs
```

Proxy variables (if `--proxy` specified):
```bash
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
# Plus lowercase variants
```

### Symbolic Link for Claude Config

Claude Code expects config at `~/.claude.json`, but we store it in `~/.claude/.claude.json`. A symlink is created automatically in the container:

```bash
~/.claude.json → ~/.claude/.claude.json
```

### Network Configuration

All containers connect to `gbox-network` (bridge mode) for inter-container communication.

Port mappings bind to `127.0.0.1` only (localhost) for security:
```bash
-p 127.0.0.1:8000:8000
```

### Resource Defaults

```bash
MEMORY_LIMIT=4g      # Default memory limit
CPU_LIMIT=2          # Default CPU cores
```

Override with environment variables:
```bash
export GBOX_MEMORY=8g
export GBOX_CPU=4
```

### Container Naming Rules

Format: `gbox-{dirname}`

**One repository corresponds to one container**, regardless of agent (claude, codex, gemini) or run mode (local/remote).

Examples:
- `/path/to/myproject` → `gbox-myproject`
- `/path/to/backend-api` → `gbox-backend-api`
- `/path/to/Prism-worktrees/v1.1.0` → `gbox-prism` (detected from worktree)

The container name is always based on the **main repository directory**, ensuring:
- Same container whether you start from main repo or any worktree
- Same container for all agents (claude, codex, gemini)
- Same container for both local and remote modes

See `generate_container_name()` in `lib/agent.sh:43` and `get_main_repo_dir()` in `lib/docker.sh:67`

### Git Directory Protection

AgentBox includes **dual-layer protection** against accidental deletion of `.git` directories by AI agents:

#### Protection Layers

**Layer 1: Command Wrapping**
- Wraps `rm`, `mv`, and `rmdir` functions with safety checks
- Automatically loaded in all shells (interactive and non-interactive via `BASH_ENV`)
- Logs all blocked operations to `/var/log/gbox-git-protector.log`

**Layer 2: System Command Replacement**
- Replaces `/bin/rm`, `/bin/mv`, `/bin/rmdir` with protected wrappers
- Original commands backed up to `/usr/local/lib/original/`
- Prevents bypass attempts using absolute paths like `/bin/rm`

#### What's Protected

All attempts are **BLOCKED**, including bypass attempts:
- Direct deletion: `rm -rf .git` ❌
- Subdirectory: `rm -rf .git/objects` ❌
- Moving: `mv .git .git.bak` ❌
- Relative paths: `rm -rf ./project/.git` ❌
- Absolute paths: `rm -rf /workspace/.git` ❌
- **Bypass attempts**: `/bin/rm -rf .git` ❌ **Still blocked!**

#### What's Allowed

Normal operations work as expected:
- File operations: `rm file.txt` ✅
- `.git` prefix files: `rm .git-backup` ✅
- Parent directories: `rm -rf parent/` ✅ (but not recommended)

#### Error Messages

When protection blocks an operation:
```
❌ ERROR: Attempting to remove .git directory is BLOCKED

Protected paths detected:
  - .git

⚠️  This protection prevents accidental deletion of git repositories.
⚠️  This operation cannot be bypassed for safety reasons.

If you need to manage .git directories, exit the container and
perform the operation on the host system.
```

**Note**: Error message intentionally does not reveal bypass methods.

#### Implementation Details

**Scripts**:
- `scripts/git-protector.sh` - Command wrapping functions
- `scripts/system-*-wrapper.sh` - System command replacements

**Integration Points**:
- `Dockerfile:163-181` - System command replacement during build
- `lib/container.sh:144-158` - Protection setup in container environment

**Logs and Auditing**:
```bash
# View protection events inside container
./gbox shell <container-name>
cat /var/log/gbox-git-protector.log

# Verify command replacements
ls -la /bin/rm /bin/mv /bin/rmdir
which rm mv rmdir
```

## Language Standards

**All project content MUST be in English**, including:

### Documentation
- **ALL** documentation files (README.md, QUICKSTART.md, ARCHITECTURE.md, etc.)
- Chinese versions are maintained separately with `_ZH` suffix (e.g., README_ZH.md)
- English is the primary language; Chinese translations are secondary

### Code Comments
- **ALL** code comments must be in English
- Function documentation must be in English
- Inline comments must be in English
- No Chinese characters in code comments

### Commit Messages
- **ALL** commit messages (subject and body) must be in English
- Follow [Conventional Commits](https://www.conventionalcommits.org/) format
- Use clear, concise English to describe changes
- Examples:
  - ✅ `feat: add OAuth multi-account support`
  - ✅ `fix: resolve git worktree detection issue`
  - ❌ `feat: 添加 OAuth 多账号支持`
  - ❌ `fix: 修复 git worktree 检测问题`

### Variable and Function Names
- Use descriptive English names
- Follow snake_case for variables: `container_name`, `main_repo_dir`
- Follow UPPER_CASE for constants: `MEMORY_LIMIT`, `CPU_LIMIT`
- Function names should be clear verbs: `start_container()`, `check_token_expiry()`

### Error Messages and Logging
- All user-facing messages must be in English
- Error messages should be clear and actionable
- Use the standardized message functions from `lib/common.sh`:
  - `error "message"` - for errors
  - `success "message"` - for success
  - `info "message"` - for information
  - `warn "message"` - for warnings

### Communication with Users
- **ALL** conversations with users MUST be in Chinese (中文)
- This applies to explanations, discussions, and interactive responses
- Code examples and technical terms should use English
- When explaining concepts, use Chinese for clarity and understanding

**Rationale**: English is the universal language for software development, ensuring:
- Better collaboration with international contributors
- Compatibility with global tools and services
- Easier code review and maintenance
- Professional standard alignment

## Development Tools and Workflow

### Code Writing Tool Standards

For all code writing, fixing, and refactoring tasks, **prefer using** `mcp__codex-cli__ask-codex` tool instead of directly using Edit/Write tools.

**Correct approach**:
```typescript
✅ mcp__codex-cli__ask-codex({
  prompt: "Fix XXX issue...",
  sandbox: true,              // Must be set to true (enable safe sandbox)
  model: "gpt-5.1-codex-max"  // latest code-specialized model
})
```

**Use cases**:
- ✅ Bug fixes (security vulnerabilities, functional errors, performance issues)
- ✅ New feature development (API endpoints, data models, business logic)
- ✅ Code refactoring (extract functions, optimize structure, eliminate duplication)
- ✅ Test writing (unit tests, integration tests, edge cases)
- ✅ Code documentation (function docstrings, type annotations, inline comments)

**Parameter descriptions**:
- `prompt`: Detailed task description (including problem, solution, verification requirements)
- `sandbox: true`: **Must be set**, enables workspace-write permission + on-failure approval policy
- `model: gpt-5.1-codex-max`: latest code-specialized model
- `config`: Optional, configuration object
  - `model_reasoning_effort`: Reasoning level (`"low"` / `"medium"` / `"high"`)
    - `"medium"` (default): General tasks (regular bug fixes, new feature development, unit tests)
    - `"high"`: Complex tasks (architecture design/refactoring, performance optimization, security vulnerability analysis, multi-file coordinated changes)
    - `"low"`: Simple tasks (code formatting, adding comments, simple renaming)
- `search: true`: Optional, enable when web search is needed

**When to use Edit/Write directly**:
- ❌ Documentation editing (README, CLAUDE.md, API docs, and other Markdown files)
- ❌ Configuration file modifications (.env, package.json, pyproject.toml, etc.)
- ❌ Progress document updates (PROGRESS.md, COMPLETION.md, etc.)
- ❌ Fine-tuning specific parts after Codex tool returns results

## Code Style Guidelines

### Shell Script Conventions

```bash
# ✅ Good
function my_function() {
    local param1="$1"
    local param2="$2"

    if [[ -z "$param1" ]]; then
        error "Parameter cannot be empty"
        return 1
    fi

    echo "Processing: $param1"
    return 0
}

# ❌ Bad
my_function() {
a=$1
if [ -z "$a" ]
then
echo "error"
fi
}
```

**Standards**:
- 4-space indentation
- Use `function name()` format
- Variables: lowercase_with_underscores
- Constants: UPPERCASE_WITH_UNDERSCORES
- Use `[[ ]]` not `[ ]`
- Quote all string variables: `"$var"`
- Add descriptive comments for non-obvious logic

### Error Handling

```bash
# Use common.sh functions
error "Error message"      # Red text, prefixed with ❌
success "Success message"  # Green text, prefixed with ✅
info "Info message"        # Blue text, prefixed with ℹ️
warn "Warning message"     # Yellow text, prefixed with ⚠️

# Early return on error
if [[ ! -d "$dir" ]]; then
    error "Directory not found: $dir"
    return 1
fi
```

### Function Documentation

Document complex functions with comments:

```bash
# Function: get_main_repo_dir
# Purpose: Detect main repository directory for git worktrees
# Args: $1 - current directory path
# Returns: Prints main directory path, or empty if not a worktree
# Exit code: 0 on success, 1 on error
```

## Testing Changes

### Before Committing

1. **Syntax check**:
   ```bash
   bash -n gbox
   bash -n lib/*.sh
   ```

2. **Manual test**:
   ```bash
   # Test basic startup
   ./gbox claude

   # Test with options
   ./gbox claude --memory 8g --cpu 4

   # Test container management
   ./gbox list
   ./gbox status
   ```

3. **Test error handling**:
   ```bash
   # Test invalid commands
   ./gbox invalid-agent
   ./gbox claude --invalid-option
   ```

4. **Format check**:
   ```bash
   # Ensure consistent formatting
   shfmt -i 4 -ci -sr -w lib/*.sh gbox
   ```

### Integration Testing

Test the full workflow:

1. Build image: `./gbox build`
2. Start container: `./gbox claude`
3. Verify mounts: Check `~/.gbox/` contents
4. Test OAuth: Verify login flow
5. Test MCP: `./gbox claude -- mcp list`
6. Clean up: `./gbox stop <container>`

## Commit Message Format

**IMPORTANT**: All commit messages MUST be in English.

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Guidelines**:
- **Keep it concise**: Subject line should be brief and to the point (ideally < 50 characters)
- **Focus on "what" and "why"**: Explain what changed and why, not how
- **Body is optional**: Only add detailed explanation if necessary
- **Use imperative mood**: "add feature" not "added feature" or "adds feature"

**Types**:
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Code formatting
- `refactor` - Code restructuring
- `perf` - Performance improvement
- `test` - Testing
- `chore` - Build/tools

**Examples**:

```
feat(oauth): add automatic account switching

Add support for automatically switching to available accounts when
current account reaches usage limits.

- Scan all available accounts
- Check current account status
- Switch to available account
- Update .claude.json config

Closes #123
```

```
fix(container): fix git worktree detection

Fix issue where worktrees in non-standard locations were not detected.
Updated get_main_repo_dir() to handle edge cases.

Fixes #456
```

## Important Constraints

### Security Considerations

1. **Port bindings**: Always bind to `127.0.0.1`, never `0.0.0.0`
2. **Reference directories**: Mount as read-only (`:ro` suffix)
3. **Git config**: Mount as read-only
4. **Non-root user**: Container runs as `guser` (UID 1000)
5. **Resource limits**: Always set memory and CPU limits

### Compatibility Requirements

1. **Docker version**: Tested with Docker 20.10+
2. **Shell**: Must work with bash 4.0+
3. **jq**: Required for JSON parsing
4. **Platform**: macOS and Linux (Ubuntu/Debian)

### Backward Compatibility

When modifying:
- Do not change container naming format
- Do not change mount points
- Do not change environment variable names
- Maintain compatibility with existing `~/.gbox/` directory structure

## Common Patterns

### Parsing Semicolon-Separated Lists

```bash
# Pattern used for --ports
IFS=';' read -ra items <<< "$input_string"
for item in "${items[@]}"; do
    # Process each item
done
```

### Handling Repeatable Parameters

```bash
# Pattern used for --ref-dir (repeatable parameter)
# In common.sh: CONTAINER_REF_DIRS=()
# In gbox parsing:
--ref-dir)
    shift
    CONTAINER_REF_DIRS+=("$1")
    shift
    ;;
# In container.sh:
parse_ref_dirs "$work_dir" "${CONTAINER_REF_DIRS[@]}"
```

### Checking Container State

```bash
if docker ps --filter "name=^${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$"; then
    # Container is running
else
    # Container is not running
fi
```

### Safe JSON Parsing

```bash
# Use jq for all JSON operations
account_info=$(jq -r '.accounts[0]' "$file")

# Always check jq exit code
if ! jq . "$json_file" >/dev/null 2>&1; then
    error "Invalid JSON file: $json_file"
    return 1
fi
```

## MCP Server Management

MCP servers are managed through Claude Code's built-in commands:

```bash
# List installed servers
./gbox claude -- mcp list

# Add a server (stored in ~/.gbox/claude/.claude.json)
./gbox claude -- mcp add <name> -s user -- <command>

# Remove a server
./gbox claude -- mcp remove <name>

# Common MCP servers
./gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox
./gbox claude -- mcp add codex-cli -s user -- npx -y @cexll/codex-mcp-server
./gbox claude -- mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /home/guser
./gbox claude -- mcp add github -s user -- npx -y @modelcontextprotocol/server-github
```

**Important**: MCP server configs are shared across all containers via `~/.gbox/claude/.claude.json`.

## Troubleshooting

### Common Issues

1. **Container fails to start**: Check `./gbox logs <container-name>`
2. **OAuth login fails**: Delete `~/.gbox/claude/.claude.json` and restart
3. **Port conflicts**: Use different ports with `--ports "8888:8000"`
4. **Network issues**: Check proxy settings, use `--proxy` if needed
5. **Playwright MCP browser conflicts**: Always use `--isolated --no-sandbox` flags

### Debug Mode

Enable debug logging:
```bash
DEBUG=happy:* ./gbox claude --debug
```

View detailed logs:
```bash
./gbox logs <container-name>
```

Interactive debugging:
```bash
./gbox shell <container-name>
```

## References

- [README.md](./README.md) - User documentation
- [QUICKSTART.md](./QUICKSTART.md) - 5-minute getting started guide
- [ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Detailed architecture design
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Contribution guidelines
