# DinD

基于 [LinuxServer.io baseimage-ubuntu][lsio-baseimage] ，对中文用户友好的 **Docker-in-Docker** 镜像，内置 Docker CE、OpenSSH Server，开箱即用。

[dind-script]: https://raw.githubusercontent.com/moby/moby/master/hack/dind
[lsio-ssh]: https://github.com/linuxserver/docker-openssh-server
[lsio-baseimage]: https://github.com/linuxserver/docker-baseimage-ubuntu
[lsio-baseimage-selkies]: https://github.com/linuxserver/docker-baseimage-selkies

## 功能概览

| 组件 | 说明 |
|------|------|
| Docker CE | 完整 Docker 引擎 + Buildx + Compose 插件 |
| OpenSSH Server | 适配自 [LSIO docker-openssh-server][lsio-ssh]，默认端口 22 |
| TLS 证书自动生成 | 设置 `DOCKER_TLS_CERTDIR` 后自签 CA + 服务端/客户端证书 |
| s6-overlay 服务编排 | init 阶段自动配置 docker 组、TLS、SSH |
| 多架构支持 | `linux/amd64` + `linux/arm64` |


## 快速开始

### 基本用法

```bash
curl -LO 'https://cdn.jsdelivr.net/gh/xfl12345/dind@main/docker-compose.yaml'
docker compose up -d --remove-orphans
```

启动后可用以下方式连接：

```bash
# SSH 登录（默认用户 abc）
ssh abc@localhost -p 22

# 通过 Docker socket 操作容器内 Docker
docker -H tcp://localhost:2375 ps
```

### 启用 Docker TLS

在 `.env` 或 compose override 中设置：

```env
DOCKER_TLS_CERTDIR=/certs
```

容器首次启动时会自动生成 CA 和证书。之后可通过安全端口连接：

```bash
docker --tlsverify \
  --tlscacert=ca.pem --tlscert=cert.pem --tlskey=key.pem \
  -H tcp://localhost:2376 ps
```

客户端证书位于 `${DOCKER_TLS_CERTDIR}/client/` 目录下（需挂载 volume 持久化）。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PUID` | `911` | 容器内用户 UID （与上游行为同步 [lsio-baseimage]） |
| `PGID` | `911` | 容器内用户 GID （与上游行为同步 [lsio-baseimage]） |
| `TZ` | `Asia/Shanghai` | 时区 |
| `START_DOCKER` | `true` | 是否自动启动 dockerd （与上游行为同步 [lsio-baseimage-selkies]） |
| `DOCKER_TLS_CERTDIR` | *(空)* | 设置后启用 Docker TLS 并自动生成证书 （与上游行为同步 [lsio-baseimage-selkies]） |

## 端口

| 端口 | 协议 | 用途 |
|------|------|------|
| 22 | TCP | OpenSSH Server |
| 2375 | TCP | Docker API（无加密） |
| 2376 | TCP | Docker API（TLS，需设置 `DOCKER_TLS_CERTDIR`） |

## 数据卷

| 容器路径 | 说明 |
|----------|------|
| `/var/lib/docker` | Docker 数据（镜像、容器、卷等） |
| `/config` | SSH 配置持久化目录 |
| `/dev/dri` | GPU 设备透传（可选） |
| `/lib/modules` | 宿主机内核模块（只读，DinD 需要） |

## 项目结构

```
.
├── .github/workflows/
│   └── build-and-release.yaml   # CI：tag push 触发多架构构建并发布到 GHCR
├── build_resource/
│   ├── Dockerfile               # 多阶段构建主文件
│   ├── gpg-test.Dockerfile      # GPG 密钥测试用 Dockerfile
│   ├── patch-openssh-server.sh  # 将 LSIO SSH 服务定义适配到 Ubuntu
│   ├── meta/
│   │   ├── apt-gpg-meta.json    # APT GPG 密钥元数据
│   │   └── apt-gpg-meta.schema.json
│   └── moved_root/              # 构建时 COPY 到镜像的文件
│       ├── etc/apt/sources.list.d/   # APT 源（含 .sources.template 模板）
│       └── etc/s6-overlay/s6-rc.d/   # s6 服务定义（dockerd）
├── docker-compose.yaml          # 开箱即用的 compose
├── docker-compose.build.yaml    # CI 用 compose override（覆盖镜像名、push、缓存）
└── volume/                      # 运行时数据卷挂载点
```

## 构建细节

### 多阶段构建

Dockerfile 采用多阶段构建，各阶段职责分明：

1. **`gpg-builder-*`**（`FROM scratch`）— 从各上游仓库下载 GPG 签名密钥
2. **`tools-builder`**（Alpine）— 通用工具层，安装 bash/gpg/envsubst 等
3. **`gpg-builder`** — 汇聚所有密钥并 `gpg --dearmor` 转为 `.gpg` 格式
4. **`apt-builder`** — 用 `envsubst` 渲染 APT 源模板（自动适配发行版代号和架构）
5. **最终镜像** — 集成 Docker CE、OpenSSH、基础工具、中文字体等

### Tag 规则

| Git Tag | 镜像 Tag |
|---------|----------|
| `v1.2.3` | `v1.2.3`、`v1.2`、`v1`、`sha-<full-sha>` |

## 运行要求

- **privileged 模式** — DinD 需要特权运行
- **shm_size ≥ 2GB** — 默认 8GB，避免构建大镜像时 OOM
- **NET_ADMIN + SYS_MODULE** — 网络管理能力（iptables、nftables）
- **net.ipv4.conf.all.src_valid_mark=1** — sysctl 设置，支持策略路由

## 许可证

[MIT](LICENSE)
