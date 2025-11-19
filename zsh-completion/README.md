# gbox Zsh Auto-completion Plugin

Provides intelligent auto-completion for the `gbox` command, similar to the git command experience.

## Features

### 1. Main Command Completion
After typing `gbox ` and pressing `Tab`, auto-complete all available commands:
- `list` - List running containers
- `status` - Show detailed status of all containers
- `stop` - Stop and delete a container
- `stop-all` - Stop all containers
- `clean` - Clean up all stopped containers
- `oauth` - OAuth account management
- `keepalive` - Container maintenance management
- `pull` / `push` / `build` - Image operations
- `logs` / `exec` / `shell` - Container operations
- `help` - Display help information
- `happy` - Remote collaboration mode

### 2. AI Agent Completion
After typing `gbox ` and pressing `Tab`, also displays all supported AI agents:
- `claude` - Claude Code
- `codex` - OpenAI Codex
- `gemini` - Google Gemini

### 3. Parameter Option Completion
After typing `gbox claude ` and pressing `Tab`, auto-complete gbox parameters:
- `--memory` / `-m` - Memory limit
- `--cpu` / `-c` - CPU cores
- `--ports` - Port mapping
- `--keep` - Keep container after exit
- `--name` - Custom container name

### 4. Dynamic Container Name Completion
Commands that require container names (`stop`, `logs`, `shell`, `exec`) automatically complete running containers:
```bash
gbox stop <Tab>
# Automatically shows: gbox-claude-project  gbox-codex-myapp  etc.
```

### 5. Subcommand Completion

**oauth subcommands:**
```bash
gbox oauth <Tab>
# Shows: claude  codex  gemini

gbox oauth claude <Tab>
# Shows: help  etc.
```

**keepalive subcommands:**
```bash
gbox keepalive <Tab>
# Shows: list  stop  stop-all  restart  logs  auto  help

gbox keepalive stop <Tab>
# Auto-complete account suffix
```

### 6. Remote Collaboration Mode Completion
```bash
gbox happy <Tab>
# Shows: claude  codex  gemini

gbox happy claude <Tab>
# Shows gbox parameter options
```

## Quick Installation

### Automatic Installation (Recommended)

Run from the project root directory:
```bash
./zsh-completion/install.sh
```

The installation script will:
1. Copy plugin files to `~/.oh-my-zsh/custom/plugins/gbox/`
2. Automatically update `~/.zshrc`, adding `gbox` to the plugins array
3. Clear completion cache
4. Prompt you to reload your shell

### Manual Installation

If you want to install manually:

1. Copy plugin files:
```bash
mkdir -p ~/.oh-my-zsh/custom/plugins/gbox
cp zsh-completion/gbox.plugin.zsh ~/.oh-my-zsh/custom/plugins/gbox/
```

2. Edit `~/.zshrc` and add `gbox` to the `plugins` array:
```bash
plugins=(
    git
    docker
    # ... other plugins
    gbox  # Add this line
)
```

3. Reload the configuration:
```bash
exec zsh
# or
source ~/.zshrc
```

## Usage Examples

### Basic Completion
```bash
gbox <Tab>
# Shows all commands and agents

gbox cl<Tab>
# Auto-completes to: gbox claude

gbox list<Tab>
# Directly complete the command
```

### Parameter Completion
```bash
gbox claude --<Tab>
# Shows: --memory --cpu --ports --keep --name

gbox claude -<Tab>
# Shows: -m -c
```

### Container Name Completion
```bash
gbox stop <Tab>
# Shows all running gbox-* containers

gbox logs gbox-<Tab>
# Auto-completes container name
```

### Subcommand Completion
```bash
gbox keepalive <Tab>
# Shows all keepalive subcommands

gbox oauth <Tab>
# Shows all supported agents
```

## Shortcut Aliases

The plugin also provides some convenient shortcuts:

| Alias | Full Command | Description |
|-------|----------|------|
| `gb` | `gbox` | Main command shortcut |
| `gbl` | `gbox list` | List containers |
| `gbs` | `gbox status` | View status |
| `gbh` | `gbox happy` | Remote collaboration mode |
| `gbc` | `gbox claude` | Run Claude |
| `gbcd` | `gbox codex` | Run Codex |
| `gbgm` | `gbox gemini` | Run Gemini |

Usage examples:
```bash
gbc                    # Equivalent to gbox claude
gbh claude             # Equivalent to gbox happy claude
gbl                    # Equivalent to gbox list
```

## Verify Installation

After installation, test in the terminal:

```bash
# 1. Check if the function is loaded
type _gbox
# Expected output: _gbox is a shell function from ...

# 2. Check completion registration
echo ${_comps[gbox]}
# Expected output: _gbox

# 3. Test completion
gbox <Tab>
# Should show all commands and agents
```

## Troubleshooting

### Completion Not Working
1. Confirm you have reloaded the shell: `exec zsh`
2. Check if the function is loaded: `type _gbox`
3. Clear the completion cache: `rm ~/.zcompdump* && exec zsh`

### Container Name Completion is Empty
- Make sure there are running gbox containers: `docker ps --filter 'name=gbox-'`
- Check if Docker is running properly

### Only Seeing Partial Completion Options
This is normal, try:
```bash
gbox cl<Tab>    # Should complete to claude
gbox li<Tab>    # Should complete to list
```

## Uninstall

If you need to uninstall:

1. Remove `gbox` from the `plugins` array in `~/.zshrc`
2. Delete the plugin directory: `rm -rf ~/.oh-my-zsh/custom/plugins/gbox`
3. Reload: `exec zsh`

## Technical Details

- Completion system: Zsh completion system with `_arguments`
- Implementation: oh-my-zsh custom plugin
- Dynamic completion: Container names fetched from Docker in real-time
- Supported version: Zsh 5.0+, oh-my-zsh

## Customization

If you want to modify the completion behavior, you can edit the plugin file:
```bash
vim ~/.oh-my-zsh/custom/plugins/gbox/gbox.plugin.zsh
```

After modification, reload:
```bash
exec zsh
```

## Maintenance Guide

### When to Update the Completion Plugin

Update the completion plugin when gbox has the following changes:

1. **Add/Remove main commands** - Update `commands` array (lines 12-29)
2. **Add/Remove AI Agents** - Update `agents` array (lines 32-36)
3. **Modify parameter options** - Update `gbox_opts` array (lines 140-151)
4. **Modify subcommands** - Update corresponding subcommand arrays (lines 39-59)

### Check Sync Status

Run the automatic verification script:
```bash
./zsh-completion/check_sync.sh
```

The script compares gbox source code and the completion plugin, reporting any inconsistencies.

### Update Workflow

1. Modify `gbox.plugin.zsh`
2. Run `./zsh-completion/check_sync.sh` to verify
3. Run `./zsh-completion/install.sh` to install the new version
4. Test completion functionality

## Contributing

We welcome bug reports and improvement suggestions! The plugin source code is located at: `zsh-completion/gbox.plugin.zsh`
