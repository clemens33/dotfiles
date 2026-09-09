# OpenDesign 0.21.1 plus the Vela CLI that its sign-in action needs.
#
# Upstream's published image ships the daemon but never bundles the Vela CLI,
# so the web UI's "Sign in to OpenDesign" fails with
# `vela binary not found; install vela or configure VELA_BIN`
# (nexu-io/open-design issue #5700; Docker/Compose remains a partially
# supported target upstream). This is a thin local derivative of the immutable
# upstream image, not a source build: the base stays pinned by index digest and
# only glibc compatibility plus the exact Vela release that tag 0.21.1 pins for
# packaged desktop builds are added.
#
# Update and rollback are a pinned-base rebuild: change the FROM digest below,
# then `open-design build && open-design restart`. Both named volumes survive.
FROM ghcr.io/nexu-io/od@sha256:441daca881e699657bacf28e0c27b16cd6be551dfff4bd63368dd74bec581f39

# Package installation needs root; the final USER restores the upstream
# non-root runtime identity.
USER root

# The base image is Alpine (musl) and Vela 0.0.33 publishes no musl build — the
# platform packages declare os/cpu only, never `libc`. gcompat supplies the
# glibc loader and symbol shims. The `vela --version` check below is the proof
# that the glibc binary actually runs, because bin/vela.cjs execs it rather
# than answering the flag itself.
RUN apk add --no-cache gcompat

# Exact meta package pinned by OpenDesign tag 0.21.1. npm resolves exactly one
# optional platform package for the build architecture. Locked npm integrity
# values for the inputs this layer can pull:
#   @powerformer/vela-cli@0.0.33
#     sha512-ypqsOqRpj/DxO8WAvM89eeWJOsOMb+bRloZb4JNW3QTNX5TmDmA61H3wM9wX0vCd95JAmPg3mxJH6xrWnKVCcg==
#   @powerformer/vela-cli-linux-arm64@0.0.33
#     sha512-+DHifD5ylfjfsaWCo0NuPwl+D0lxkOs+apDCaxrj4EkSABkzjryrh2yIBncopZbz3GmDw+43AKNfTyDx6yr4fg==
#   @powerformer/vela-cli-linux-x64@0.0.33
#     sha512-uBAeeTUEUaLMe5DtO1RjfiH7egvljfUJoUEkGOqle2O83wX2zulXkQzDhh+br5EvKsZo9RtSHzCcsiRPaNeo/g==
RUN npm install -g --no-fund --no-audit @powerformer/vela-cli@0.0.33 \
    && rm -rf /root/.npm

# VELA_BIN must name the *native* binary, not npm's `bin/vela.cjs`, and gets a
# stable arch-independent path here so the ENV below stays correct on any
# architecture the base image publishes.
#
# Two reasons the wrapper is the wrong target. First, it runs the binary as a
# `spawnSync` child, so login is two processes; the daemon cancels a login by
# stopping the process tree of the pid it spawned, and its tree walk shells out
# to `ps -axo pid=,ppid=,command=`, which BusyBox rejects (`unrecognized
# option: x`) and the platform helper degrades to an empty snapshot. Cancelling
# therefore kills only the wrapper and orphans a `vela login` that keeps
# polling device authorization. Executing the binary directly makes the pid the
# daemon spawned the pid it must stop.
#
# Second, the daemon resolves the OpenCode companion at
# `dirname(VELA_BIN)/libexec/opencode/opencode` and only then falls back to
# PATH, which holds no `opencode` here. That companion ships beside the native
# binary, so it is exposed next to the stable path too — otherwise sign-in works
# but an AMR run cannot launch the known-good runtime of the selected release.
#
# `vela` itself stays on PATH as the npm wrapper for interactive use.
RUN set -eu; \
    native=$(node -e 'process.stdout.write(require("/usr/local/lib/node_modules/@powerformer/vela-cli/index.cjs").resolveVelaCliBin({ strict: true }))'); \
    ln -s "$native" /usr/local/bin/vela-bin; \
    ln -s "$(dirname "$native")/libexec" /usr/local/bin/libexec; \
    test -x /usr/local/bin/libexec/opencode/opencode

# Fail the build rather than ship an image whose sign-in still cannot run. Both
# entry points are checked: the PATH wrapper and the exact path VELA_BIN names.
RUN set -eu; \
    for entry in vela /usr/local/bin/vela-bin; do \
        installed=$("$entry" --version); \
        if [ "$installed" != 0.0.33 ]; then \
            printf '%s --version reported %s, expected 0.0.33\n' "$entry" "$installed" >&2; \
            exit 1; \
        fi; \
    done

# Vela keeps its device-login bearer state in $HOME — the daemon reports its
# config at /home/open-design/.amr/config.json — and the upstream image has no
# home directory for uid 1001 at all. Compose mounts the separate
# `open_design_vela_data` volume here, which inherits this mode and ownership
# on first use, so the login survives a restart while the root filesystem stays
# read-only. That volume is credential-bearing: do not copy or export it.
RUN install -d -m 0700 -o 1001 -g 1001 /home/open-design

ENV HOME=/home/open-design \
    VELA_BIN=/usr/local/bin/vela-bin

USER open-design
