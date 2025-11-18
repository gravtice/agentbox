# Zsh 补全插件更新日志

## [1.0.1] - 2025-11-18

### 修复
- 🔧 移除已废弃的 `extend` 命令补全
- 📝 更新所有文档，移除 extend 相关引用

### 变更
- 🗑️ 删除未使用的 `gbox.plugin.dynamic.zsh` 文件（该文件未被安装脚本使用，且未真正实现动态功能）
- 📝 `README.md` - 移除 extend 相关说明
- 📝 `MAINTENANCE.md` - 移除 extend 维护指南
- 📝 `QUICKREF.md` - 移除 extend 快速参考

## [1.0.0] - 2025-11-13

### 新增功能
- ✨ 完整的 Zsh 自动补全支持
- 🎯 主命令补全 (list, status, stop, clean, oauth, keepalive, 等)
- 🤖 AI Agent 补全 (claude, codex, gemini)
- ⚙️ 参数选项补全 (--memory, --cpu, --ports, --keep, --name)
- 📦 容器名动态补全 (从 Docker 实时获取)
- 🔧 子命令补全 (oauth, keepalive)
- 🚀 远程协作模式补全 (gbox happy <agent>)
- ⌨️ 快捷别名 (gb, gbl, gbs, gbh, gbc, gbcd, gbgm)

### 技术实现
- 使用 Zsh completion system with `_arguments`
- 实现为 oh-my-zsh 自定义插件
- 支持多级子命令补全
- 动态获取运行中的容器列表

### 文件结构
```
zsh-completion/
├── gbox.plugin.zsh    # 插件主文件
├── install.sh         # 自动安装脚本
├── README.md          # 使用文档
└── CHANGELOG.md       # 更新日志
```

### 安装位置
- 源码: `AgentBox/zsh-completion/`
- 安装: `~/.oh-my-zsh/custom/plugins/gbox/`

### 使用要求
- Zsh 5.0+
- oh-my-zsh
- Docker (用于容器名补全)

### 特性亮点
1. **智能补全**: 根据上下文动态提供补全选项
2. **描述支持**: 每个选项都有中文说明
3. **容器感知**: 实时获取运行中的 gbox 容器
4. **模式识别**: 区分本地模式和远程协作模式
5. **参数透传**: 支持 `--` 分隔符后的参数补全

### 已知限制
- 仅支持 oh-my-zsh
- 容器名补全需要 Docker 运行
- 不支持 bash 补全 (计划中)

### 未来计划
- [ ] 支持 bash 补全
- [ ] 支持 fish shell 补全
- [ ] 更智能的参数值补全 (如内存大小建议)
- [ ] 支持自定义补全配置

### 贡献者
- Initial implementation: Claude Code + User

### 参考资源
- [Zsh Completion System](http://zsh.sourceforge.net/Doc/Release/Completion-System.html)
- [oh-my-zsh Custom Plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Customization#overriding-and-adding-plugins)
