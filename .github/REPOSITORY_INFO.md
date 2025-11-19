# GitHub Repository Configuration

This file documents the GitHub repository settings for reference and version control.

## Repository Information

**Name**: AgentBox

**Description**:
```
开箱即用的容器化 AI 编程助手，无需安装即可安全自动化运行 Claude Code、Codex、Gemini CLI
```

**Website**:
```
https://gravtice.com
```

**Topics** (GitHub Tags):
```
docker, ai, claude-code, openai-codex, gemini, container, devtools, cli, oauth, automation
```

## How to Apply

These settings are configured on GitHub.com and cannot be set via local files.

### Manual Configuration
1. Go to: https://github.com/Gravtice/AgentBox/settings
2. Update Description, Website, and Topics

### Using GitHub CLI
```bash
gh repo edit --description "开箱即用的容器化 AI 编程助手，无需安装即可安全自动化运行 Claude Code、Codex、Gemini CLI"
gh repo edit --homepage "https://gravtice.com"
gh repo edit --add-topic docker,ai,claude-code,openai-codex,gemini,container,devtools,cli,oauth,automation
```

### Using GitHub API
```bash
curl -X PATCH \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/Gravtice/AgentBox \
  -d '{
    "description": "开箱即用的容器化 AI 编程助手，无需安装即可安全自动化运行 Claude Code、Codex、Gemini CLI",
    "homepage": "https://gravtice.com",
    "topics": ["docker", "ai", "claude-code", "openai-codex", "gemini", "container", "devtools", "cli", "oauth", "automation"]
  }'
```

## Recommended Topics

Based on the project features:
- **docker** - Container-based architecture
- **ai** - AI agent management
- **claude-code** - Claude Code support
- **openai-codex** - Codex support
- **gemini** - Gemini support
- **container** - Containerization
- **devtools** - Developer tools
- **cli** - Command-line interface
- **oauth** - OAuth authentication
- **automation** - Automation features

---

*Note: This file is for reference only. Actual configuration must be done on GitHub.com or via GitHub CLI/API.*
