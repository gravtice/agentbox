# gbox Zsh 自动补全插件

为 `gbox` 命令提供智能自动补全功能,类似 git 命令的体验。

## 功能特性

### 1. 主命令补全
输入 `gbox ` 后按 `Tab`,自动补全所有可用命令:
- `list` - 列出运行中的容器
- `status` - 显示所有容器详细状态
- `stop` - 停止并删除容器
- `stop-all` - 停止所有容器
- `clean` - 清理所有停止的容器
- `oauth` - OAuth 账号管理
- `keepalive` - 维持容器管理
- `pull` / `push` / `build` - 镜像操作
- `logs` / `exec` / `shell` - 容器操作
- `help` - 显示帮助信息
- `happy` - 远程协作模式

### 2. AI Agent 补全
输入 `gbox ` 后按 `Tab`,也会显示所有支持的 AI agents:
- `claude` - Claude Code
- `codex` - OpenAI Codex
- `gemini` - Google Gemini

### 3. 参数选项补全
输入 `gbox claude ` 后按 `Tab`,自动补全 gbox 参数:
- `--memory` / `-m` - 内存限制
- `--cpu` / `-c` - CPU 核心数
- `--ports` - 端口映射
- `--keep` - 退出后保留容器
- `--name` - 自定义容器名

### 4. 容器名动态补全
需要容器名的命令(`stop`, `logs`, `shell`, `exec`)会自动补全运行中的容器:
```bash
gbox stop <Tab>
# 自动显示: gbox-claude-project  gbox-codex-myapp  等
```

### 5. 子命令补全

**oauth 子命令:**
```bash
gbox oauth <Tab>
# 显示: claude  codex  gemini

gbox oauth claude <Tab>
# 显示: help  等
```

**keepalive 子命令:**
```bash
gbox keepalive <Tab>
# 显示: list  stop  stop-all  restart  logs  auto  help

gbox keepalive stop <Tab>
# 自动补全账号后缀
```

### 6. 远程协作模式补全
```bash
gbox happy <Tab>
# 显示: claude  codex  gemini

gbox happy claude <Tab>
# 显示 gbox 参数选项
```

## 快速安装

### 自动安装 (推荐)

从项目根目录运行:
```bash
./zsh-completion/install.sh
```

安装脚本会:
1. 复制插件文件到 `~/.oh-my-zsh/custom/plugins/gbox/`
2. 自动更新 `~/.zshrc`,添加 `gbox` 到 plugins 数组
3. 清理补全缓存
4. 提示你重新加载 shell

### 手动安装

如果你想手动安装:

1. 复制插件文件:
```bash
mkdir -p ~/.oh-my-zsh/custom/plugins/gbox
cp zsh-completion/gbox.plugin.zsh ~/.oh-my-zsh/custom/plugins/gbox/
```

2. 编辑 `~/.zshrc`,在 `plugins` 数组中添加 `gbox`:
```bash
plugins=(
    git
    docker
    # ... 其他插件
    gbox  # 添加这一行
)
```

3. 重新加载配置:
```bash
exec zsh
# 或者
source ~/.zshrc
```

## 使用示例

### 基本补全
```bash
gbox <Tab>
# 显示所有命令和 agents

gbox cl<Tab>
# 自动补全为: gbox claude

gbox list<Tab>
# 直接补全命令
```

### 参数补全
```bash
gbox claude --<Tab>
# 显示: --memory --cpu --ports --keep --name

gbox claude -<Tab>
# 显示: -m -c
```

### 容器名补全
```bash
gbox stop <Tab>
# 显示所有运行中的 gbox-* 容器

gbox logs gbox-<Tab>
# 自动补全容器名
```

### 子命令补全
```bash
gbox keepalive <Tab>
# 显示所有 keepalive 子命令

gbox oauth <Tab>
# 显示所有支持的 agents
```

## 快捷别名

插件还提供了一些快捷别名:

| 别名 | 完整命令 | 说明 |
|------|----------|------|
| `gb` | `gbox` | 主命令缩写 |
| `gbl` | `gbox list` | 列出容器 |
| `gbs` | `gbox status` | 查看状态 |
| `gbh` | `gbox happy` | 远程协作模式 |
| `gbc` | `gbox claude` | 运行 Claude |
| `gbcd` | `gbox codex` | 运行 Codex |
| `gbgm` | `gbox gemini` | 运行 Gemini |

使用示例:
```bash
gbc                    # 等同于 gbox claude
gbh claude             # 等同于 gbox happy claude
gbl                    # 等同于 gbox list
```

## 验证安装

安装完成后,在终端中测试:

```bash
# 1. 检查函数是否加载
type _gbox
# 期望输出: _gbox is a shell function from ...

# 2. 检查补全注册
echo ${_comps[gbox]}
# 期望输出: _gbox

# 3. 测试补全
gbox <Tab>
# 应该显示所有命令和 agents
```

## 故障排除

### 补全不工作
1. 确认已经重新加载 shell: `exec zsh`
2. 检查函数是否加载: `type _gbox`
3. 清理补全缓存: `rm ~/.zcompdump* && exec zsh`

### 容器名补全为空
- 确保有运行中的 gbox 容器: `docker ps --filter 'name=gbox-'`
- 检查 Docker 是否正常运行

### 只看到部分补全选项
这是正常的,尝试:
```bash
gbox cl<Tab>    # 应该补全为 claude
gbox li<Tab>    # 应该补全为 list
```

## 卸载

如果需要卸载:

1. 从 `~/.zshrc` 的 `plugins` 数组中移除 `gbox`
2. 删除插件目录: `rm -rf ~/.oh-my-zsh/custom/plugins/gbox`
3. 重新加载: `exec zsh`

## 技术说明

- 补全系统: Zsh completion system with `_arguments`
- 实现方式: oh-my-zsh 自定义插件
- 动态补全: 容器名从 Docker 实时获取
- 支持版本: Zsh 5.0+, oh-my-zsh

## 自定义

如果你想修改补全行为,可以编辑插件文件:
```bash
vim ~/.oh-my-zsh/custom/plugins/gbox/gbox.plugin.zsh
```

修改后重新加载:
```bash
exec zsh
```

## 维护指南

### 何时需要更新补全插件

当 gbox 有以下变化时,需要同步更新补全插件:

1. **添加/删除主命令** - 更新 `commands` 数组 (第12-29行)
2. **添加/删除 AI Agent** - 更新 `agents` 数组 (第32-36行)
3. **修改参数选项** - 更新 `gbox_opts` 数组 (第140-151行)
4. **修改子命令** - 更新相应的子命令数组 (第39-59行)

### 检查同步状态

运行自动检查脚本:
```bash
./zsh-completion/check_sync.sh
```

脚本会对比 gbox 源码和补全插件,报告不一致的地方。

### 更新流程

1. 修改 `gbox.plugin.zsh`
2. 运行 `./zsh-completion/check_sync.sh` 验证
3. 更新 `CHANGELOG.md`
4. 运行 `./zsh-completion/install.sh` 安装新版本
5. 测试补全功能

详细维护文档: [MAINTENANCE.md](MAINTENANCE.md)

## 贡献

欢迎提交问题和改进建议!插件源码位于: `zsh-completion/gbox.plugin.zsh`
