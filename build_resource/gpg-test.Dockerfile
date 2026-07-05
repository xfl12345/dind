### 定义构建产出的底包
ARG BASE_IMAGE_TAG=lscr.io/linuxserver/baseimage-ubuntu:noble
### 标记底包为 origin 用以提取发行版信息
FROM $BASE_IMAGE_TAG AS origin

### docs URL=https://learn.microsoft.com/en-us/linux/packages#microsoftasc
FROM scratch AS gpg-builder-microsoft
ADD https://packages.microsoft.com/keys/microsoft.asc /root/apt/keys/microsoft.asc

### docs URL=https://vscodium.com/#install-on-debian-ubuntu-deb-package
FROM scratch AS gpg-builder-vscodium
ADD https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg /root/apt/keys/vscodium.asc

### docs URL=https://antigravity.google/download/linux
FROM scratch AS gpg-builder-antigravity
ADD https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg /root/apt/keys/google-antigravity.asc

### docs URL=https://www.google.com/linuxrepositories/
FROM scratch AS gpg-builder-google
ADD https://dl.google.com/linux/linux_signing_key.pub /root/apt/keys/google.asc

### docs URL=https://brave.com/linux/#debian-ubuntu-mint
FROM scratch AS gpg-builder-brave-browser-archive
ADD https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg /root/apt/keys/brave-browser-archive.asc

### docs URL=https://dbeaver.io/download/
FROM scratch AS gpg-builder-dbeaver
ADD https://dbeaver.io/debs/dbeaver.gpg.key /root/apt/keys/dbeaver.asc

### docs URL=https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
FROM scratch AS gpg-builder-docker
ADD https://download.docker.com/linux/ubuntu/gpg /root/apt/keys/docker.asc

### docs URL=https://www.nushell.sh/book/installation.html#package-managers
FROM scratch AS gpg-builder-nushell
ADD https://apt.fury.io/nushell/gpg.key /root/apt/keys/fury-nushell.asc

### 构建 alpine 通用工具镜像为 tools-builder
FROM alpine:latest AS tools-builder
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
RUN apk add bash gettext wget gpg curl jq
SHELL ["/bin/bash", "-c"]
USER root
RUN mkdir -p /usr/share/keyrings

### 汇聚 gpg 文件
FROM tools-builder AS gpg-builder
COPY --from=gpg-builder-microsoft /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-vscodium /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-antigravity /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-google /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-brave-browser-archive /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-dbeaver /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-docker /root/apt/keys/* /root/apt/keys/
COPY --from=gpg-builder-nushell /root/apt/keys/* /root/apt/keys/
RUN for file_path in /root/apt/keys/*.asc; do \
        name=$(basename "$file_path" .asc); \
        gpg --dearmor < "${file_path}" -o "/usr/share/keyrings/${name}.gpg"; \
    done

### 用 gettext envsubst 渲染 APT 源模板
FROM tools-builder AS apt-builder
COPY moved_root/etc/apt/sources.list.d/*.sources.template /tmp/docker/build/apt/
COPY moved_root/etc/apt/sources.list.d/*.sources /tmp/docker/build/apt/
COPY --from=origin /etc/lsb-release /tmp/lab/etc/lsb-release
RUN <<EOF
    set -a
    source /tmp/lab/etc/lsb-release
    set +a
    export DPKG_ARCH_IS_AMD64="$([ "$(arch)" = "x86_64" ] && echo yes || echo no)"
    export DPKG_ARCH_IS_OTHERS="$([ "${DPKG_ARCH_IS_AMD64}" = "yes" ] && echo no || echo yes)"
    export
    for i in $(find /tmp/docker/build/apt -name "*.template"); do
        echo "Processing ${i} ...";
        envsubst < "$i" > "$(echo "$i" | sed 's/\.template$//')"
    done
EOF

### 构建产出镜像
FROM $BASE_IMAGE_TAG
SHELL ["/bin/bash", "-c"]
COPY --from=apt-builder --chown=root:root --chmod=755 /tmp/docker/build/apt/*.sources /etc/apt/sources.list.d/
COPY --from=gpg-builder /usr/share/keyrings/* /usr/share/keyrings/
RUN echo '# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources' > /etc/apt/sources.list
RUN apt update
