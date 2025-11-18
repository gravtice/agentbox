# Zsh 补全插件维护指南

## 📝 需要同步更新的场景

当 gbox 代码有以下变化时,需要同步更新补全插件:

### 1. 添加/删除主命令

**文件位置**: `gbox` (主脚本 case 语句)

**需要更新**: `gbox.plugin.zsh` 第 12-29 行

**示例**:
```bash
# 如果在 gbox 中添加了新命令 'restart'
# 需要在 gbox.plugin.zsh 的 commands 数组中添加:
'restart:重启容器'
```

**检查方法**:
```bash
# 对比 gbox case 语句和插件中的 commands 数组
grep -A 50 "^case.*in$" gbox | grep ")"
```

### 2. 添加/删除 AI Agent

**文件位置**: `lib/common.sh` 的 `SUPPORTED_AGENTS` 数组

**需要更新**: `gbox.plugin.zsh` 第 32-36 行

**示例**:
```bash
# 如果添加了新 agent 'gpt4'
# lib/common.sh:
SUPPORTED_AGENTS=("claude" "codex" "gemini" "gpt4")

# gbox.plugin.zsh 需要添加:
'gpt4:GPT-4 Agent'
```

**检查方法**:
```bash
# 对比两个文件中的 agents
grep "SUPPORTED_AGENTS" lib/common.sh
grep -A 5 "agents=(" zsh-completion/gbox.plugin.zsh
```

### 3. 修改 gbox 参数选项

**文件位置**: `gbox` 主脚本的参数解析部分

**需要更新**: `gbox.plugin.zsh` 第 140-151 行 (gbox_opts 数组)

**示例**:
```bash
# 如果添加了新参数 --disk
# gbox.plugin.zsh 需要添加:
'--disk:磁盘限制(如 10g, 20g)'
```

**检查方法**:
```bash
# 查看 gbox 中的参数解析
grep -E "\-\-memory|\-\-cpu|\-\-ports|\-\-keep|\-\-name" gbox
```

### 4. 修改子命令 (oauth/keepalive)

**文件位置**:
- `lib/oauth.sh` - oauth 子命令
- `lib/keepalive.sh` - keepalive 子命令

**需要更新**: `gbox.plugin.zsh` 第 39-59 行

**示例**:
```bash
# 如果 keepalive 添加了新子命令 'status'
# gbox.plugin.zsh 的 keepalive_cmds 需要添加:
'status:查看维持容器状态'
```

**检查方法**:
```bash
# 查看各个模块的子命令
grep "case.*in$" -A 20 lib/keepalive.sh
grep "case.*in$" -A 20 lib/oauth.sh
```

## 🔍 完整性检查脚本

创建一个脚本来检查补全插件是否需要更新:

```bash
#!/bin/bash
# check_completion_sync.sh - 检查补全插件是否与 gbox 同步

echo "检查 Zsh 补全插件同步状态..."
echo ""

# 1. 检查 agents
echo "1. 检查 AI Agents:"
echo "   lib/common.sh 中定义:"
grep "SUPPORTED_AGENTS" lib/common.sh

echo "   补全插件中定义:"
grep -A 5 "# 定义支持的 AI agents" zsh-completion/gbox.plugin.zsh | grep "'"

echo ""

# 2. 检查主命令 (简单示例)
echo "2. 检查主命令:"
echo "   gbox 中的 case 分支:"
grep -E "^\s*(list|status|stop|oauth|keepalive|pull|push|logs|exec|shell|build|help|happy)\)" gbox | head -15

echo ""
echo "   补全插件中定义:"
grep -A 20 "# 定义主命令" zsh-completion/gbox.plugin.zsh | grep "'" | head -15

echo ""
echo "请手动对比以上输出,确认是否需要更新补全插件"
```

## 🚀 推荐工作流

### 方式 1: 每次发布前检查

在发布新版本之前:

1. 运行检查脚本
2. 手动对比差异
3. 更新 `gbox.plugin.zsh`
4. 更新 `CHANGELOG.md`
5. 提交修改

### 方式 2: Git Hook

在 `.git/hooks/pre-commit` 中添加检查:

```bash
#!/bin/bash
# 检查是否修改了命令相关文件

if git diff --cached --name-only | grep -E "^(gbox|lib/common.sh|lib/oauth.sh|lib/keepalive.sh)$"; then
    echo "⚠️  警告: 检测到 gbox 核心文件修改"
    echo "请检查是否需要更新 zsh-completion/gbox.plugin.zsh"
    echo ""
    echo "按 Enter 继续提交,或 Ctrl+C 取消"
    read
fi
```

### 方式 3: CI 自动检查 (未来)

在 CI 流程中添加自动化测试,比对:
- gbox 定义的命令 vs 插件中的命令
- lib/common.sh 的 agents vs 插件中的 agents

## 📋 更新清单模板

每次更新补全插件时,使用此清单:

```markdown
## Zsh 补全插件更新清单

- [ ] 检查主命令列表是否完整
- [ ] 检查 AI agents 列表是否完整
- [ ] 检查 gbox 参数选项是否完整
- [ ] 检查 oauth 子命令是否完整
- [ ] 检查 keepalive 子命令是否完整
- [ ] 更新 CHANGELOG.md
- [ ] 测试补全功能
- [ ] 更新安装脚本中的版本号(如需要)
```

## 🔄 版本管理建议

1. **插件版本号**: 在 `gbox.plugin.zsh` 开头添加版本号注释
   ```bash
   # Version: 1.0.0
   # Last Updated: 2025-11-13
   # Compatible with: gbox v1.0.4+
   ```

2. **CHANGELOG**: 每次更新都记录在 `CHANGELOG.md`

3. **兼容性**: 在 README 中说明插件支持的 gbox 版本范围

## 📞 需要帮助?

如果不确定是否需要更新补全插件,可以:

1. 查看 `git log` 中最近的 gbox 修改
2. 运行 `./gbox help` 查看最新命令列表
3. 对比 `lib/common.sh` 中的 `SUPPORTED_AGENTS`

---

**重要提示**: 补全插件的更新不会自动同步到用户环境,用户需要重新运行 `./zsh-completion/install.sh` 或手动更新 `~/.oh-my-zsh/custom/plugins/gbox/gbox.plugin.zsh`。

建议在 CHANGELOG 和 Release Notes 中提醒用户更新补全插件。
