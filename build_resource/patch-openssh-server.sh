#!/bin/bash
# patch-openssh-server.sh
# 将 linuxserver/docker-openssh-server 的 s6-overlay 文件适配到 Ubuntu 环境中
# 在 Dockerfile 中作为 RUN 脚本调用

set -euo pipefail

S6_SRC="/tmp/openssh-server-root/etc/s6-overlay/s6-rc.d"
S6_DST="/etc/s6-overlay/s6-rc.d"

# ── 1. 复制 LSIO 的 s6-overlay 服务定义 ──

# init-openssh-server-config (oneshot)
cp -a "${S6_SRC}/init-openssh-server-config" "${S6_DST}/"

# svc-openssh-server (longrun)
cp -a "${S6_SRC}/svc-openssh-server" "${S6_DST}/"

# log-openssh-server (longrun)
cp -a "${S6_SRC}/log-openssh-server" "${S6_DST}/"

# ── 2. 注册到 user bundle ──
touch "${S6_DST}/user/contents.d/init-openssh-server-config"
touch "${S6_DST}/user/contents.d/svc-openssh-server"
touch "${S6_DST}/user/contents.d/log-openssh-server"

# ── 3. 修补依赖链：Alpine baseimage 用 init-config → init-config-end，Ubuntu baseimage 用 init-services ──

# init-openssh-server-config: 依赖 init-config → 改为依赖 init-services
rm -f "${S6_DST}/init-openssh-server-config/dependencies.d/init-config"
touch "${S6_DST}/init-openssh-server-config/dependencies.d/init-services"

# init-config-end 的依赖钩子：LSIO 原版在这里放了一个空文件让 init-config-end 等 init-openssh-server-config
# baseimage-ubuntu 里 init-config-end 也有自己的依赖，不需要我们处理
# 所以跳过 init-config-end/dependencies.d 的复制

# ── 4. 修补 svc-openssh-server/run：Alpine sshd.pam → Ubuntu sshd，去掉 s6-setuidgid ──
# Ubuntu sshd 必须以 root 启动（需要创建 PTY、PAM 认证、切换用户上下文）
# Alpine 的 sshd.pam 可以以非 root 运行，但 Ubuntu 的不行
sed -i 's|/usr/sbin/sshd\.pam|/usr/sbin/sshd|g' "${S6_DST}/svc-openssh-server/run"
sed -i 's|s6-setuidgid "${USER_NAME}" ||g' "${S6_DST}/svc-openssh-server/run"

# ── 5. 全局替换用户名：linuxserver.io → abc（webtop/ubuntu 都用 abc）──
# 覆盖 init / svc / log 所有脚本
find "${S6_DST}/init-openssh-server-config" "${S6_DST}/svc-openssh-server" "${S6_DST}/log-openssh-server" \
    -type f -exec sed -i 's/linuxserver\.io/abc/g' {} +

# ── 6. 端口：默认 2222 → 22 ──
# 包括 init 脚本里的硬编码回退值和 svc 的变量默认值
sed -i 's/LISTEN_PORT:-2222/LISTEN_PORT:-22/g' "${S6_DST}/init-openssh-server-config/run"
sed -i 's/LISTEN_PORT:-2222/LISTEN_PORT:-22/g' "${S6_DST}/svc-openssh-server/run"
sed -i 's/Port 2222/Port 22/g' "${S6_DST}/init-openssh-server-config/run"

# ── 7. Ubuntu sshd 需要 privilege separation 目录，Alpine 不需要 ──
sed -i '/^    \/run\/sshd$/d' "${S6_DST}/init-openssh-server-config/run"
sed -i '/# create folders/a mkdir -p /run/sshd' "${S6_DST}/init-openssh-server-config/run"

# ── 8. abc 用户 shell：baseimage 默认 /bin/false，SSH 登录需要真正的 shell ──
sed -i '/^# permissions/i chsh -s /bin/bash abc' "${S6_DST}/init-openssh-server-config/run"

# ── 9. 删除构建时 apt 自动生成的 host key ──
rm -f /etc/ssh/ssh_host_*

echo "[patch-openssh-server] Done."
