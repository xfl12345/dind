#!/bin/bash
# patch-wireguard.sh
# 将 linuxserver/docker-wireguard 的 s6-overlay 文件适配到 Ubuntu 环境中
# 在 Dockerfile 中作为 RUN 脚本调用

set -euo pipefail

S6_SRC="/tmp/wireguard-root/etc/s6-overlay/s6-rc.d"
S6_DST="/etc/s6-overlay/s6-rc.d"

# ── 1. 复制 LSIO 的 s6-overlay 服务定义 ──

# init-wireguard-module (oneshot)
cp -a "${S6_SRC}/init-wireguard-module" "${S6_DST}/"

# init-wireguard-confs (oneshot)
cp -a "${S6_SRC}/init-wireguard-confs" "${S6_DST}/"

# svc-wireguard (longrun)
cp -a "${S6_SRC}/svc-wireguard" "${S6_DST}/"

# svc-coredns (longrun)
cp -a "${S6_SRC}/svc-coredns" "${S6_DST}/"

# ── 2. 注册到 user bundle ──
touch "${S6_DST}/user/contents.d/init-wireguard-module"
touch "${S6_DST}/user/contents.d/init-wireguard-confs"
touch "${S6_DST}/user/contents.d/svc-wireguard"
touch "${S6_DST}/user/contents.d/svc-coredns"

# ── 3. 修补依赖链：Alpine baseimage 用 init-config，Ubuntu baseimage 用 init-services ──

# init-wireguard-module: 依赖 init-config → 改为依赖 init-services
rm -f "${S6_DST}/init-wireguard-module/dependencies.d/init-config"
touch "${S6_DST}/init-wireguard-module/dependencies.d/init-services"

# init-wireguard-confs: 依赖 init-wireguard-module（无需改动）

# svc-wireguard: 原版只依赖 svc-coredns，补上 init-services
touch "${S6_DST}/svc-wireguard/dependencies.d/init-services"

# svc-coredns: 依赖 init-services（原版已有，无需改动）

# ── 4. 复制默认配置模板 ──
mkdir -p /defaults
cp -a /tmp/wireguard-root/defaults/. /defaults/

echo "[patch-wireguard] Done."
