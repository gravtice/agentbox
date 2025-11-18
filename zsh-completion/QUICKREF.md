# gbox 补全快速参考

## 🚀 快速开始

```bash
# 安装
./zsh-completion/install.sh
exec zsh

# 测试
gbox <Tab>
```

## ⌨️ 补全示例

### 基本命令
```bash
gbox <Tab>              # 显示所有命令和 agents
gbox l<Tab>             # list
gbox s<Tab>             # status / stop / stop-all / shell
gbox cl<Tab>            # clean / claude
```

### AI Agents
```bash
gbox cl<Tab>            # claude
gbox co<Tab>            # codex
gbox ge<Tab>            # gemini
```

### 参数选项
```bash
gbox claude --<Tab>     # 显示所有参数选项
gbox claude -<Tab>      # 显示短选项 -m, -c
gbox claude --m<Tab>    # --memory
gbox claude --c<Tab>    # --cpu
```

### 容器名
```bash
gbox stop <Tab>         # 显示运行中的容器
gbox logs gbox-<Tab>    # 补全容器名
gbox shell <Tab>        # 补全容器名
gbox exec <Tab>         # 补全容器名
```

### 子命令

**keepalive:**
```bash
gbox keepalive <Tab>    # list, stop, stop-all, restart, logs, auto, help
gbox keepalive s<Tab>   # stop / stop-all
gbox keepalive stop <Tab>  # 补全账号后缀
```

**oauth:**
```bash
gbox oauth <Tab>        # claude, codex, gemini
gbox oauth claude <Tab> # help
```

### 远程协作模式
```bash
gbox happy <Tab>        # claude, codex, gemini
gbox happy claude <Tab> # 显示 gbox 参数
gbox happy claude --<Tab>  # --memory, --cpu, etc.
```

## 🎯 快捷别名

```bash
gb <Tab>                # 等同于 gbox
gbl                     # gbox list
gbs                     # gbox status
gbh <Tab>               # gbox happy
gbc                     # gbox claude
gbcd                    # gbox codex
gbgm                    # gbox gemini
```

## 🔍 调试命令

```bash
# 检查函数是否加载
type _gbox

# 检查补全注册
echo ${_comps[gbox]}

# 重新加载配置
exec zsh

# 清理缓存
rm ~/.zcompdump* && exec zsh
```

## ⚙️ 配置文件位置

- **源码**: `AgentBox/zsh-completion/gbox.plugin.zsh`
- **安装**: `~/.oh-my-zsh/custom/plugins/gbox/gbox.plugin.zsh`
- **配置**: `~/.zshrc` (plugins 数组)

## 📚 更多信息

- 完整文档: `zsh-completion/README.md`
- 安装说明: `./zsh-completion/install.sh`
- 更新日志: `zsh-completion/CHANGELOG.md`
