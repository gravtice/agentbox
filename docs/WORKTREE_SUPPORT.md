# Git Worktree 支持文档

## 概述

AgentBox 现在完全支持 Git Worktree 并行开发模式，确保无论从主仓库目录还是 worktree 子目录启动容器，都会使用同一个容器，实现真正的统一开发环境。

## 目录规范

### 主目录和 Worktrees 目录关系

```
/path/to/project/                    # 主仓库目录
/path/to/project-worktrees/          # Worktrees 目录（自动创建）
  ├── feature-branch-1/              # Worktree 子目录 1
  ├── feature-branch-2/              # Worktree 子目录 2
  └── ...
```

例如：
```
~/Work/Gravtice/AgentBox/           # 主仓库
~/Work/Gravtice/AgentBox-worktrees/ # Worktrees 目录
  ├── v1.0.1/                                      # Worktree: develop/v1.0.1
  ├── v1.0.2/                                      # Worktree: develop/v1.0.2
  └── feature-auth/                                # Worktree: feature/auth
```

## 核心特性

### 1. 自动检测主仓库

系统会自动检测当前目录：
- 如果是主仓库目录，直接使用
- 如果是 worktree 子目录，自动检测并使用主仓库目录

检测方式：
1. **Git 命令检测**：通过 `git rev-parse --git-common-dir` 检测真实的 worktree
2. **目录命名规范推断**：如果父目录名以 `-worktrees` 结尾，推断主仓库位置

### 2. 统一的容器命名

容器名始终基于主仓库目录的 basename 生成，确保：
- 从主目录启动：`gbox-{agent}-{主目录名}`
- 从 worktree 子目录启动：`gbox-{agent}-{主目录名}`（相同）

例如：
```bash
# 从主目录启动
cd ~/Work/Gravtice/AgentBox
./gbox claude
# 容器名: gbox-claude-agentbox

# 从 worktree 启动
cd ~/Work/Gravtice/AgentBox-worktrees/feature-auth
./gbox claude
# 容器名: gbox-claude-agentbox (相同！)
```

### 3. 双目录挂载

容器会同时挂载主目录和 worktrees 目录：
```
-v /path/to/project:/path/to/project
-v /path/to/project-worktrees:/path/to/project-worktrees
```

这确保：
- Worktree 可以访问主仓库的 `.git` 目录
- 容器内可以自由切换到任何 worktree
- Git 命令在 worktree 中正常工作

### 4. 自动创建 Worktrees 目录

当启动容器时，如果 worktrees 目录不存在，会自动创建：
```bash
mkdir -p /path/to/project-worktrees
```

## 使用示例

### 创建和使用 Worktree

```bash
# 1. 在主仓库中创建 worktree
cd ~/Work/Gravtice/AgentBox
git worktree add ../AgentBox-worktrees/feature-auth feature/auth

# 2. 进入 worktree 并启动容器
cd ../AgentBox-worktrees/feature-auth
./gbox claude

# 3. 验证容器名（应该和主仓库一致）
./gbox list
# 输出: gbox-claude-agentbox
```

### 在不同 Worktree 之间切换

```bash
# 当前在 worktree A
cd ~/Work/Gravtice/AgentBox-worktrees/feature-a
./gbox claude

# 切换到 worktree B（使用同一个容器）
cd ../feature-b
./gbox claude  # 连接到已有容器
```

### 多 Agent 支持

每个 agent 有独立的容器，但都遵循统一命名规则：

```bash
# Claude Agent
./gbox claude          # gbox-claude-agentbox
./gbox happy claude    # gbox-happy-claude-agentbox

# Codex Agent
./gbox codex           # gbox-codex-agentbox
./gbox happy codex     # gbox-happy-codex-agentbox
```

## 技术实现

### 核心函数

#### `get_main_repo_dir(work_dir)`
检测并获取主仓库目录：
```bash
# 从主目录调用
get_main_repo_dir "/path/to/project"
# 返回: /path/to/project

# 从 worktree 调用
get_main_repo_dir "/path/to/project-worktrees/feature"
# 返回: /path/to/project
```

#### `get_worktree_dir(work_dir)`
获取 worktrees 目录路径（自动基于主仓库目录）：
```bash
get_worktree_dir "/path/to/project"
# 返回: /path/to/project-worktrees

get_worktree_dir "/path/to/project-worktrees/feature"
# 返回: /path/to/project-worktrees (相同！)
```

#### `generate_container_name(run_mode, agent, work_dir)`
生成容器名（始终基于主仓库目录）：
```bash
generate_container_name "only-local" "claude" "/path/to/project"
# 返回: gbox-claude-project

generate_container_name "only-local" "claude" "/path/to/project-worktrees/feature"
# 返回: gbox-claude-project (相同！)
```

### 容器挂载配置

```bash
docker run \
    -v "$main_dir:$main_dir" \
    -v "$worktree_dir:$worktree_dir" \
    -w "$work_dir" \
    ...
```

参数说明：
- `$main_dir`: 主仓库目录（自动检测）
- `$worktree_dir`: Worktrees 目录（自动创建）
- `$work_dir`: 实际工作目录（可能是主目录或 worktree 子目录）

## 优势

1. **统一环境**：无论从哪个目录启动，都使用同一个容器，避免环境不一致
2. **资源节约**：不会为每个 worktree 创建独立容器，节省系统资源
3. **配置共享**：所有 worktree 共享同一份 Claude/Codex/Gemini 配置
4. **无缝切换**：可以在不同 worktree 之间自由切换，无需重新配置

## 测试验证

运行测试脚本验证功能：
```bash
./test_worktree_support.sh
```

测试覆盖：
- ✓ 主目录检测
- ✓ Worktree 子目录检测
- ✓ Worktrees 目录规范
- ✓ 容器名统一性
- ✓ 真实 Git Worktree 环境

## 注意事项

1. **目录命名规范必须遵守**：
   - 主目录：`/path/to/project`
   - Worktrees 目录：`/path/to/project-worktrees`
   - 不要自定义 worktrees 目录名

2. **Git Worktree 创建建议**：
   ```bash
   # 推荐：使用相对路径，确保目录结构正确
   git worktree add ../project-worktrees/feature-name branch-name

   # 避免：使用绝对路径可能导致路径不一致
   git worktree add /some/other/path feature-name
   ```

3. **容器状态管理**：
   - 容器会保持运行，即使你切换到其他 worktree
   - 使用 `./gbox stop <container>` 停止容器
   - 使用 `./gbox list` 查看运行中的容器

## 故障排查

### 问题：从 worktree 启动时创建了新容器

**原因**：可能是 worktrees 目录命名不符合规范

**解决**：
```bash
# 检查目录结构
ls -la /path/to/project*

# 确保符合规范：
# /path/to/project/          <- 主目录
# /path/to/project-worktrees/ <- worktrees 目录
```

### 问题：容器内无法访问 worktree

**原因**：worktrees 目录未正确挂载

**解决**：
```bash
# 1. 停止并删除容器
./gbox stop <container>

# 2. 重新创建容器（会自动挂载 worktrees 目录）
./gbox claude
```

### 问题：Git 命令在 worktree 中报错

**原因**：主仓库目录未挂载

**解决**：确保使用最新版本的 gbox，已自动挂载主仓库目录

## 更新日志

### v1.0.4 (2025-01-13)
- ✅ 添加 `get_main_repo_dir()` 函数，自动检测主仓库
- ✅ 修改 `get_worktree_dir()` 函数，基于主仓库目录生成 worktrees 路径
- ✅ 修改 `generate_container_name()` 函数，确保基于主仓库名称
- ✅ 修改 `start_container()` 函数，同时挂载主目录和 worktrees 目录
- ✅ 添加 `GBOX_MAIN_DIR` 环境变量到容器
- ✅ 添加测试脚本 `test_worktree_support.sh`
