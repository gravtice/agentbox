# 自定义 AgentBox 镜像

本文档介绍如何基于 AgentBox 标准镜像创建自定义镜像,预装项目所需的依赖和工具。

## 🎯 使用场景

- **团队统一环境** - 所有成员使用相同的开发环境
- **预装项目依赖** - 避免每次启动都要安装依赖
- **自定义工具** - 安装团队常用的工具和配置
- **特定语言/框架** - 针对特定技术栈优化镜像

## 📋 前置要求

- 已安装 Docker
- 已构建或拉取 AgentBox 标准镜像
- 基本的 Dockerfile 知识

## 🚀 快速开始

### 1. 创建 Dockerfile

在项目根目录创建 `Dockerfile.custom`:

```dockerfile
# 基于 AgentBox 标准镜像
FROM gravtice/agentbox:latest

# 切换到 root 用户安装系统包
USER root

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    vim \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# 切换回 guser 用户
USER guser

# 安装 Python 依赖
RUN pip install --no-cache-dir \
    django==4.2 \
    djangorestframework==3.14 \
    celery==5.3

# 安装 Node.js 依赖
RUN npm install -g \
    typescript \
    @vue/cli \
    vite

# 设置工作目录
WORKDIR /home/guser
```

### 2. 构建自定义镜像

```bash
# 构建镜像
docker build -f Dockerfile.custom -t myproject/agentbox:1.0 .

# 查看镜像
docker images | grep myproject
```

### 3. 使用自定义镜像

修改 `gbox` 脚本中的镜像名称:

```bash
# 方式1: 直接修改 lib/common.sh
DEFAULT_IMAGE_NAME="myproject/agentbox"
DEFAULT_IMAGE_TAG="1.0"

# 方式2: 使用环境变量
export GBOX_IMAGE=myproject/agentbox:1.0
./gbox claude
```

## 📝 常用定制示例

### 示例 1: Python Web 项目

```dockerfile
FROM gravtice/agentbox:latest

USER root
RUN apt-get update && apt-get install -y \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

USER guser
RUN pip install --no-cache-dir \
    django==4.2 \
    djangorestframework==3.14 \
    celery==5.3 \
    redis==5.0 \
    psycopg2-binary==2.9 \
    gunicorn==21.2 \
    pytest==7.4 \
    pytest-django==4.5

WORKDIR /home/guser
```

### 示例 2: Node.js 全栈项目

```dockerfile
FROM gravtice/agentbox:latest

USER root
RUN apt-get update && apt-get install -y \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

USER guser
RUN npm install -g \
    typescript \
    @nestjs/cli \
    @vue/cli \
    vite \
    prisma \
    pm2

# 配置 npm 镜像 (可选,加速安装)
RUN npm config set registry https://registry.npmmirror.com

WORKDIR /home/guser
```

### 示例 3: Rust 项目

```dockerfile
FROM gravtice/agentbox:latest

USER root
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

USER guser

# 安装 Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/guser/.cargo/bin:${PATH}"

# 安装常用 Rust 工具
RUN cargo install \
    cargo-watch \
    cargo-edit \
    cargo-expand

WORKDIR /home/guser
```

### 示例 4: Go 项目

```dockerfile
FROM gravtice/agentbox:latest

USER root

# 安装 Go
RUN wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz && \
    rm go1.21.5.linux-amd64.tar.gz

USER guser

# 配置 Go 环境变量
ENV PATH="/usr/local/go/bin:/home/guser/go/bin:${PATH}"
ENV GOPATH="/home/guser/go"
ENV GOPROXY="https://goproxy.cn,direct"

# 安装常用 Go 工具
RUN go install golang.org/x/tools/gopls@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest

WORKDIR /home/guser
```

### 示例 5: 数据科学项目

```dockerfile
FROM gravtice/agentbox:latest

USER root
RUN apt-get update && apt-get install -y \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

USER guser

# 安装数据科学常用库
RUN pip install --no-cache-dir \
    numpy==1.24 \
    pandas==2.0 \
    matplotlib==3.7 \
    scikit-learn==1.3 \
    jupyter==1.0 \
    jupyterlab==4.0

WORKDIR /home/guser
```

## 🔧 高级定制

### 1. 多阶段构建

优化镜像大小:

```dockerfile
# Stage 1: 构建依赖
FROM gravtice/agentbox:latest AS builder

USER guser
WORKDIR /build

# 复制依赖文件
COPY requirements.txt .

# 安装依赖
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: 最终镜像
FROM gravtice/agentbox:latest

USER guser

# 只复制已安装的依赖
COPY --from=builder /home/guser/.local /home/guser/.local

ENV PATH="/home/guser/.local/bin:${PATH}"

WORKDIR /home/guser
```

### 2. 添加自定义配置

```dockerfile
FROM gravtice/agentbox:latest

USER guser

# 复制自定义配置文件
COPY --chown=guser:guser .vimrc /home/guser/
COPY --chown=guser:guser .tmux.conf /home/guser/

# 配置 Git 别名
RUN git config --global alias.st status && \
    git config --global alias.co checkout && \
    git config --global alias.br branch

WORKDIR /home/guser
```

### 3. 预下载大文件

```dockerfile
FROM gravtice/agentbox:latest

USER guser

# 预下载模型文件
RUN mkdir -p /home/guser/.cache/models && \
    wget -O /home/guser/.cache/models/model.bin \
    https://example.com/model.bin

WORKDIR /home/guser
```

### 4. 设置环境变量

```dockerfile
FROM gravtice/agentbox:latest

USER guser

# 设置项目相关环境变量
ENV DJANGO_SETTINGS_MODULE=myproject.settings
ENV DATABASE_URL=postgresql://localhost/mydb
ENV REDIS_URL=redis://localhost:6379

WORKDIR /home/guser
```

## 📦 镜像管理

### 构建不同版本

```bash
# 开发版本
docker build -f Dockerfile.custom -t myproject/agentbox:dev .

# 生产版本
docker build -f Dockerfile.custom -t myproject/agentbox:prod .

# 带版本号
docker build -f Dockerfile.custom -t myproject/agentbox:1.0.0 .
```

### 推送到私有仓库

```bash
# 登录私有仓库
docker login registry.example.com

# 打标签
docker tag myproject/agentbox:1.0 registry.example.com/myproject/agentbox:1.0

# 推送
docker push registry.example.com/myproject/agentbox:1.0
```

### 团队使用

```bash
# 团队成员拉取镜像
docker pull registry.example.com/myproject/agentbox:1.0

# 配置 gbox 使用自定义镜像
export GBOX_IMAGE=registry.example.com/myproject/agentbox:1.0
./gbox claude
```

## 🎓 最佳实践

### 1. 分层优化

```dockerfile
# ✅ 好: 先安装不常变化的依赖
RUN apt-get update && apt-get install -y vim
RUN pip install django  # 框架
RUN pip install mylib   # 项目依赖 (常变化)

# ❌ 差: 一次性安装所有依赖 (变化时重新安装全部)
RUN apt-get update && apt-get install -y vim && \
    pip install django mylib
```

### 2. 清理缓存

```dockerfile
# ✅ 好: 及时清理缓存
RUN apt-get update && apt-get install -y vim \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir django

# ❌ 差: 不清理缓存,镜像体积大
RUN apt-get update && apt-get install -y vim
RUN pip install django
```

### 3. 使用 .dockerignore

创建 `.dockerignore` 文件:

```
# Git
.git
.gitignore

# Python
__pycache__
*.py[cod]
.venv
*.egg-info

# Node.js
node_modules
npm-debug.log

# IDE
.vscode
.idea

# 其他
.DS_Store
*.log
```

### 4. 固定版本

```dockerfile
# ✅ 好: 固定版本,可重现构建
RUN pip install django==4.2.0

# ❌ 差: 不固定版本,可能每次构建不一致
RUN pip install django
```

### 5. 使用国内镜像

```dockerfile
# Python pip 镜像
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# npm 镜像
RUN npm config set registry https://registry.npmmirror.com

# apt 镜像 (Ubuntu)
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
```

## 🔍 调试技巧

### 1. 交互式构建

```bash
# 构建到特定阶段
docker build --target builder -t debug .

# 运行容器进行调试
docker run -it debug bash
```

### 2. 查看镜像历史

```bash
# 查看镜像构建历史
docker history myproject/agentbox:1.0

# 查看每层大小
docker history --no-trunc myproject/agentbox:1.0
```

### 3. Dive 工具

使用 [dive](https://github.com/wagoodman/dive) 分析镜像:

```bash
# 安装 dive
brew install dive

# 分析镜像
dive myproject/agentbox:1.0
```

## 📊 示例项目

完整的自定义镜像示例项目结构:

```
myproject/
├── Dockerfile.custom       # 自定义镜像
├── .dockerignore           # Docker 忽略文件
├── requirements.txt        # Python 依赖
├── package.json            # Node.js 依赖
└── scripts/
    ├── build-image.sh      # 构建脚本
    └── push-image.sh       # 推送脚本
```

**build-image.sh:**
```bash
#!/bin/bash
set -e

VERSION=${1:-latest}
IMAGE_NAME="myproject/agentbox"

echo "Building $IMAGE_NAME:$VERSION..."
docker build -f Dockerfile.custom -t $IMAGE_NAME:$VERSION .

echo "Tagging as latest..."
docker tag $IMAGE_NAME:$VERSION $IMAGE_NAME:latest

echo "Build complete!"
docker images | grep $IMAGE_NAME
```

**push-image.sh:**
```bash
#!/bin/bash
set -e

VERSION=${1:-latest}
IMAGE_NAME="myproject/agentbox"
REGISTRY="registry.example.com"

echo "Tagging for registry..."
docker tag $IMAGE_NAME:$VERSION $REGISTRY/$IMAGE_NAME:$VERSION

echo "Pushing to $REGISTRY..."
docker push $REGISTRY/$IMAGE_NAME:$VERSION

echo "Push complete!"
```

## 🆘 常见问题

### Q: 如何减小镜像体积？

A:
1. 使用 `--no-cache-dir` (pip)
2. 及时清理 apt 缓存
3. 使用多阶段构建
4. 合并 RUN 命令减少层数

### Q: 构建很慢怎么办？

A:
1. 使用国内镜像源
2. 利用 Docker 层缓存
3. 优化 Dockerfile 顺序

### Q: 如何在自定义镜像中保留 AgentBox 功能？

A: 只要基于 `gravtice/agentbox:latest`,所有功能都会保留。不要修改:
- 用户 `guser`
- 工作目录 `/home/guser`
- 环境变量 (除非明确知道影响)

### Q: 可以使用不同的基础镜像吗？

A: 不建议。AgentBox 镜像包含了预配置的 Claude Code、Happy 等工具。如果需要完全不同的基础,建议参考 AgentBox 的 Dockerfile 重新构建。

## 📚 参考资料

- [Dockerfile 最佳实践](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [AgentBox 构建指南](./docs/dev/BUILD_GUIDE.md)
- [Docker 多阶段构建](https://docs.docker.com/build/building/multi-stage/)

---

**享受定制化的开发环境！** 🎨
