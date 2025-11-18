# ccbox - Claude Code 容器化开发指南

## 快速开始

### 1. 构建镜像

```bash
./ccbox build
```

### 2. 启动容器

```bash
# 使用绝对路径
./ccbox new /path/to/your-project

# 使用当前目录
cd /path/to/worktree
./ccbox new
```

### 3. 查看运行中的容器

```bash
./ccbox list
```

### 4. 停止容器

```bash
./ccbox stop ccbox-myproject
```

## 特性说明

### 工作目录隔离

- 每个工作目录只能启动一个容器
- 尝试重复启动会报错提示
- 容器内外路径完全一致
- 支持git worktree并行开发

### 用户权限

- 容器使用宿主机用户的UID/GID运行
- 工作目录读写权限与宿主机一致
- 无需担心权限问题

### 免权限模式

- 容器内Claude Code自动使用 `--dangerously-skip-permissions`
- 所有工具调用无需手动批准
- 不影响宿主机的Claude Code配置

### 配置共享

- 共享 `~/.claude` 目录
- 认证token自动生效，无需重复登录
- 配置在所有容器间共享

### 端口管理

- 容器内固定使用8000端口
- 宿主机端口从8001-8010自动分配
- 避免端口冲突

## 常用命令

```bash
# 启动容器（进入Claude Code交互式会话）
./ccbox new /path/to/worktree

# 列出运行中的容器及其工作目录
./ccbox list

# 显示所有容器状态（包括已停止的）
./ccbox status

# 在容器中执行命令
./ccbox exec ccbox-myproject "uv run pytest"

# 查看容器日志
./ccbox logs ccbox-myproject

# 停止单个容器
./ccbox stop ccbox-myproject

# 停止所有容器
./ccbox stop-all

# 清理停止的容器
./ccbox clean

# 重新构建镜像
./ccbox build
```

## 状态管理

容器状态存储在 `~/.ccbox/containers.json`：

```json
{
  "/path/to/project-main": "ccbox-project-main",
  "/path/to/project-v0.2.0": "ccbox-project-v0.2.0"
}
```

## 故障排查

### 问题：提示工作目录已被使用

```bash
错误: 工作目录 /path/to/worktree 已被容器 ccbox-xxx 使用
```

**解决方案**：
```bash
# 检查容器状态
./ccbox status

# 停止占用的容器
./ccbox stop ccbox-xxx

# 或清理所有停止的容器
./ccbox clean
```

### 问题：端口全部被占用

**解决方案**：
```bash
# 检查端口占用
lsof -i :8001-8010

# 停止不需要的容器
./ccbox stop-all
```

### 问题：容器无法访问工作目录文件

**原因**：用户权限不匹配

**解决方案**：
- 重新构建镜像：`./ccbox build`
- 检查文件权限：`ls -la /path/to/worktree`

### 问题：jq命令未找到

**解决方案**：
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

## 最佳实践

### 1. 并行开发多个版本

```bash
# Terminal 1
cd /path/to/worktree-1
../ccbox --work-dir .

# Terminal 2
cd /path/to/worktree-2
../ccbox --work-dir .
```

### 2. 定期清理

```bash
# 每天结束时清理停止的容器
./ccbox clean
```

### 3. 更新镜像

```bash
# 代码依赖变化后重新构建
./ccbox build
```

### 4. 使用别名简化命令

```bash
# 在 ~/.bashrc 或 ~/.zshrc 中添加
alias ccbox='/path/to/your-project/ccbox'

# 然后可以在任何地方使用
ccbox new /path/to/worktree
```

## 限制和注意事项

1. **端口限制**：最多支持10个并发容器（8001-8010）
2. **工作目录唯一性**：一个工作目录同时只能有一个容器
3. **配置共享**：`.claude`目录在所有容器间共享，修改会互相影响
4. **容器生命周期**：使用 `--rm` 标志，容器退出后自动删除
5. **依赖要求**：需要安装 `jq` 工具用于状态管理

## 技术实现

### 目录映射

```
宿主机                          容器
/path/to/your-project      →   /path/to/your-project
~/.claude                  →   ~/.claude
```

### 用户权限

容器使用 `--user $(id -u):$(id -g)` 确保：
- 容器进程使用宿主机用户身份运行
- 文件创建和修改权限与宿主机一致
- 避免权限问题

### 状态跟踪

- 使用JSON文件记录工作目录到容器的映射
- 启动前检查工作目录是否已被占用
- 容器退出后自动清理映射
- 支持手动清理失效映射

## 进阶用法

### 自定义镜像

编辑 `Dockerfile` 添加自定义工具：

```dockerfile
# 安装额外的开发工具
RUN apt-get update && apt-get install -y \
    vim \
    tmux \
    && rm -rf /var/lib/apt/lists/*
```

### 资源限制

编辑 `ccbox` 的 `docker run` 命令添加资源限制：

```bash
docker run -it --rm \
    --memory="4g" \
    --cpus="2" \
    ...
```

### 持久化缓存

挂载包管理器缓存加快依赖安装：

```bash
-v "$HOME/.cache/pip:/home/$(whoami)/.cache/pip" \
-v "$HOME/.npm:/home/$(whoami)/.npm"
```

## 常见问题

### Q: 为什么需要jq？

A: jq用于管理容器状态的JSON文件，实现工作目录到容器的映射跟踪。

### Q: 可以在容器中修改代码吗？

A: 可以！容器使用宿主机用户权限，所有修改都会同步到宿主机。

### Q: 多个容器会互相干扰吗？

A: 不会。每个容器使用独立的端口，工作目录也是隔离的。只有 `.claude` 配置是共享的。

### Q: 如何在容器中使用不同的Claude Code版本？

A: 修改 `Dockerfile` 中的安装命令，然后重新构建镜像。

### Q: 容器退出后数据会丢失吗？

A: 不会。工作目录是挂载的，所有修改都保存在宿主机。
