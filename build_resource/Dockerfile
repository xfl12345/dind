# ============================================================
# 阶段1: 从底包提取发行版信息
# ============================================================
ARG BASE_IMAGE_TAG=lscr.io/linuxserver/baseimage-ubuntu:noble
FROM $BASE_IMAGE_TAG AS origin

# ============================================================
# 阶段2: alpine builder — 用 gettext envsubst 渲染 APT 源模板
# ============================================================
FROM alpine:latest AS apt-builder
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
RUN apk add bash gettext wget gpg curl
SHELL ["/bin/bash", "-c"]
USER root
COPY moved_root/etc/apt/sources.list.d/*.sources.template /tmp/docker/build/apt/
COPY moved_root/etc/apt/sources.list.d/*.sources /tmp/docker/build/apt/
COPY --from=origin /etc/lsb-release /tmp/lab/etc/lsb-release
RUN <<EOF
    set -a
    source /tmp/lab/etc/lsb-release
    set +a
    export DPKG_ARCH_IS_AMD64="$([ "$(arch)" = "x86_64" ] && echo yes || echo no)"
    export DPKG_ARCH_IS_OTHERS="$([ "$(arch)" = "x86_64" ] && echo no || echo yes)"
    export
    for i in $(find /tmp/docker/build/apt -name "*.template"); do
        echo "Processing ${i} ...";
        envsubst < "$i" > "$(echo "$i" | sed 's/\.template$//')"
    done
EOF

# ============================================================
# 阶段3: 最终镜像 — 基于 linuxserver/baseimage-ubuntu (自带 s6-overlay)
# ============================================================
ARG DEBIAN_FRONTEND=noninteractive
FROM $BASE_IMAGE_TAG
SHELL ["/bin/bash", "-c"]

# APT 源 + GPG 密钥
COPY --from=ubuntu-quick --chown=root:root --chmod=644 /moved_root/etc/profile.d/* /etc/profile.d/
COPY --from=apt-builder --chown=root:root --chmod=755 /tmp/docker/build/apt/*.sources /etc/apt/sources.list.d/
COPY moved_root/usr/share/keyrings/* /usr/share/keyrings/
RUN echo '# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources' > /etc/apt/sources.list

# 安装基础工具 + DinD 依赖 + SSH
RUN apt update
### 优先更新 apt 基础套件以优化安装性能
RUN apt install -y apt-file apt-utils apt-transport-https git curl wget openssl
### 优先修正 LINUX 字体问题
RUN apt install -y fonts-noto-mono fonts-noto-extra fonts-noto-cjk-extra fonts-unifont
### 安装 LINUX 常用基础套件
RUN apt install -y ubuntu-standard file tar zip unzip p7zip-full xz-utils bc
### 安装 LINUX 常用离线运维套件
RUN apt install -y sudo safe-rm tree screen kmod procps htop locales pigz xfsprogs btrfs-progs e2fsprogs qrencode
### 安装 LINUX 常用网络运维套件
RUN apt install -y iptables iproute2 nftables libcap2-bin netcat-openbsd resolvconf net-tools bind9-dnsutils wireguard-tools mtr openssh-server
### 安装 LINUX 常用开发包
RUN apt install -y build-essential
### 安装 LINUX 杂项
RUN apt install -y language-pack-zh-hans

### 安装 Docker 套件
RUN CONFLICTS=$(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1) && apt remove -y ${CONFLICTS:-runc}
RUN apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker dind 辅助脚本 (moby/moby)
ARG DIND_COMMIT=8d9e3502aba39127e4d12196dae16d306f76993d
RUN curl -fsSL "https://raw.githubusercontent.com/moby/moby/${DIND_COMMIT}/hack/dind" \
        -o /usr/local/bin/dind && chmod +x /usr/local/bin/dind

# coredns (WireGuard PEERDNS=auto 依赖，不在 Docker APT 仓库中)
ARG COREDNS_VERSION=1.14.3
RUN COREDNS_ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_${COREDNS_ARCH}.tgz" \
        | tar --extract --gzip --directory=/usr/local/bin/ --no-same-owner coredns && \
    coredns -version

# userns-remap + docker 组
RUN useradd -U dockremap && \
    usermod -G dockremap dockremap && \
    echo 'dockremap:165536:65536' >> /etc/subuid && \
    echo 'dockremap:165536:65536' >> /etc/subgid && \
    usermod -aG docker abc 2>/dev/null || true

# openssh-server: 从 LSIO docker-openssh-server 复制 s6 服务定义 + 打补丁适配 Ubuntu
COPY --from=openssh-server /root /tmp/openssh-server-root
COPY patch-openssh-server.sh /tmp/patch-openssh-server.sh
RUN bash /tmp/patch-openssh-server.sh && rm -f /tmp/patch-openssh-server.sh

# wireguard: 从 LSIO docker-wireguard 复制 s6 服务定义 + 默认模板 + 打补丁适配 Ubuntu
COPY --from=wireguard /root /tmp/wireguard-root
COPY patch-wireguard.sh /tmp/patch-wireguard.sh
RUN bash /tmp/patch-wireguard.sh && rm -f /tmp/patch-wireguard.sh

# WireGuard: symlink + kernel module autoload + wg-quick 补丁
RUN rm -rf /etc/wireguard && \
    ln -s /config/wg_confs /etc/wireguard && \
    echo 'wireguard' >> /etc/modules && \
    sed -i 's|\[\[ $proto == -4 \]\] && cmd sysctl -q net\.ipv4\.conf\.all\.src_valid_mark=1|[[ $proto == -4 ]] \&\& [[ $(sysctl -n net.ipv4.conf.all.src_valid_mark) != 1 ]] \&\& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1|' /usr/bin/wg-quick

# 自定义 s6 服务定义 (DinD + WireGuard)
COPY moved_root/etc/s6-overlay/s6-rc.d  /etc/s6-overlay/s6-rc.d

EXPOSE 22 2375 2376 51820/udp
VOLUME /var/lib/docker
