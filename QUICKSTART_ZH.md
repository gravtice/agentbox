# Gravtice AgentBox 快速入门

5分钟快速上手 Gravtice AgentBox！

## 📋 准备工作

### 1. 安装依赖

**macOS:**
```bash
brew install jq docker
```

**Ubuntu/Debian:**
```bash
sudo apt-get install jq docker.io
```

### 2. 克隆项目

```bash
git clone https://github.com/Gravtice/AgentBox.git
cd AgentBox
```

### 3. 构建镜像

```bash
./gbox build
# 等待 2-5 分钟完成构建
```

## 🚀 第一次使用

### 启动 Claude Code

```bash
cd ~/projects/myproject
./gbox claude
```

第一次启动时会:
1. 自动创建配置目录 `~/.gbox/`
2. 自动创建容器 `gbox-claude-myproject`
3. 启动 Claude Code
4. 提示完成 OAuth 登录

### 完成 OAuth 登录

在 Claude Code 界面:
1. 按提示打开浏览器
2. 登录 Anthropic 账号
3. 授权 Claude Code
4. 回到终端,开始使用

> 💡 **提示**: OAuth 登录只需一次,后续所有容器都会自动复用登录态

## 📚 基本使用

### 启动不同的 Agent

```bash
# Claude Code (本地模式)
./gbox claude

# Happy + Claude Code (远程控制)
./gbox happy claude

# Codex
./gbox codex

# Gemini
./gbox gemini
```

### 查看运行中的容器

```bash
./gbox list
```

输出示例:
```
运行中的 gbox 容器:
容器名                    工作目录              镜像
gbox-claude-myproject   ~/projects/myproject  agentbox:1.0.1
```

### 停止容器

```bash
# 停止指定容器
./gbox stop gbox-claude-myproject

# 停止所有容器
./gbox stop-all
```

### 查看容器日志

```bash
./gbox logs gbox-claude-myproject
```

### 登录容器调试

```bash
./gbox shell gbox-claude-myproject
```

## ⚙️ 常用配置

### 调整资源限制

```bash
# 增加内存和 CPU
./gbox claude --memory 16g --cpu 8
```

### 映射端口

```bash
# 映射单个端口
./gbox claude --ports "8000:8000"

# 映射多个端口
./gbox claude --ports "8000:8000;3000:3000;5432:5432"
```

### 挂载参考目录

```bash
# 挂载其他项目作为只读参考
./gbox claude --ref-dirs "/path/to/reference-project"

# 挂载多个参考目录
./gbox claude --ref-dirs "/path/to/ref1;/path/to/ref2"
```

### 使用代理

```bash
# HTTP 代理
./gbox claude --proxy "http://127.0.0.1:7890"

# SOCKS5 代理
./gbox claude --proxy "socks5://127.0.0.1:1080"
```

### 组合使用

```bash
./gbox claude \
  --memory 16g \
  --cpu 8 \
  --ports "8000:8000;3000:3000" \
  --ref-dirs "/path/to/reference" \
  --proxy "http://127.0.0.1:7890" \
  -- --model sonnet
```

## 🎯 使用技巧

### 1. 多项目管理

每个项目目录会自动创建独立的容器:

```bash
# 项目 A
cd ~/projects/project-a
./gbox claude    # 容器: gbox-claude-project-a

# 项目 B
cd ~/projects/project-b
./gbox claude    # 容器: gbox-claude-project-b
```

### 2. 配置文件编辑

所有配置文件都在 `~/.gbox/` 目录下,可以直接编辑:

```bash
# 编辑 Claude 全局指令
code ~/.gbox/claude/CLAUDE.md

# 编辑 Git 配置
vim ~/.gbox/.gitconfig

# 查看 OAuth 配置
cat ~/.gbox/claude/.claude.json
```

### 3. MCP 服务器管理

#### 常用 MCP 服务推荐

AgentBox 支持所有标准的 MCP 服务器。以下是一些常用推荐：

**Playwright (浏览器自动化)**
```bash
# 安装 Playwright MCP - 支持浏览器自动化和网页截图
./gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox
```

**Codex CLI (终端命令执行)**
```bash
# 安装 Codex CLI MCP - 支持安全的终端命令执行
./gbox claude -- mcp add codex-cli -s user -- npx -y @cexll/codex-mcp-server
```

**Filesystem (文件系统访问)**
```bash
# 安装 Filesystem MCP - 支持读写文件系统
./gbox claude -- mcp add filesystem -s user -- npx -y @modelcontextprotocol/server-filesystem /home/guser
```

**GitHub (GitHub API 访问)**
```bash
# 安装 GitHub MCP - 支持操作 GitHub 仓库、Issues、PR 等
./gbox claude -- mcp add github -s user -- npx -y @modelcontextprotocol/server-github
```

**基本操作**
```bash
# 列出已安装的 MCP 服务器
./gbox claude -- mcp list

# 删除 MCP 服务器
./gbox claude -- mcp remove <服务器名>

# 查看 MCP 服务器状态
cat ~/.gbox/claude/.claude.json
```

> 💡 **提示**:
> - 安装后需要退出并重新进入 Claude Code 会话才能生效
> - Playwright 必须使用 `--isolated --no-sandbox` 参数避免浏览器冲突
> - 更多 MCP 服务器请查看 [MCP 服务器目录](https://github.com/modelcontextprotocol/servers)

### 4. OAuth 账号切换

当账号达到使用限制时:

```bash
# 查看当前账号状态
./gbox oauth claude status

# 切换到其他账号
./gbox oauth claude switch

# 列出所有账号
./gbox oauth claude list
```

### 5. Git Worktree 支持

AgentBox 自动支持 Git Worktree:

```bash
# 在主仓库创建 worktree
cd ~/projects/myproject
git worktree add ../myproject-worktrees/feature-a feature-a

# 在 worktree 中启动 (使用同一个容器)
cd ../myproject-worktrees/feature-a
./gbox claude
```

## 🐛 故障排查

### 问题 1: 容器无法启动

**症状**: 执行 `./gbox claude` 后容器无法启动

**解决方法**:
```bash
# 1. 检查 Docker 是否运行
docker ps

# 2. 查看容器日志
./gbox logs <容器名>

# 3. 检查镜像是否存在
docker images | grep agentbox

# 4. 重新构建镜像
./gbox build
```

### 问题 2: OAuth 登录失败

**症状**: Claude Code 提示 OAuth 登录失败

**解决方法**:
```bash
# 1. 删除旧的 OAuth 配置
rm ~/.gbox/claude/.claude.json

# 2. 重新启动容器
./gbox claude

# 3. 按提示重新登录
```

### 问题 3: 端口冲突

**症状**: 提示端口已被占用

**解决方法**:
```bash
# 1. 查看占用端口的容器
docker ps | grep gbox

# 2. 停止占用端口的容器
./gbox stop <容器名>

# 3. 或使用不同的端口
./gbox claude --ports "8888:8000"
```

### 问题 4: 容器内无法访问网络

**症状**: Claude Code 无法联网

**解决方法**:
```bash
# 1. 检查宿主机网络
ping anthropic.com

# 2. 如需代理,添加代理配置
./gbox claude --proxy "http://127.0.0.1:7890"

# 3. 登录容器调试
./gbox shell <容器名>
ping anthropic.com
```

### 问题 5: 依赖安装缓慢

**症状**: 每次启动都要重新安装依赖

**说明**: AgentBox 已自动启用依赖缓存,缓存目录:
- `~/.gbox/cache/pip` - Python pip 缓存
- `~/.gbox/cache/npm` - Node.js npm 缓存
- `~/.gbox/cache/uv` - Python uv 缓存

如果仍然缓慢,可能是网络问题,考虑使用代理。

### 问题 6: 配置文件丢失

**症状**: 容器内看不到配置文件

**解决方法**:
```bash
# 1. 检查配置目录是否存在
ls -la ~/.gbox/

# 2. 如果不存在,重新启动容器会自动创建
./gbox claude

# 3. 恢复备份配置 (如果有备份)
tar -xzf gbox-backup-20241106.tar.gz -C ~
```

### 问题 7: Playwright MCP 浏览器占用错误

**症状**: Claude Code 提示 `Error: Browser is already in use for /usr/local/share/playwright/mcp-chrome-03e4594, use --isolated to run multiple instances of the same browser`

**原因**: Playwright MCP 的浏览器实例已被占用,需要使用 `--isolated` 参数来运行独立实例

**解决方法**:
```bash
# 1. 先卸载 Playwright MCP
./gbox claude -- mcp remove playwright

# 2. 使用带隔离参数重新安装
./gbox claude -- mcp add playwright -s user -- npx -y @playwright/mcp@latest --isolated --no-sandbox

# 3. 退出当前 Claude Code 会话 (Ctrl+D)，重新进入
./gbox claude
```

### 清理和重置

如果遇到无法解决的问题,可以完全清理并重新开始:

```bash
# 1. 停止所有容器
./gbox stop-all

# 2. 删除配置 (会删除 OAuth 登录态,需重新登录)
rm -rf ~/.gbox

# 3. 重新启动
./gbox claude
```

## 📚 进阶阅读

- [架构设计](./docs/ARCHITECTURE_ZH.md) - 了解 AgentBox 的设计理念
- [自定义镜像](./docs/CUSTOM_IMAGE_ZH.md) - 制作自己的 Agent 镜像

## 💡 最佳实践

1. **首次使用**: 先用小项目测试,熟悉后再用于大项目
2. **资源配置**: 根据项目大小调整内存和 CPU
3. **定期备份**: 定期备份 `~/.gbox/` 目录下的重要配置
4. **容器清理**: 定期运行 `./gbox clean` 清理停止的容器
5. **日志查看**: 遇到问题先查看日志 `./gbox logs <容器名>`

## 🤔 需要帮助？

- 查看完整文档: [README_ZH.md](./README_ZH.md)
- 提交问题: [GitHub Issues](https://github.com/Gravtice/AgentBox/issues)
- 参与讨论: [GitHub Discussions](https://github.com/Gravtice/AgentBox/discussions)

---

**祝你使用愉快！** 🎉
