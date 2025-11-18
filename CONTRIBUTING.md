# 贡献指南

感谢你考虑为 AgentBox 做出贡献！本文档将帮助你了解如何参与项目。

## 📋 行为准则

### 我们的承诺

为了营造开放和友好的环境,我们承诺:

- 使用友好和包容的语言
- 尊重不同的观点和经验
- 优雅地接受建设性批评
- 关注对社区最有利的事情
- 对其他社区成员表示同理心

## 🤝 如何贡献

### 报告 Bug

在提交 Bug 报告前,请先搜索现有的 [Issues](https://github.com/Gravtice/AgentBox/issues) 确认问题尚未被报告。

**优秀的 Bug 报告应包含:**

1. **清晰的标题** - 简洁描述问题
2. **复现步骤** - 详细的步骤说明
3. **预期行为** - 你期望发生什么
4. **实际行为** - 实际发生了什么
5. **环境信息** - 操作系统、Docker 版本等
6. **日志和截图** - 相关的错误日志或截图

**示例:**

```markdown
## Bug 描述
容器启动时提示权限错误

## 复现步骤
1. 执行 `./gbox claude`
2. 容器启动
3. 提示 "Permission denied: /.claude.json"

## 环境信息
- OS: macOS 14.1
- Docker: 24.0.6
- AgentBox: v1.0.0

## 错误日志
```
Error: EACCES: permission denied, open '/.claude.json'
```
```

### 提出功能建议

我们欢迎新功能建议！

**优秀的功能建议应包含:**

1. **功能描述** - 清晰描述建议的功能
2. **使用场景** - 为什么需要这个功能
3. **预期效果** - 如何实现和使用
4. **替代方案** - 是否考虑过其他方案

**示例:**

```markdown
## 功能建议
支持 Docker Compose 项目

## 使用场景
很多项目使用 docker-compose.yml 定义多个服务,希望 gbox 能自动识别并启动这些服务。

## 预期效果
- 自动检测 docker-compose.yml
- 启动所有定义的服务
- 支持服务间网络通信

## 替代方案
手动启动 docker-compose,但不如集成方便
```

### 提交 Pull Request

#### 准备工作

1. **Fork 仓库**
   ```bash
   # 在 GitHub 上 Fork 仓库
   # 然后克隆你的 Fork
   git clone https://github.com/YOUR_USERNAME/AgentBox.git
   cd AgentBox
   ```

2. **创建分支**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **配置上游仓库**
   ```bash
   git remote add upstream https://github.com/Gravtice/AgentBox.git
   ```

#### 开发流程

1. **保持同步**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **编写代码**
   - 遵循项目代码风格
   - 添加必要的注释
   - 保持代码简洁

3. **测试**
   ```bash
   # 测试基本功能
   ./gbox claude

   # 测试修改的功能
   # ... 根据具体修改进行测试

   # 语法检查
   bash -n gbox
   bash -n lib/*.sh
   ```

4. **提交更改**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   ```

#### 提交信息规范

使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 格式:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type 类型:**
- `feat` - 新功能
- `fix` - Bug 修复
- `docs` - 文档更新
- `style` - 代码格式 (不影响功能)
- `refactor` - 重构 (不是新功能也不是修复)
- `perf` - 性能优化
- `test` - 测试相关
- `chore` - 构建/工具相关

**示例:**

```
feat(oauth): 支持自动切换 OAuth 账号

添加账号达到限制时自动切换到其他可用账号的功能。

- 扫描所有可用账号
- 检测当前账号使用情况
- 自动切换到可用账号
- 更新 .claude.json 配置

Closes #123
```

#### 创建 Pull Request

1. **推送分支**
   ```bash
   git push origin feature/amazing-feature
   ```

2. **创建 PR**
   - 访问 GitHub 仓库
   - 点击 "New Pull Request"
   - 选择你的分支
   - 填写 PR 描述

**PR 描述模板:**

```markdown
## 变更说明
简要描述本次 PR 的目的和内容

## 变更类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 文档更新
- [ ] 代码重构
- [ ] 性能优化

## 测试
描述如何测试这些变更

## 相关 Issue
Closes #123

## 截图 (如适用)
添加相关截图

## 检查清单
- [ ] 代码遵循项目风格
- [ ] 已添加必要的注释
- [ ] 已更新相关文档
- [ ] 已完成本地测试
- [ ] 提交信息符合规范
```

## 💻 开发指南

### 项目结构

```
AgentBox/
├── gbox                 # 主入口脚本
├── lib/                 # 模块化库
│   ├── common.sh        # 通用工具
│   ├── container.sh     # 容器管理
│   ├── agent.sh         # Agent 会话
│   └── ...
├── docs/                # 文档
├── Dockerfile           # 镜像构建
└── README.md            # 项目说明
```

### 代码风格

#### Shell 脚本

```bash
# ✅ 好的风格
function my_function() {
    local param1="$1"
    local param2="$2"

    if [[ -z "$param1" ]]; then
        error "参数不能为空"
        return 1
    fi

    echo "处理: $param1"
    return 0
}

# ❌ 不好的风格
my_function() {
a=$1
if [ -z "$a" ]
then
echo "error"
fi
}
```

**规范:**
- 使用 4 空格缩进
- 函数使用 `function name()` 格式
- 变量使用小写+下划线
- 常量使用大写+下划线
- 使用 `[[ ]]` 而不是 `[ ]`
- 字符串使用双引号
- 添加必要的注释

#### 文档

```markdown
# ✅ 好的文档
## 功能描述

清晰简洁的描述

### 使用示例

\`\`\`bash
./gbox claude
\`\`\`

### 参数说明

- `--memory` - 内存限制 (默认: 4g)

# ❌ 不好的文档
功能xxx

用法: xxx
```

### 测试

#### 手动测试清单

新增功能时,请确保测试:

- [ ] 基本功能正常
- [ ] 错误处理正确
- [ ] 日志输出清晰
- [ ] 不影响现有功能
- [ ] 文档已更新

#### 测试脚本

```bash
# 测试基本命令
./gbox help
./gbox list
./gbox status

# 测试 Agent 启动
./gbox claude
./gbox happy claude
./gbox codex

# 测试容器管理
./gbox stop <container>
./gbox logs <container>
./gbox shell <container>

# 测试 OAuth 管理
./gbox oauth claude status
./gbox oauth claude list
```

## 📚 开发资源

### 文档
- [快速入门](./QUICKSTART.md)
- [架构设计](./docs/ARCHITECTURE.md)

### 工具
- [shellcheck](https://www.shellcheck.net/) - Shell 脚本检查
- [shfmt](https://github.com/mvdan/sh) - Shell 脚本格式化

### 学习资源
- [Bash 编程指南](https://tldp.org/LDP/abs/html/)
- [Docker 文档](https://docs.docker.com/)
- [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)

## 🎓 最佳实践

### 1. 小步提交

每次提交应该:
- 只做一件事
- 可以独立审查
- 通过所有测试
- 包含清晰的提交信息

### 2. 文档先行

添加新功能时:
1. 先更新文档
2. 再实现功能
3. 确保文档和代码一致

### 3. 向后兼容

除非主版本更新,否则:
- 不要破坏现有 API
- 不要移除现有功能
- 添加功能时保持兼容

### 4. 代码审查

提交 PR 后:
- 回应审查意见
- 及时更新代码
- 保持礼貌友好

## 🆘 获取帮助

遇到问题？

1. **查看文档** - [README](./README.md), [QUICKSTART](./QUICKSTART.md)
2. **搜索 Issues** - 可能已有相关讨论
3. **提问** - 在 [Discussions](https://github.com/Gravtice/AgentBox/discussions) 提问
4. **报告 Bug** - 创建新 [Issue](https://github.com/Gravtice/AgentBox/issues)

## 📮 联系方式

- **GitHub Issues**: [提交问题](https://github.com/Gravtice/AgentBox/issues)
- **GitHub Discussions**: [参与讨论](https://github.com/Gravtice/AgentBox/discussions)

## 🙏 致谢

感谢所有贡献者的付出！

你的贡献会列在:
- [CHANGELOG.md](./CHANGELOG.md)
- GitHub Contributors

---

**再次感谢你的贡献！** ❤️
