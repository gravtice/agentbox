# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0

# ============================================
# Stage 1: Build happy-cli
# ============================================
FROM node:20-slim AS happy-builder

# Copy happy-cli source code (from git submodule)
COPY vendor/happy-cli /build
WORKDIR /build

# Install dependencies, build, and package
# Clean up package-lock.json and node_modules to resolve rollup optional dependency issues
RUN rm -rf package-lock.json node_modules && \
    npm install && \
    npm run build && \
    npm pack

# ============================================
# Stage 2: Final runtime environment
# ============================================
FROM python:3.12-slim

# Gravtice AgentBox - AI Agent containerized runtime environment (full version)
# Includes heavy-weight MCP dependencies like Playwright

# Mirror source configuration parameter (automatically set by gbox script based on timezone)
ARG USE_CHINA_MIRROR=false

# Configure APT mirror source (use Aliyun mirror for China timezone)
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources; \
    fi

# Install system dependencies (including libraries commonly needed by MCP)
RUN apt-get update && apt-get install -y \
    # Basic development tools
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    # Text editors
    vim \
    nano \
    # File processing tools
    unzip \
    zip \
    jq \
    # System tools
    procps \
    less \
    htop \
    tree \
    lsof \
    # Compilation tools (required by some npm packages)
    build-essential \
    # Browser-related dependencies (needed by Playwright and other MCP tools)\
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

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Configure npm mirror source (use Taobao mirror for China timezone)
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        npm config set registry https://registry.npmmirror.com; \
    fi

# Install Claude Code CLI (install globally via npm)
RUN npm install -g @anthropic-ai/claude-code

# Install happy-coder from build stage (includes permission handling fixes)
# happy calls claude inside the container, all communication happens within the container
COPY --from=happy-builder /build/happy-coder-*.tgz /tmp/
RUN npm install -g /tmp/happy-coder-*.tgz && \
    rm /tmp/happy-coder-*.tgz

# Install OpenAI Codex CLI (coding assistant tool)
RUN npm install -g @openai/codex

# Install Google Gemini CLI (AI terminal assistant)
RUN npm install -g @google/gemini-cli

# Pre-install playwright and its browser dependencies
# This adds approximately 500MB to image size, but ensures playwright MCP works properly
# Configure Playwright download source (use npmmirror mirror for China timezone)
# Install browsers to system directory, accessible by all users
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        export PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright/; \
    fi && \
    npm install -g playwright@1.48.0 && \
    npx playwright install chromium && \
    chmod -R 777 /usr/local/share/playwright
# Note: Skip install-deps because all necessary system dependencies are already installed in the apt-get step above

# Set shared directory permissions, allow all users to create subdirectories and files
# This way various MCP tools can create configurations, caches, etc. within them
RUN chmod -R 777 /usr/local/share && \
    mkdir -p /var/cache && chmod 777 /var/cache && \
    mkdir -p /var/lib && chmod 777 /var/lib

# Create Chrome symbolic link pointing to Chromium, for compatibility with code using channel: 'chrome'
RUN mkdir -p /opt/google/chrome && \
    ln -s /usr/local/share/playwright/chromium-*/chrome-linux/chrome /opt/google/chrome/chrome

# Install uv package manager to system path (available to all users)
# Use CARGO_HOME and UV_INSTALL_DIR environment variables to control installation location
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Configure pip mirror source at system level (effective for all users)
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        mkdir -p /etc/pip && \
        echo '[global]' > /etc/pip/pip.conf && \
        echo 'index-url = https://mirrors.aliyun.com/pypi/simple/' >> /etc/pip/pip.conf && \
        echo 'trusted-host = mirrors.aliyun.com' >> /etc/pip/pip.conf; \
    fi

# Set timezone
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /workspace

# Start bash by default (no longer start claude directly)
CMD ["bash"]
