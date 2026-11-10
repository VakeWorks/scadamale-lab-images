# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# 1arch-tools -- the 1ArchCodeMathsProveDog commands of ONE release, for a student's group repository, on any
# machine with Docker or Podman (macOS, Windows, Linux; amd64 and arm64, each built natively, no qemu).
# It installs them exactly as 1Arch's README "Install" does (git clone, then `stack build --copy-bins`): ias-check
# finds the other commands in its own folder and the release's files through $ONEARCH.
#
#   docker run --rm -v "$PWD":/work -w /work git.vake.works/ias/1arch-tools:<release> ias-check run
#
# No ENTRYPOINT: the command is whatever follows the image (ias-check, ias-template, ias-symbols, ...).
# Phase A only: no Lean and no TeX (`ias-check run --build` needs the fuller course image that follows).
#
# Build (the image's recipe gives ONEARCH_REF, the release commit):
#   docker build --build-arg ONEARCH_REF=<full 40-character 1Arch commit> -t <ref> labs-images/1arch-tools
# The final stage copies the test stage's marker, so no image exists whose smoke test failed, on any architecture.

# Both bases are pinned by digest (multi-arch indexes with amd64 and arm64, read 2026-11-10), so a release builds the
# same way later: a floating tag rebuilt on another Debian would give the runtime another glibc.
# ---- 1. build: the release's engines, exactly as 1Arch's README installs them ----
FROM docker.io/library/haskell:9.6.6-bullseye@sha256:33e280e96a347f31cb9eb595c9e2ff134fc42d5175a50a9d958194d711402876 AS build
ARG ONEARCH_REPO=https://git.vake.works/ias/1archcodemathsprovedog.git
ARG ONEARCH_REF
RUN test -n "$ONEARCH_REF" || { echo "ONEARCH_REF (the full 1Arch commit) is required" >&2; exit 1; }
# haskell:9.6.6 (GHC 9.6.6 + stack, for lts-22.43) is Debian bullseye, whose security archive no longer serves the
# packages its index names: install from bullseye main only
RUN printf 'deb http://deb.debian.org/debian bullseye main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone "$ONEARCH_REPO" /src/1arch \
 && git -C /src/1arch checkout -q --detach "$ONEARCH_REF" \
 && test "$(git -C /src/1arch rev-parse HEAD)" = "$ONEARCH_REF"
# `git archive` (below) silently drops export-ignore files, rewrites export-subst ones and leaves LFS files as pointer
# stubs: refuse a release whose .gitattributes asks for any of them
RUN if find /src/1arch -name .gitattributes -not -path '*/.git/*' | xargs -r grep -lE 'export-ignore|export-subst|filter=lfs' | grep -q .; then \
      echo "1Arch's .gitattributes would make git archive drop, rewrite or stub files" >&2; exit 1; fi
WORKDIR /src/1arch
RUN stack build --system-ghc --no-install-ghc --copy-bins --local-bin-path /out/bin
# the 1Arch assets ($ONEARCH: templates, codebooks, symbols, the seal) as the release has them, without .git
RUN mkdir -p /out/1arch \
 && git -C /src/1arch archive --format=tar HEAD | tar -x -C /out/1arch \
 && printf '%s\n' "$ONEARCH_REF" > /out/1arch/ONEARCH_COMMIT

# ---- 2. runtime: the same Debian as the build (one glibc), the engines, git ----
FROM docker.io/library/debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd AS runtime
RUN printf 'deb http://deb.debian.org/debian bullseye main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates libgmp10 libffi7 libnuma1 zlib1g \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*'
# safe.directory: the student's repository is mounted from the host and owned by another uid than the container's
COPY --from=build /out/bin/ /usr/local/bin/
COPY --from=build /out/1arch/ /opt/1arch/
ENV ONEARCH=/opt/1arch
WORKDIR /work

# ---- 3. test: E2E-FRESH and its canary, on this architecture, inside this image ----
FROM runtime AS test
COPY smoke-test.sh /usr/local/share/1arch-tools/smoke-test.sh
RUN sh /usr/local/share/1arch-tools/smoke-test.sh

# ---- 4. the image: the runtime, carrying the test's marker ----
FROM runtime
ARG ONEARCH_REF
COPY smoke-test.sh /usr/local/share/1arch-tools/smoke-test.sh
COPY --from=test /usr/local/share/1arch-tools/smoke-ok /usr/local/share/1arch-tools/smoke-ok
LABEL org.opencontainers.image.title="1arch-tools" \
      org.opencontainers.image.description="The 1ArchCodeMathsProveDog commands of one release (ias-check, ias-template, ...), phase A" \
      org.opencontainers.image.source="https://git.vake.works/ias/1archcodemathsprovedog" \
      org.opencontainers.image.revision="${ONEARCH_REF}" \
      org.opencontainers.image.vendor="VakeWorks AB" \
      org.opencontainers.image.licenses="Apache-2.0"
CMD ["ias-check"]
