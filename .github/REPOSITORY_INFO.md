# GitHub Repository Configuration

This file documents the GitHub repository settings for reference and version control.

## Repository Information

**Name**: AgentBox

**Description**:
```
容器化的 AI Agent 运行工具，支持 Claude Code、Codex、Gemini 等多种 AI Agent
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
gh repo edit --description "容器化的 AI Agent 运行工具，支持 Claude Code、Codex、Gemini 等多种 AI Agent"
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
    "description": "容器化的 AI Agent 运行工具，支持 Claude Code、Codex、Gemini 等多种 AI Agent",
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
