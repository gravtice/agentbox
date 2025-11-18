# gbox 容器资源配置指南

## 概述

gbox 支持通过**环境变量**和**命令行参数**两种方式配置容器资源限制,包括内存、CPU、端口等。

## 配置方式

### 1. 环境变量（全局默认值）

通过环境变量设置默认的资源配置:

```bash
export GBOX_MEMORY=8g                        # 容器内存限制（默认: 4g）
export GBOX_CPU=4                            # 容器 CPU 核心数（默认: 2）
export GBOX_PORTS="8000:8000;7000:7001"      # 端口映射配置（默认: 不映射任何端口）
export GBOX_KEEP=true                        # 退出后保留容器（默认: false）
export GBOX_NAME=my-container                # 自定义容器名（默认: 自动生成）
export GBOX_PROXY="http://127.0.0.1:7890"    # Agent 网络代理（默认: 不使用代理）

gbox claude                                  # 使用环境变量中的配置
```

### 2. 命令行参数（临时覆盖）

通过命令行参数临时覆盖配置:

```bash
# 完整参数形式
gbox claude --memory 8g --cpu 4 -- --model sonnet
gbox happy claude --memory 16g --cpu 8 -- --resume <session-id>

# 短参数形式
gbox claude -m 8g -c 4 -- --model sonnet
gbox happy claude -m 16g -c 8 -- --resume <session-id>
```

### 3. 优先级

配置优先级从高到低:

1. **命令行参数** (最高优先级)
2. **环境变量**
3. **默认值** (最低优先级)

示例:

```bash
# 环境变量设置为 4g
export GBOX_MEMORY=4g

# 命令行参数设置为 16g,将覆盖环境变量
gbox claude --memory 16g

# 最终容器将使用 16g 内存
```

## 可用参数

| 参数           | 短参数 | 环境变量       | 默认值                  | 说明                                    |
| -------------- | ------ | -------------- | ----------------------- | --------------------------------------- |
| `--memory`     | `-m`   | `GBOX_MEMORY`  | `4g`                    | 容器内存限制                            |
| `--cpu`        | `-c`   | `GBOX_CPU`     | `2`                     | 容器 CPU 核心数                         |
| `--ports`      | 无     | `GBOX_PORTS`   | 无（不映射任何端口）    | 端口映射（格式: "8000:8000;7000:7001"）|
| `--keep`       | 无     | `GBOX_KEEP`    | `false`                 | 退出后保留容器                          |
| `--name`       | 无     | `GBOX_NAME`    | 自动生成                | 自定义容器名                            |
| `--proxy`      | 无     | `GBOX_PROXY`   | 无（不使用代理）        | Agent 运行时使用的 HTTP/SOCKS 代理地址 |

## 使用示例

### 示例 1: 使用默认配置

```bash
gbox claude
# 内存: 4g, CPU: 2核
```

### 示例 2: 通过环境变量配置

```bash
export GBOX_MEMORY=8g
export GBOX_CPU=4
gbox claude
# 内存: 8g, CPU: 4核
```

### 示例 3: 通过命令行参数配置

```bash
gbox claude --memory 16g --cpu 8
# 内存: 16g, CPU: 8核
```

### 示例 4: 混合使用（命令行优先）

```bash
export GBOX_MEMORY=4g
export GBOX_CPU=2

gbox claude --memory 16g
# 内存: 16g (命令行覆盖), CPU: 2核 (环境变量)
```

### 示例 5: 完整参数示例

```bash
gbox claude \
  --memory 16g \
  --cpu 8 \
  --ports "9000:8000;5432:5432" \
  --keep \
  --name my-claude-project \
  -- --model sonnet
# 内存: 16g
# CPU: 8核
# 端口映射: 宿主机 9000->容器 8000, 宿主机 5432->容器 5432
# 退出后保留容器
# 容器名: my-claude-project
# 传递给 claude: --model sonnet
```

### 示例 6: happy 模式

```bash
gbox happy claude -m 32g -c 16 -- --resume <session-id>
# 内存: 32g
# CPU: 16核
# 运行模式: local-remote (happy)
# 传递给 claude: --resume <session-id>
```

## 参数分隔符 `--`

`--` 用于分隔 gbox 参数和 agent 参数:

```bash
gbox claude --memory 8g -- --model sonnet
             ^^^^^^^^^ gbox参数
                         ^^^^^^^^^^^^^ agent参数
```

- **gbox 参数** (在 `--` 之前): 控制容器资源
- **agent 参数** (在 `--` 之后): 传递给 AI agent (如 claude)

## 端口映射配置

### 格式说明

`GBOX_PORTS` 环境变量或 `--ports` 参数使用以下格式:

```bash
"host_port:container_port"              # 单个端口
"host_port1:container_port1;host_port2:container_port2"  # 多个端口（分号分隔）
```

### 示例

```bash
# 示例 1: 单个端口映射
GBOX_PORTS="8000:8000" gbox claude

# 示例 2: 多个端口映射
GBOX_PORTS="8000:8000;7000:7001;5432:5432" gbox claude

# 示例 3: 不同的宿主机和容器端口
GBOX_PORTS="8080:8000" gbox claude     # 宿主机 8080 访问容器 8000
```

### 安全说明

- 所有端口映射仅绑定到 `127.0.0.1`（本地回环地址）
- 外部网络无法直接访问容器端口
- 默认不映射任何端口，需要时通过 `GBOX_PORTS` 显式配置

## 代理配置

当宿主机需要通过代理访问外网时,可以把代理地址传递给 `gbox <agent>` 和 `gbox happy <agent>`。

### 使用环境变量

```bash
export GBOX_PROXY="http://127.0.0.1:7890"
gbox claude
```

### 使用命令行参数

```bash
gbox claude --proxy http://127.0.0.1:7890
gbox happy claude --proxy socks5://127.0.0.1:1080
```

### 说明

- `GBOX_PROXY`/`--proxy` 会同步到 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 及对应的小写变量,大部分 CLI/SDK 均可识别
- 代理仅在运行 Agent (`gbox <agent>` / `gbox happy <agent>`) 时注入,不会影响 `gbox list`、`gbox logs` 等其他子命令
- 代理地址需要包含协议前缀,如 `http://`、`https://` 或 `socks5://`

## 注意事项

1. **内存格式**: 使用 Docker 支持的格式 (如 `4g`, `8g`, `512m`)
2. **CPU 数值**: 整数或小数 (如 `2`, `4`, `0.5`)
3. **端口映射**: 使用 `GBOX_PORTS` 环境变量或 `--ports` 参数，格式为 `"host:container;host:container"`
4. **容器名**: 必须符合 Docker 命名规范 (字母、数字、下划线、点、连字符)

## 验证配置

查看容器实际使用的资源:

```bash
# 查看容器状态
gbox status

# 查看容器详细信息
docker inspect <容器名> | jq '.[0].HostConfig | {Memory, NanoCpus}'
```

## 故障排查

### 问题 1: 参数未生效

检查参数是否在 `--` 之前:

```bash
# ✗ 错误: 参数在 -- 之后
gbox claude -- --memory 8g

# ✓ 正确: 参数在 -- 之前
gbox claude --memory 8g --
```

### 问题 2: 环境变量未生效

检查环境变量名称是否正确:

```bash
# ✗ 错误: 没有 GBOX_ 前缀
export MEMORY=8g

# ✓ 正确: 有 GBOX_ 前缀
export GBOX_MEMORY=8g
```

### 问题 3: 命令行参数格式错误

检查参数格式:

```bash
# ✗ 错误: 缺少参数值
gbox claude --memory

# ✓ 正确: 提供参数值
gbox claude --memory 8g
```

## 相关文档

- [gbox 主文档](../README.md)
- [MCP 使用指南](MCP_GUIDE.md)
