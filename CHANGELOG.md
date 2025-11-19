# 变更日志

本文档记录 AgentBox 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/),
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.1] - 2025-01-17

### 新增
- 支持多容器独立设备 ID 并共享登录态 (#80a454b)
- Happy CLI 更新至 hostname 自动检测版本 (#5a1bb6b)

### 移除
- 移除 shim API 和 API 模式功能 (#18d05fc)
- 移除 gbox extend 功能,简化工具设计 (#f74b84b)

### 文档
- 完整匹配 happy-cli 实际代码 (#96e473d)
- 更正权限修复方案为实际实现 (#7bd64b3)
- 精简文档,保留最终解决方案 (#c77735b)

## [1.0.0] - 2025-01-15

### 新增

#### 核心功能
- 工作目录驱动的容器自动管理
- Claude Code、Codex、Gemini 多 AI Agent 支持
- Happy 远程协作模式
- OAuth 多账号管理和自动切换
- Git Worktree 完整支持

#### 资源配置
- 内存和 CPU 限制配置
- 灵活的端口映射 (#6c54546, #14ddec9)
- 只读参考目录挂载 (#6c54546)
- 代理配置支持 (#5e5b03c)

#### 开发工具
- Zsh 自动补全插件 (#20382f7)
- OAuth 账号状态查看和切换
- Keepalive 自动维持登录态
- 容器日志查看和调试

### 优化

#### 性能
- 依赖缓存共享 (pip, npm, uv)
- Multi-stage Docker 镜像构建
- 自动 Git 子模块管理

#### 用户体验
- 一键启动,自动创建/连接容器
- 退出时自动清理容器
- 宿主机可直接编辑配置文件
- 智能容器命名

### 技术实现
- 从单文件 3546 行重构为模块化架构 (#REFACTORING_COMPLETE.md)
- 使用 git submodule 管理 happy-cli (#d56ab75)
- 环境变量驱动的权限自动跳过 (#9be1182, #b3cdd1f)
- Docker network 网络隔离

### 文档
- 完整的用户文档和快速入门
- 架构设计说明
- 开发者文档和贡献指南
- Zsh 补全维护文档 (#b346513)

### 修复
- 修复 git submodule 递归更新问题 (#4ac3281)
- 修复参考目录挂载安全问题 (#4038841)
- 修复传递参数给 agent 内部的问题 (#14ddec9)

## [未发布]

### 计划中
- 预构建镜像发布到 Docker Hub
- GitHub Actions CI/CD
- 更多 AI Agent 支持
- Web UI 管理界面

---

## 版本说明

### [主版本号] - 重大变更
- 破坏性变更
- 架构重构

### [次版本号] - 功能更新
- 新增功能
- 功能增强

### [修订号] - Bug 修复
- Bug 修复
- 文档更新
- 性能优化

## 贡献

欢迎提交 Issue 和 Pull Request!

查看 [贡献指南](./CONTRIBUTING.md) 了解如何参与项目。
