# Image Management Module
# 提供镜像存在性检查、构建、拉取与推送等功能，供其他脚本复用。

# ============================================
# 镜像检查相关
# ============================================

function check_image_exists() {
    docker image inspect "$IMAGE_FULL" &>/dev/null
}

function ensure_image() {
    if ! check_image_exists; then
        echo -e "${RED}错误: 容器镜像不存在${NC}"
        echo -e "${YELLOW}镜像: $IMAGE_FULL${NC}"
        echo ""
        echo -e "${BLUE}请先构建镜像:${NC}"
        echo -e "  ${GREEN}./gbox build${NC}"
        echo ""
        exit 1
    fi
}

# ============================================
# 镜像构建
# ============================================

function build_image() {
    local dockerfile="Dockerfile"

    # 使用 gbox 主脚本定义的 SCRIPT_DIR（项目根目录）
    local dockerfile_path="$SCRIPT_DIR/$dockerfile"

    if [[ ! -f "$dockerfile_path" ]]; then
        echo -e "${RED}错误: $dockerfile_path 不存在${NC}"
        exit 1
    fi

    # 检测时区，决定是否使用国内镜像源
    local use_china_mirror="false"
    local timezone=$(readlink /etc/localtime 2>/dev/null || echo "")

    if [[ "$timezone" =~ "Asia/Shanghai" ]] || [[ "$timezone" =~ "Asia/Chongqing" ]] || [[ "$timezone" =~ "Asia/Beijing" ]]; then
        use_china_mirror="true"
        echo -e "${BLUE}检测到中国时区，将使用国内镜像源加速构建${NC}"
    else
        echo -e "${BLUE}使用默认镜像源${NC}"
    fi
    echo ""

    echo -e "${GREEN}构建容器镜像 v${VERSION}${NC}"
    echo -e "${YELLOW}镜像名称: $IMAGE_FULL${NC}"
    echo -e "${YELLOW}Dockerfile: $dockerfile_path${NC}"
    echo -e "${YELLOW}使用国内镜像: $use_china_mirror${NC}"
    echo ""

    # 更新 git 子模块（happy-cli）
    # 注意：只更新顶层 submodule，不递归（happy-cli 内部可能有 worktree 等特殊配置）
    echo -e "${BLUE}更新 happy-cli 子模块...${NC}"
    ( cd "$SCRIPT_DIR" && git submodule update --init )

    # 显示 happy-cli 版本
    if [[ -d "$SCRIPT_DIR/vendor/happy-cli" ]]; then
        local happy_version=$(cd "$SCRIPT_DIR/vendor/happy-cli" && git describe --always --dirty 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ happy-cli 版本: ${happy_version}${NC}"
    fi
    echo ""

    # 切换到项目根目录执行 docker build，确保 context 正确
    ( cd "$SCRIPT_DIR" && docker build \
        -f "$dockerfile" \
        --build-arg USE_CHINA_MIRROR="$use_china_mirror" \
        -t "$IMAGE_FULL" \
        -t "${IMAGE_NAME}:latest" \
        . )

    echo ""
    echo -e "${GREEN}✓ 镜像构建完成${NC}"
    echo -e "  版本标签: ${BLUE}$IMAGE_FULL${NC}"
    echo -e "  最新标签: ${BLUE}${IMAGE_NAME}:latest${NC}"
    echo ""
    echo -e "${YELLOW}注意: 镜像包含 Playwright 浏览器，体积较大（~1.5GB）${NC}"
}

# ============================================
# 镜像拉取
# ============================================

function pull_image() {
    local tag="${1:-latest}"
    local remote_image="${IMAGE_NAME}:${tag}"

    echo -e "${GREEN}从 Docker Hub 拉取镜像${NC}"
    echo -e "${YELLOW}镜像: ${remote_image}${NC}"
    echo ""

    # 拉取镜像
    if docker pull "${remote_image}"; then
        echo ""
        echo -e "${GREEN}✓ 镜像拉取成功${NC}"

        # 如果是 latest 标签，同时标记为版本号
        if [[ "$tag" == "latest" ]]; then
            docker tag "${remote_image}" "${IMAGE_NAME}:${VERSION}"
            echo -e "${GREEN}✓ 已标记版本: ${IMAGE_NAME}:${VERSION}${NC}"
        fi

        echo ""
        echo -e "${BLUE}可用镜像标签:${NC}"
        docker images "${IMAGE_NAME}" --format "  {{.Repository}}:{{.Tag}}" | head -5
    else
        echo ""
        echo -e "${RED}✗ 镜像拉取失败${NC}"
        echo -e "${YELLOW}请检查:${NC}"
        echo -e "  1. 网络连接是否正常"
        echo -e "  2. 镜像标签 '${tag}' 是否存在"
        echo -e "  3. 访问 https://hub.docker.com/r/${IMAGE_NAME}/tags 查看可用标签"
        exit 1
    fi
}

# ============================================
# 镜像推送
# ============================================

function push_image() {
    local tag="${1:-latest}"
    local image="${IMAGE_NAME}:${tag}"

    # 检查本地镜像是否存在
    if ! docker image inspect "${image}" &>/dev/null; then
        echo -e "${RED}错误: 本地镜像不存在: ${image}${NC}"
        echo -e "${YELLOW}请先构建镜像:${NC}"
        echo -e "  ${GREEN}gbox build${NC}"
        exit 1
    fi

    echo -e "${GREEN}推送镜像到 Docker Hub${NC}"
    echo -e "${YELLOW}镜像: ${image}${NC}"
    echo ""

    # 检查是否已登录 Docker Hub
    if ! docker info 2>/dev/null | grep -q "Username:"; then
        echo -e "${YELLOW}需要登录 Docker Hub${NC}"
        echo -e "${BLUE}请运行: ${GREEN}docker login${NC}"
        echo ""
        read -p "现在登录？(y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker login
        else
            echo -e "${YELLOW}已取消${NC}"
            exit 0
        fi
    fi

    # 推送镜像
    echo -e "${YELLOW}推送镜像...${NC}"
    echo ""
    if docker push "${image}"; then
        echo ""
        echo -e "${GREEN}✓ 镜像推送成功${NC}"
        echo -e "${BLUE}镜像地址: ${image}${NC}"
        echo -e "${BLUE}Docker Hub: https://hub.docker.com/r/${IMAGE_NAME}/tags${NC}"

        # 如果是 latest 或版本号标签，提示同时推送另一个
        if [[ "$tag" == "latest" ]]; then
            echo ""
            echo -e "${YELLOW}提示: 同时推送版本标签?${NC}"
            echo -e "  ${GREEN}gbox push ${VERSION}${NC}"
        elif [[ "$tag" == "${VERSION}" ]]; then
            echo ""
            echo -e "${YELLOW}提示: 同时推送 latest 标签?${NC}"
            echo -e "  ${GREEN}gbox push latest${NC}"
        fi
    else
        echo ""
        echo -e "${RED}✗ 镜像推送失败${NC}"
        echo -e "${YELLOW}请检查:${NC}"
        echo -e "  1. 是否有推送权限到 ${IMAGE_NAME}"
        echo -e "  2. 网络连接是否正常"
        exit 1
    fi
}
