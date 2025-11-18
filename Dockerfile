# ============================================
# Stage 1: 构建 happy-cli
# ============================================
FROM node:20-slim AS happy-builder

# 复制 happy-cli 源码（从 git submodule）
COPY vendor/happy-cli /build
WORKDIR /build

# 安装依赖、构建并打包
# 清理 package-lock.json 和 node_modules 以解决 rollup 可选依赖问题
RUN rm -rf package-lock.json node_modules && \
    npm install && \
    npm run build && \
    npm pack

# ============================================
# Stage 2: 最终运行环境
# ============================================
FROM python:3.12-slim

# Gravtice AgentBox - AI Agent 容器化运行环境（完整版）
# 包含 Playwright 等重量级 MCP 依赖

# 镜像源配置参数（由 gbox 脚本根据时区自动设置）
ARG USE_CHINA_MIRROR=false

# 配置 APT 镜像源（中国时区使用阿里云镜像）
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources; \
    fi

# 安装系统依赖（包括常见 MCP 需要的库）
RUN apt-get update && apt-get install -y \
    # 基础开发工具
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    # 文本编辑器
    vim \
    nano \
    # 文件处理工具
    unzip \
    zip \
    jq \
    # 系统工具
    procps \
    less \
    htop \
    tree \
    lsof \
    # 编译工具（某些 npm 包需要）
    build-essential \
    # 浏览器相关依赖（playwright 等 MCP 需要）\
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxext6 \
    fonts-liberation \
    libappindicator3-1 \
    libu2f-udev \
    libvulkan1 \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# 安装Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# 配置 npm 镜像源（中国时区使用淘宝镜像）
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        npm config set registry https://registry.npmmirror.com; \
    fi

# 安装Claude Code CLI（使用npm全局安装）
RUN npm install -g @anthropic-ai/claude-code

# 从构建阶段安装 happy-coder（包含权限处理修复）
# happy 在容器内调用 claude，所有通信都在容器内完成
COPY --from=happy-builder /build/happy-coder-*.tgz /tmp/
RUN npm install -g /tmp/happy-coder-*.tgz && \
    rm /tmp/happy-coder-*.tgz

# 安装 OpenAI Codex CLI（编码助手工具）
RUN npm install -g @openai/codex

# 安装 Google Gemini CLI（AI 终端助手）
RUN npm install -g @google/gemini-cli

# 预装 playwright 及其浏览器依赖
# 这会增加约 500MB 镜像大小，但能确保 playwright MCP 正常工作
# 配置 Playwright 下载源（中国时区使用 npmmirror 镜像）
# 将浏览器安装到系统目录，所有用户都能访问
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        export PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/; \
    fi && \
    npm install -g playwright@1.48.0 && \
    npx playwright install chromium && \
    chmod -R 777 /usr/local/share/playwright
# 注意：跳过 install-deps，因为所有必要的系统依赖已在上面的 apt-get 步骤中安装

# 设置共享目录权限，允许所有用户创建子目录和文件
# 这样各种 MCP 工具都可以在其中创建配置、缓存等
RUN chmod -R 777 /usr/local/share && \
    mkdir -p /var/cache && chmod 777 /var/cache && \
    mkdir -p /var/lib && chmod 777 /var/lib

# 创建 Chrome 符号链接指向 Chromium，兼容使用 channel: 'chrome' 的代码
RUN mkdir -p /opt/google/chrome && \
    ln -s /usr/local/share/playwright/chromium-*/chrome-linux/chrome /opt/google/chrome/chrome

# 安装uv包管理器到系统路径（所有用户可用）
# 使用 CARGO_HOME 和 UV_INSTALL_DIR 环境变量控制安装位置
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# 配置 pip 镜像源到系统级别（所有用户生效）
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        mkdir -p /etc/pip && \
        echo '[global]' > /etc/pip/pip.conf && \
        echo 'index-url = https://mirrors.aliyun.com/pypi/simple/' >> /etc/pip/pip.conf && \
        echo 'trusted-host = mirrors.aliyun.com' >> /etc/pip/pip.conf; \
    fi

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /workspace

# 默认启动 bash（不再直接启动 claude）
CMD ["bash"]
