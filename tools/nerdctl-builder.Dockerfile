FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless ca-certificates curl git gh unzip zstd xz-utils perl python3 \
        build-essential pkg-config \
        docker.io iptables iproute2 \
    && rm -rf /var/lib/apt/lists/*

ARG RUSTUP_VERSION=1.28.2
ARG RUSTUP_INIT_SHA256=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c
RUN curl -fsSL --proto '=https' --tlsv1.2 -o /usr/local/bin/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
    && echo "${RUSTUP_INIT_SHA256}  /usr/local/bin/rustup-init" | sha256sum -c - \
    && chmod +x /usr/local/bin/rustup-init

ARG CMDLINE_TOOLS=11076708
ARG CMDLINE_TOOLS_SHA256=2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
ARG NDK_VERSION=27.3.13750724
ARG BUILD_TOOLS=34.0.0
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL --proto '=https' --tlsv1.2 -o /tmp/cmdline.zip "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
    && echo "${CMDLINE_TOOLS_SHA256}  /tmp/cmdline.zip" | sha256sum -c - \
    && unzip -q /tmp/cmdline.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/cmdline.zip \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null \
    && "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" \
        "platform-tools" "platforms;android-34" "build-tools;${BUILD_TOOLS}" "ndk;${NDK_VERSION}" \
    && chmod -R a+rwX "${ANDROID_HOME}"

# The cross-compile steps of build_local.sh start containers; the daemon runs inside this image.
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

RUN git config --system --add safe.directory '*'
WORKDIR /src
