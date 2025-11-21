# Docker Image Optimization Guide

## Current Status (v1.0.7)

- **Current Size**: ~4.2 GB
- **Base Image**: python:3.12-slim
- **Major Components**:
  - Playwright + Chromium: ~500-800 MB
  - Node.js + Global Packages: ~300-500 MB
  - Python + System Dependencies: ~400-600 MB
  - Claude Code, Codex, Gemini CLI: ~200-400 MB

## Optimization Applied

### Phase 1: Cache Cleanup (Implemented)

**Changes**:
1. Added `npm cache clean --force` after each npm global install
2. Added `rm -rf /var/lib/apt/lists/*` after Node.js installation
3. Cleaned up temporary files after builds

**Expected Reduction**: 200-400 MB (5-10%)

### Phase 2: Layer Consolidation (Optional)

**Potential Changes**:
```dockerfile
# Consolidate all npm installs into one layer
RUN npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli \
    /tmp/happy-coder-*.tgz && \
    rm /tmp/happy-coder-*.tgz && \
    npm cache clean --force
```

**Expected Reduction**: 50-100 MB (layer overhead)

### Phase 3: Lite Version (Recommended)

**Create two variants**:

1. **Full Version** (current): With Playwright, all features
   - Size: ~3.8-4.0 GB (after Phase 1)
   - Use case: Complete AI agent environment

2. **Lite Version** (new): Without Playwright
   - Size: ~2.5-3.0 GB
   - Use case: Basic coding without browser automation

**Implementation**:
```dockerfile
# Add build argument
ARG INCLUDE_PLAYWRIGHT=true

# Conditional Playwright installation
RUN if [ "$INCLUDE_PLAYWRIGHT" = "true" ]; then \
        npm install -g playwright@1.48.0 && \
        npx playwright install chromium && \
        chmod -R 777 /usr/local/share/playwright && \
        npm cache clean --force; \
    fi
```

## Build Commands

### Full Version (Current)
```bash
./gbox build                    # ~4.2 GB → ~3.8 GB
docker tag gravtice/agentbox:1.0.7 gravtice/agentbox:1.0.7-full
```

### Lite Version (Without Playwright)
```bash
docker build --build-arg INCLUDE_PLAYWRIGHT=false \
    -t gravtice/agentbox:1.0.7-lite .
```

## Analysis Tools

### Using dive to inspect layers
```bash
# Install dive
brew install dive  # macOS
# or
docker pull wagoodman/dive

# Analyze image
dive gravtice/agentbox:1.0.7
```

### Using docker-slim (aggressive optimization)
```bash
# Install docker-slim
brew install docker-slim  # macOS

# Optimize image (may break some features)
docker-slim build gravtice/agentbox:1.0.7
```

## Size Breakdown (Estimated)

| Component | Size | Can Remove? |
|-----------|------|-------------|
| Base (python:3.12-slim) | ~150 MB | No |
| Node.js 20 | ~200 MB | No |
| System Dependencies | ~400 MB | Partially |
| Claude Code CLI | ~100 MB | No |
| Codex CLI | ~50 MB | Yes (lite) |
| Gemini CLI | ~50 MB | Yes (lite) |
| Happy Daemon | ~50 MB | No |
| Playwright + Chromium | ~700 MB | Yes (lite) |
| npm/pip caches | ~200 MB | **Yes** ✅ |
| Build artifacts | ~100 MB | Partially |

## Recommendations

### Immediate Actions (Done in Phase 1)
- ✅ Clean npm cache after each install
- ✅ Clean apt lists after updates
- ✅ Remove build artifacts

### Short-term (Optional)
- [ ] Consolidate npm installs
- [ ] Create lite variant without Playwright
- [ ] Use multi-stage builds for CLI tools

### Long-term (Breaking Changes)
- [ ] Switch to Alpine-based images (may break compatibility)
- [ ] Lazy-load Playwright on first use
- [ ] Separate Playwright into extension image

## Testing After Optimization

```bash
# Rebuild with optimizations
./gbox build

# Check new size
docker images | grep agentbox

# Verify functionality
./gbox claude
./gbox claude -- mcp list
./gbox happy claude
```

## Expected Results

| Phase | Size Reduction | Final Size | Effort |
|-------|----------------|------------|--------|
| Phase 1 (Cache) | -400 MB | ~3.8 GB | Low ✅ |
| Phase 2 (Layers) | -100 MB | ~3.7 GB | Medium |
| Phase 3 (Lite) | -1.2 GB | ~2.5 GB | Medium |
| All Phases | -1.5 GB | ~2.7 GB | High |

## Notes

- Aggressive optimization (docker-slim, Alpine) may break MCP servers
- Playwright is the largest optional component
- Consider user needs: full vs lite version
- Test thoroughly after each optimization phase
