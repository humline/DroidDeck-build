#!/usr/bin/env bash
# Builds the APK entirely inside a nerdctl container (JDK, Android SDK/NDK, Gradle, Rust)
# and copies it to the repository root as droiddeck-<variant>.apk.
#
# Usage: tools/build_nerdctl.sh [debug|release]      (default: release)
# Env:   NERDCTL            nerdctl command, e.g. "sudo nerdctl" (default: nerdctl)
#        DROIDDECK_GH_TOKEN GitHub token for `gh release download` (falls back to GH_TOKEN,
#                           GITHUB_TOKEN, then `gh auth token` on the host)
#        DROIDDECK_*        forwarded to tools/build_local.sh (e.g. DROIDDECK_SKIP_RUST=1)
#
# The builder image carries the whole toolchain plus its own Docker daemon, which runs the
# cross-compile containers that build_local.sh starts. It needs --privileged for that daemon, but
# no host sockets are mounted. Gradle/Cargo caches and the daemon's images live in named volumes.
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
variant=${1:-${DROIDDECK_BUILD_VARIANT:-release}}
case "${variant}" in debug | release) ;; *) echo "variant must be debug or release" >&2; exit 1 ;; esac

read -r -a nerdctl <<<"${NERDCTL:-nerdctl}"
command -v "${nerdctl[0]}" >/dev/null || { echo "nerdctl not found; set NERDCTL." >&2; exit 1; }
"${nerdctl[@]}" info >/dev/null 2>&1 || { echo "nerdctl cannot reach containerd (rootful access required, try NERDCTL='sudo nerdctl')." >&2; exit 1; }

image=${DROIDDECK_NERDCTL_BUILDER_IMAGE:-droiddeck-nerdctl-builder:3}
if ! "${nerdctl[@]}" image inspect "${image}" >/dev/null 2>&1; then
    "${nerdctl[@]}" build --platform linux/amd64 -t "${image}" \
        -f "${repo_root}/tools/nerdctl-builder.Dockerfile" "${repo_root}/tools"
fi


gh_token=${DROIDDECK_GH_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}
if [[ -z "${gh_token}" ]] && command -v gh >/dev/null; then gh_token=$(gh auth token 2>/dev/null || true); fi
# An env file keeps the token out of the process list and the container's command line.
env_file=$(mktemp)
chmod 600 "${env_file}"
printf 'GH_TOKEN=%s\n' "${gh_token}" >"${env_file}"
env | grep -E '^DROIDDECK_' | grep -v '^DROIDDECK_GH_TOKEN=' >>"${env_file}" || true
host_uid=$(id -u)
host_gid=$(id -g)
name=droiddeck-build-$$
cleanup() { rm -f "${env_file}"; "${nerdctl[@]}" rm -f "${name}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

inner='
set -euo pipefail
dockerd >/var/log/dockerd.log 2>&1 &
dockerd_pid=$!
for _ in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker info >/dev/null 2>&1 || { cat /var/log/dockerd.log >&2; echo "inner dockerd failed to start" >&2; exit 1; }
export PATH="$HOME/.cargo/bin:$PATH"
if [[ "${DROIDDECK_SKIP_RUST:-0}" != 1 ]] && ! command -v rustup >/dev/null; then
    rustup-init -y --profile minimal --default-toolchain stable
fi
finish() {
    code=$?
    chown -R "${HOST_UID}:${HOST_GID}" /src 2>/dev/null || true
    kill "${dockerd_pid}" 2>/dev/null || true
    exit "${code}"
}
trap finish EXIT
tools/build_local.sh
mkdir -p /out
cp "app/build/outputs/apk/${VARIANT}/app-${VARIANT}.apk" "/out/droiddeck-${VARIANT}.apk"
'

"${nerdctl[@]}" run --name "${name}" --platform linux/amd64 --privileged --user 0:0 \
    -v "${repo_root}:/src" -w /src \
    -v droiddeck-docker:/var/lib/docker -v droiddeck-home:/cache \
    -e HOME=/cache/home -e DROIDDECK_BUILD_CACHE=/cache/home/.cache/droiddeck-build \
    -e DROIDDECK_BUILD_VARIANT="${variant}" -e VARIANT="${variant}" \
    -e HOST_UID="${host_uid}" -e HOST_GID="${host_gid}" \
    --env-file "${env_file}" \
    "${image}" bash -c "${inner}"

"${nerdctl[@]}" cp "${name}:/out/droiddeck-${variant}.apk" "${repo_root}/droiddeck-${variant}.apk"
apk_out="${repo_root}/droiddeck-${variant}.apk"
chown "${host_uid}:${host_gid}" "${apk_out}" 2>/dev/null || sudo chown "${host_uid}:${host_gid}" "${apk_out}" 2>/dev/null || true
echo "APK: ${repo_root}/droiddeck-${variant}.apk"
