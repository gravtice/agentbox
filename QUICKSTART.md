# Gravtice AgentBox Quick Start

Get started with Gravtice AgentBox in 5 minutes!

## 📋 Prerequisites

### 1. Install Dependencies

**macOS:**
```bash
brew install jq docker
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq docker.io
```

### 2. Install AgentBox

**Option A: One-line install (recommended)**

```bash
curl -fsSL https://raw.githubusercontent.com/Gravtice/AgentBox/main/install.sh | bash
```

**Option B: Install from a cloned repository**

```bash
git clone https://github.com/Gravtice/AgentBox.git
cd AgentBox
./install.sh
```

### 3. Build the Image

```bash
gbox build
# Wait 2-5 minutes for the build to complete
```

> If you are running directly from the repository without installing system-wide, replace `gbox` with `./gbox` in the commands below.

## 🚀 First-Time Use

### Start Claude Code

```bash
cd ~/projects/myproject
gbox claude
```

On first launch, it will:
1. Automatically create the configuration directory `~/.gbox/`
2. Automatically create container `gbox-myproject`
3. Start Claude Code
4. Prompt you to complete OAuth login

### Complete OAuth Login

In the Claude Code interface:
1. Follow the prompt to open your browser
2. Log in to your Anthropic account
3. Authorize Claude Code
4. Return to the terminal and start using it

> 💡 **Tip**: OAuth login is only required once. All subsequent containers will automatically reuse the login session.

## 📚 Basic Usage

### Start Different Agents

```bash
# Claude Code (local mode)
gbox claude

# Happy + Claude Code (remote control)
gbox happy claude

# Codex
gbox codex

# Gemini
gbox gemini
```

### View Running Containers

```bash
gbox list
```

Example output:
```
Running gbox containers:
Container Name            Working Directory        Image
gbox-myproject    ~/projects/myproject     agentbox:1.0.1
```

### Stop Containers

```bash
# Stop a specific container
gbox stop gbox-myproject

# Stop all containers
gbox stop-all
```

### View Container Logs

```bash
gbox logs gbox-myproject
```

### Login to Container for Debugging

```bash
gbox shell gbox-myproject
```

## ⚙️ Common Configurations

### Adjust Resource Limits

```bash
# Increase memory and CPU
gbox claude --memory 16g --cpu 8
```

### Map Ports

```bash
# Map a single port
gbox claude --ports "8000:8000"

# Map multiple ports
gbox claude --ports "8000:8000;3000:3000;5432:5432"
```

### Mount Reference Directories

```bash
# Mount another project as read-only reference
gbox claude --ref-dirs "/path/to/reference-project"

# Mount multiple reference directories
gbox claude --ref-dirs "/path/to/ref1;/path/to/ref2"
```

### Use Proxy

```bash
# HTTP proxy
gbox claude --proxy "http://127.0.0.1:7890"

# SOCKS5 proxy
gbox claude --proxy "socks5://127.0.0.1:1080"
```

### Combine Options

```bash
gbox claude \
  --memory 16g \
  --cpu 8 \
  --ports "8000:8000;3000:3000" \
  --ref-dirs "/path/to/reference" \
  --proxy "http://127.0.0.1:7890" \
  -- --model sonnet
```

## 🎯 Tips and Tricks

### 1. Multi-Project Management

Each project directory automatically creates an independent container:

```bash
# Project A
cd ~/projects/project-a
gbox claude    # Container: gbox-project-a

# Project B
cd ~/projects/project-b
gbox claude    # Container: gbox-project-b
```

### 2. Configuration File Editing

All configuration files are under the `~/.gbox/` directory and can be edited directly:

```bash
# Edit Claude global instructions
code ~/.gbox/claude/CLAUDE.md

# Edit Git configuration
vim ~/.gbox/.gitconfig

# View OAuth configuration
cat ~/.gbox/claude/.claude.json
```

### 3. MCP Server Management

#### Recommended MCP Servers

AgentBox supports all standard MCP servers. Here are some common recommendations:

**Playwright (Browser Automation)**
```bash
# Install Playwright MCP - supports browser automation and webpage screenshots
gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox
```

**Codex CLI (Terminal Command Execution)**
```bash
# Install Codex CLI MCP - supports secure terminal command execution
gbox claude -- mcp add codex-cli -s user -- npx -y @cexll/codex-mcp-server
```

**Filesystem (File System Access)**
```bash
# Install Filesystem MCP - supports reading and writing to the file system
gbox claude -- mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /home/guser
```

**GitHub (GitHub API Access)**
```bash
# Install GitHub MCP - supports operations on GitHub repositories, Issues, PRs, etc.
gbox claude -- mcp add github -s user -- npx -y @modelcontextprotocol/server-github
```

**Basic Operations**
```bash
# List installed MCP servers
gbox claude -- mcp list

# Remove an MCP server
gbox claude -- mcp remove <server-name>

# View MCP server status
cat ~/.gbox/claude/.claude.json
```

> 💡 **Tips**:
> - You need to exit and re-enter the Claude Code session for changes to take effect
> - Playwright must use `--isolated --no-sandbox` parameters to avoid browser conflicts
> - For more MCP servers, see the [MCP Server Directory](https://github.com/modelcontextprotocol/servers)

### 4. OAuth Account Switching

When your account reaches usage limits:

```bash
# Check current account status
gbox oauth claude status

# Switch to another account
gbox oauth claude switch

# List all accounts
gbox oauth claude list
```

### 5. Git Worktree Support

AgentBox automatically supports Git Worktrees:

```bash
# Create a worktree in the main repository
cd ~/projects/myproject
git worktree add ../myproject-worktrees/feature-a feature-a

# Start in the worktree (uses the same container)
cd ../myproject-worktrees/feature-a
gbox claude
```

## 🧹 Uninstall AgentBox

If you installed via one-line command:

```bash
curl -fsSL https://raw.githubusercontent.com/Gravtice/AgentBox/main/install.sh | bash -s -- --uninstall
```

If you have the repository locally:

```bash
./uninstall.sh
# or
./install.sh --uninstall
```

## 🐛 Troubleshooting

### Issue 1: Container Fails to Start

**Symptoms**: Container fails to start after running `gbox claude`

**Solution**:
```bash
# 1. Check if Docker is running
docker ps

# 2. View container logs
gbox logs <container-name>

# 3. Check if the image exists
docker images | grep agentbox

# 4. Rebuild the image
gbox build
```

### Issue 2: OAuth Login Failed

**Symptoms**: Claude Code reports OAuth login failure

**Solution**:
```bash
# 1. Delete old OAuth configuration
rm ~/.gbox/claude/.claude.json

# 2. Restart the container
gbox claude

# 3. Follow the prompt to log in again
```

### Issue 3: Port Conflict

**Symptoms**: Error message indicating port is already in use

**Solution**:
```bash
# 1. View containers occupying the port
docker ps | grep gbox

# 2. Stop the container occupying the port
gbox stop <container-name>

# 3. Or use a different port
gbox claude --ports "8888:8000"
```

### Issue 4: No Network Access Inside Container

**Symptoms**: Claude Code cannot access the network

**Solution**:
```bash
# 1. Check host network
ping anthropic.com

# 2. If proxy is needed, add proxy configuration
gbox claude --proxy "http://127.0.0.1:7890"

# 3. Login to container for debugging
gbox shell <container-name>
ping anthropic.com
```

### Issue 5: Slow Dependency Installation

**Symptoms**: Dependencies need to be reinstalled every time

**Explanation**: AgentBox has dependency caching enabled automatically. Cache directories:
- `~/.gbox/cache/pip` - Python pip cache
- `~/.gbox/cache/npm` - Node.js npm cache
- `~/.gbox/cache/uv` - Python uv cache

If it's still slow, it may be a network issue. Consider using a proxy.

### Issue 6: Configuration Files Missing

**Symptoms**: Cannot see configuration files inside the container

**Solution**:
```bash
# 1. Check if the configuration directory exists
ls -la ~/.gbox/

# 2. If it doesn't exist, restarting the container will create it automatically
gbox claude

# 3. Restore backup configuration (if you have a backup)
tar -xzf gbox-backup-20241106.tar.gz -C ~
```

### Issue 7: Playwright MCP Browser Occupancy Error

**Symptoms**: Claude Code reports `Error: Browser is already in use for /usr/local/share/playwright/mcp-chrome-03e4594, use --isolated to run multiple instances of the same browser`

**Cause**: The Playwright MCP browser instance is already in use. You need to use the `--isolated` parameter to run independent instances.

**Solution**:
```bash
# 1. First uninstall Playwright MCP
gbox claude -- mcp remove playwright

# 2. Reinstall with isolation parameters
gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox

# 3. Exit the current Claude Code session (Ctrl+D) and re-enter
gbox claude
```

### Clean and Reset

If you encounter unresolvable issues, you can completely clean up and start fresh:

```bash
# 1. Stop all containers
gbox stop-all

# 2. Delete configuration (this will delete OAuth login sessions, requiring re-login)
rm -rf ~/.gbox

# 3. Restart
gbox claude
```

## 📚 Further Reading

- [Architecture Design](./docs/ARCHITECTURE.md) - Understand AgentBox's design philosophy
- [Custom Images](./docs/CUSTOM_IMAGE.md) - Create your own Agent images

## 💡 Best Practices

1. **First-time use**: Test with a small project first, then use on larger projects after getting familiar
2. **Resource configuration**: Adjust memory and CPU based on project size
3. **Regular backups**: Regularly back up important configurations in the `~/.gbox/` directory
4. **Container cleanup**: Regularly run `gbox clean` to clean up stopped containers
5. **Log viewing**: When encountering issues, first check logs with `gbox logs <container-name>`

## 🤔 Need Help?

- View complete documentation: [README.md](./README.md)
- Submit issues: [GitHub Issues](https://github.com/Gravtice/AgentBox/issues)
- Join discussions: [GitHub Discussions](https://github.com/Gravtice/AgentBox/discussions)

---

**Enjoy using AgentBox!** 🎉
