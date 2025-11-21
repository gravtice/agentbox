# Copyright 2024-2025 Gravtice
# SPDX-License-Identifier: Apache-2.0
#
# Image Management Module
# Provides image existence checks, building, pulling, and pushing functions for reuse by other scripts.

# ============================================
# Image existence checks
# ============================================

function check_image_exists() {
    docker image inspect "$IMAGE_FULL" &>/dev/null
}

function ensure_image() {
    if ! check_image_exists; then
        echo -e "${RED}Error: container image does not exist${NC}"
        echo -e "${YELLOW}Image: $IMAGE_FULL${NC}"
        echo ""
        echo -e "${BLUE}Please build the image first:${NC}"
        echo -e "  ${GREEN}./gbox build${NC}"
        echo ""
        exit 1
    fi
}

# ============================================
# Image building
# ============================================

function build_image() {
    local no_cache=""
    local dockerfile="Dockerfile"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-cache)
                no_cache="--no-cache"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Use SCRIPT_DIR defined in the main gbox script (project root directory)
    local dockerfile_path="$SCRIPT_DIR/$dockerfile"

    # Check if Dockerfile exists
    if [ ! -f "$dockerfile_path" ]; then
        echo -e "${RED}Error: Dockerfile not found${NC}"
        echo -e "${YELLOW}Path: $dockerfile_path${NC}"
        echo ""
        echo -e "${BLUE}Note: ${NC}Building images requires the full source repository."
        echo -e "If you installed gbox via install.sh, please either:"
        echo ""
        echo -e "  1. ${GREEN}Pull the pre-built image (recommended):${NC}"
        echo -e "     gbox pull"
        echo ""
        echo -e "  2. ${GREEN}Build from the source directory:${NC}"
        echo -e "     cd /path/to/AgentBox"
        echo -e "     ./gbox build"
        echo ""
        exit 1
    fi

    # Detect timezone and decide whether to use domestic mirror source
    local use_china_mirror="false"
    local timezone=$(readlink /etc/localtime 2>/dev/null || echo "")

    if [[ "$timezone" =~ "Asia/Shanghai" ]] || [[ "$timezone" =~ "Asia/Chongqing" ]] || [[ "$timezone" =~ "Asia/Beijing" ]]; then
        use_china_mirror="true"
        echo -e "${BLUE}Detected China timezone, will use domestic mirror source to accelerate build${NC}"
    else
        echo -e "${BLUE}Using default mirror source${NC}"
    fi
    echo ""

    echo -e "${GREEN}Building container image v${VERSION}${NC}"
    echo -e "${YELLOW}Image name: $IMAGE_FULL${NC}"
    echo -e "${YELLOW}Dockerfile: $dockerfile_path${NC}"
    echo -e "${YELLOW}Use domestic mirror: $use_china_mirror${NC}"
    if [[ -n "$no_cache" ]]; then
        echo -e "${YELLOW}Cache: disabled (forcing rebuild)${NC}"
    else
        echo -e "${YELLOW}Cache: enabled${NC}"
    fi
    echo ""

    # Update git submodule (happy-cli)
    # Note: only update top-level submodule, non-recursive (happy-cli may have special configs like worktrees)
    echo -e "${BLUE}Updating happy-cli submodule...${NC}"
    ( cd "$SCRIPT_DIR" && git submodule update --init )

    # Display happy-cli version
    if [[ -d "$SCRIPT_DIR/vendor/happy-cli" ]]; then
        local happy_version=$(cd "$SCRIPT_DIR/vendor/happy-cli" && git describe --always --dirty 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ happy-cli version: ${happy_version}${NC}"
    fi
    echo ""

    # Switch to project root directory to execute docker build, ensure context is correct
    ( cd "$SCRIPT_DIR" && docker build \
        $no_cache \
        -f "$dockerfile" \
        --build-arg USE_CHINA_MIRROR="$use_china_mirror" \
        -t "$IMAGE_FULL" \
        -t "${IMAGE_NAME}:latest" \
        . )

    echo ""
    echo -e "${GREEN}✓ Image build completed${NC}"
    echo -e "  Version tag: ${BLUE}$IMAGE_FULL${NC}"
    echo -e "  Latest tag: ${BLUE}${IMAGE_NAME}:latest${NC}"
    echo ""
    echo -e "${YELLOW}Note: image contains Playwright browser, large size (~1.5GB)${NC}"
}

# ============================================
# Image pulling
# ============================================

function pull_image() {
    local tag="${1:-latest}"
    local remote_image="${IMAGE_NAME}:${tag}"

    echo -e "${GREEN}Pulling image from Docker Hub${NC}"
    echo -e "${YELLOW}Image: ${remote_image}${NC}"
    echo ""

    # Pull image
    if docker pull "${remote_image}"; then
        echo ""
        echo -e "${GREEN}✓ Image pulled successfully${NC}"

        # If latest tag, also tag it with version number
        if [[ "$tag" == "latest" ]]; then
            docker tag "${remote_image}" "${IMAGE_NAME}:${VERSION}"
            echo -e "${GREEN}✓ Tagged version: ${IMAGE_NAME}:${VERSION}${NC}"
        fi

        echo ""
        echo -e "${BLUE}Available image tags:${NC}"
        docker images "${IMAGE_NAME}" --format "  {{.Repository}}:{{.Tag}}" | head -5
    else
        echo ""
        echo -e "${RED}✗ Failed to pull image${NC}"
        echo -e "${YELLOW}Please check:${NC}"
        echo -e "  1. Network connection is normal"
        echo -e "  2. Image tag '${tag}' exists"
        echo -e "  3. Visit https://hub.docker.com/r/${IMAGE_NAME}/tags to see available tags"
        exit 1
    fi
}

# ============================================
# Image pushing
# ============================================

function push_image() {
    local tag="${1:-latest}"
    local image="${IMAGE_NAME}:${tag}"

    # Check if local image exists
    if ! docker image inspect "${image}" &>/dev/null; then
        echo -e "${RED}Error: local image does not exist: ${image}${NC}"
        echo -e "${YELLOW}Please build the image first:${NC}"
        echo -e "  ${GREEN}gbox build${NC}"
        exit 1
    fi

    echo -e "${GREEN}Pushing image to Docker Hub${NC}"
    echo -e "${YELLOW}Image: ${image}${NC}"
    echo ""

    # Check if already logged into Docker Hub
    if ! docker info 2>/dev/null | grep -q "Username:"; then
        echo -e "${YELLOW}Need to login to Docker Hub${NC}"
        echo -e "${BLUE}Please run: ${GREEN}docker login${NC}"
        echo ""
        read -p "Login now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker login
        else
            echo -e "${YELLOW}Cancelled${NC}"
            exit 0
        fi
    fi

    # Push image
    echo -e "${YELLOW}Pushing image...${NC}"
    echo ""
    if docker push "${image}"; then
        echo ""
        echo -e "${GREEN}✓ Image pushed successfully${NC}"
        echo -e "${BLUE}Image address: ${image}${NC}"
        echo -e "${BLUE}Docker Hub: https://hub.docker.com/r/${IMAGE_NAME}/tags${NC}"

        # If latest or version tag, prompt to push the other one as well
        if [[ "$tag" == "latest" ]]; then
            echo ""
            echo -e "${YELLOW}Hint: also push version tag?${NC}"
            echo -e "  ${GREEN}gbox push ${VERSION}${NC}"
        elif [[ "$tag" == "${VERSION}" ]]; then
            echo ""
            echo -e "${YELLOW}Hint: also push latest tag?${NC}"
            echo -e "  ${GREEN}gbox push latest${NC}"
        fi
    else
        echo ""
        echo -e "${RED}✗ Failed to push image${NC}"
        echo -e "${YELLOW}Please check:${NC}"
        echo -e "  1. Have permission to push to ${IMAGE_NAME}"
        echo -e "  2. Network connection is normal"
        exit 1
    fi
}
