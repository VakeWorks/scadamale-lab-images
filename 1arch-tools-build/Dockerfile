# syntax=docker/dockerfile:1
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# 1arch-tools:<release>-build -- the 1arch-tools image of ONE release, plus core Lean 4.32.0 (elan), TeX Live 2023
# (lualatex, latexmk, BibTeX) and the course's slide machinery without a browser (Node 22, Marp, 1arch-figure), so
# `ias-check run --build` runs in one container and a group's talk and its TikZ figures build the way the course's
# lecture slides do. The same image name the groups already use, a sibling tag: <release> stays the phase-A image as
# walked; <release>-build adds Lean, TeX and the slides.
#
#   docker run --rm -v "$PWD":/work -w /work docker.io/vakeworks/1arch-tools:<release>-build ias-check run --build
#   docker run --rm -v "$PWD":/work -w /work docker.io/vakeworks/1arch-tools:<release>-build \
#     marp --html --allow-local-files --theme slides/scadamale-marp-theme.css slides/talk.md
#
# No browser in the image (the op's ruling (e), 2026-11-20): marp makes the talk's HTML here (slides/talk.html), and
# the PDF is made on the student's own machine, where marp uses the installed Chrome, Edge or Firefox (README). A
# browser in a container also needs a sandbox the container does not give: the op's third local build (2026-11-20
# 23:20 CET) stopped with Chrome for Testing's "No usable sandbox!".
#
# One run line on every OS: the entrypoint runs the command as the owner of the mounted folder (entrypoint.sh).
# Built FROM the walked 1arch-tools image by digest (no engine rebuild, the same bullseye glibc), never FROM
# vakeworks/iasprovedog (Mathlib and internal certificates). No Mathlib: the group template is dependency-free.
#
# Build (the workflow gives both): TOOLS_IMAGE, the 1arch-tools image of the release carrying @sha256:, and
# ONEARCH_REF, that release's full commit (the test checks the tools image was built from it):
#   docker buildx build --build-arg TOOLS_IMAGE=docker.io/vakeworks/1arch-tools:<release>@sha256:<index> \
#     --build-arg ONEARCH_REF=<40 hex> -t <ref> .
# The final stage copies both tests' markers and the guard's record, so BuildKit (which builds only the stages the
# target needs) runs all three, and no image exists whose test failed, on any architecture.

ARG TOOLS_IMAGE
ARG ONEARCH_REF
ARG DEBIAN=docker.io/library/debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd

# ---- 0. guard: the tools image is named by digest, and the release by its full commit ----
FROM ${DEBIAN} AS guard
ARG TOOLS_IMAGE
ARG ONEARCH_REF
RUN d="${TOOLS_IMAGE##*@sha256:}"; \
    if [ "$d" = "$TOOLS_IMAGE" ] || [ "${#d}" -ne 64 ] || [ -n "$(printf '%s' "$d" | tr -d '0-9a-f')" ]; then \
      echo "TOOLS_IMAGE must name the 1arch-tools image by digest (<ref>@sha256:<64 hex>), got: '$TOOLS_IMAGE'" >&2; exit 1; fi; \
    if [ "${#ONEARCH_REF}" -ne 40 ] || [ -n "$(printf '%s' "$ONEARCH_REF" | tr -d '0-9a-f')" ]; then \
      echo "ONEARCH_REF must be the release's full 40-character commit, got: '$ONEARCH_REF'" >&2; exit 1; fi; \
    mkdir -p /guard && printf '%s\n%s\n' "$TOOLS_IMAGE" "$ONEARCH_REF" > /guard/tools-image

# ---- 1. lean: elan and the course's Lean, on the same bullseye as the tools image ----
FROM ${DEBIAN} AS lean
ARG TARGETARCH
# the same two apt sources as 1arch-tools (bullseye main from deb.debian.org, bullseye-security from the archive)
RUN printf 'deb http://deb.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends ca-certificates curl zstd \
 && rm -rf /var/lib/apt/lists/*
# elan v4.4.0 and Lean v4.32.0: each release asset pinned by the sha256 GitHub publishes for it (read 2026-11-20).
# elan installs the toolchain itself (explicitly: elan 4.4.0's elan-init --default-toolchain only SETS the default and
# installs nothing, so the first local build met "No such file or directory" at the diff; 2026-11-20); the pinned Lean
# asset is then unpacked beside it and must be byte-equal (diff -r),
# so the toolchain is the pinned bytes. Installed under EXACTLY the seed's lean-toolchain string (Ias.Check leanPin) and
# made elan's default. Root-owned, no group or world write: ias-check's probe (lean --print-prefix, its
# bin/lean and lib/lean) must find it read-only for a non-root uid.
ENV ELAN_HOME=/opt/elan
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) ea=x86_64;  es=0e8250aa2be86c7af929ade68db617af9edc8b9ccf6eaf5ece228250d0d032e2; \
             la=lean-4.32.0-linux;         ls=fca846f3588724a38ad19ee40292c67cb7438d7555903372e3308eef795ba516 ;; \
      arm64) ea=aarch64; es=45cde3006f82f98804c94cf2ca4949d117060a5f3cc8afa62f523759947ee21f; \
             la=lean-4.32.0-linux_aarch64; ls=e5eb67e5f30c14d57e70bf7ca2ad880b09a52d75da1cf5e2deabb2418a84c8d1 ;; \
      *) echo "no pins for TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -sSL -o /tmp/elan.tar.gz "https://github.com/leanprover/elan/releases/download/v4.4.0/elan-$ea-unknown-linux-gnu.tar.gz"; \
    echo "$es  /tmp/elan.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/elan.tar.gz -C /tmp; \
    /tmp/elan-init -y --no-modify-path --default-toolchain leanprover/lean4:v4.32.0; \
    /opt/elan/bin/elan toolchain install leanprover/lean4:v4.32.0; \
    ls /opt/elan/toolchains; \
    curl -sSL -o /tmp/lean.tar.zst "https://github.com/leanprover/lean4/releases/download/v4.32.0/$la.tar.zst"; \
    echo "$ls  /tmp/lean.tar.zst" | sha256sum -c -; \
    mkdir /tmp/lean; \
    tar --zstd -xf /tmp/lean.tar.zst -C /tmp/lean --strip-components=1; \
    diff -r /tmp/lean /opt/elan/toolchains/leanprover--lean4---v4.32.0; \
    rm -rf /tmp/elan-init /tmp/elan.tar.gz /tmp/lean /tmp/lean.tar.zst; \
    chown -R root:root /opt/elan; \
    chmod -R go-w /opt/elan

# ---- 2. tex: TeX Live 2023 from the frozen historic tlnet-final ----
# The same TeX Live YEAR as the maths image where the course papers build. Upstream x86_64-linux and
# aarch64-linux binaries run on bullseye's glibc 2.31. install-tl-20240312, its tarball pinned by sha256 (its sha512
# equals the archive's own .sha512, fetched 2026-11-20); install-tl checks every package against the tlpdb's
# checksums and, with gpg present, the tlpdb's signature.
FROM ${DEBIAN} AS tex
ARG TL_REPO=https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2023/tlnet-final
RUN printf 'deb http://deb.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends ca-certificates curl perl gnupg xz-utils \
 && rm -rf /var/lib/apt/lists/*
COPY texlive.profile /tmp/texlive.profile
# scheme-basic (collection-basic + collection-latex: amsmath, amscls, amsfonts, geometry, graphics, hyperref, tools,
# bibtex, luahbtex, lua-alt-getopt, ...) plus the packages that ship the rest of the kpsewhich list, each found in
# tlnet-final's texlive.tlpdb (sha512 2d308c40...68d09, as published) by the file it ships: booktabs cite cleveref
# isomath jknapltx (mathrsfs.sty) latexmk lm luaotfload mathtools microtype parskip pgf (tikz.sty). tlmgr follows
# their declared depends (luaotfload: lm lualibs lua-uni-algos; pgf: xcolor fp ms). Named for their undeclared
# \RequirePackage needs: etoolbox fixmath infwarerr rsfs xcolor. For 1arch-figure's page, the standalone class and
# what standalone.cls v1.3b loads under lualatex with its default crop (preview off): xkeyval, luatex85, pdftexcmds
# (tlmgr skips any already present). The compile tests (E2E-BUILD's paper-pdf, T1, the slides test's S4) decide.
# /opt/texlive/bin is filled the way TeX Live supports (tlmgr path add: one absolute link per binary), so each
# program finds its texmf.cnf from its real location and PATH needs no architecture name.
RUN set -eu; \
    curl -sSL -o /tmp/install-tl-unx.tar.gz "$TL_REPO/install-tl-unx.tar.gz"; \
    echo "29b0a67c31231b789cd45be15c02aadf76134942a7907a9ed12e0539ffc77537  /tmp/install-tl-unx.tar.gz" | sha256sum -c -; \
    mkdir /tmp/install-tl; \
    tar -xzf /tmp/install-tl-unx.tar.gz -C /tmp/install-tl --strip-components=1; \
    /tmp/install-tl/install-tl --profile /tmp/texlive.profile --repository "$TL_REPO"; \
    tl="$(echo /opt/texlive/2023/bin/*-linux)"; \
    test -x "$tl/tlmgr"; \
    "$tl/tlmgr" --repository "$TL_REPO" install \
      booktabs cite cleveref etoolbox fixmath infwarerr isomath jknapltx latexmk lm luaotfload mathtools microtype \
      parskip pgf rsfs xcolor \
      standalone xkeyval luatex85 pdftexcmds; \
    mkdir -p /opt/texlive/bin; \
    "$tl/tlmgr" option sys_bin /opt/texlive/bin; \
    "$tl/tlmgr" path add; \
    test -x /opt/texlive/bin/lualatex; \
    PATH=/opt/texlive/bin:$PATH /opt/texlive/bin/luaotfload-tool --update; \
    rm -rf /tmp/install-tl /tmp/install-tl-unx.tar.gz /tmp/texlive.profile; \
    chown -R root:root /opt/texlive; \
    chmod -R go-w /opt/texlive
# luaotfload-tool is '#!/usr/bin/env texlua', so it runs with /opt/texlive/bin on PATH (without it the op's second
# local build, 2026-11-20 22:01, stopped at "/usr/bin/env: 'texlua': No such file or directory").
# luaotfload-tool runs BARE (no '|| true'), as root, so its names database lands in TEXMFSYSVAR, read-only at run
# time; the test shows a student's run finds it warm.

# ---- 3. node: Node.js 22 LTS and the slides' npm closure (Marp) ----
# The tarball for each architecture is pinned by the sha256 that nodejs.org's SHASUMS256.txt for v22.23.2 publishes
# (that file's own sha256 778ac5b2fcdbd68d9c0ae9f4310674faa3af0910bd0d18e7f6597787c40a3e39; read 2026-11-20).
# slides/package.json names @marp-team/marp-cli 4.5.0 exactly, and slides/package-lock.json pins its whole closure
# (156 packages from registry.npmjs.org, each with its integrity hash; none has an install script, and none is
# platform-specific): npm ci refuses any drift. No Mermaid (the op's ruling: the course's slides are Marp and TikZ).
FROM ${DEBIAN} AS node
ARG TARGETARCH
ARG NODE_VERSION=22.23.2
RUN printf 'deb http://deb.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) na=x64;   ns=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307 ;; \
      arm64) na=arm64; ns=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8 ;; \
      *) echo "no pins for TARGETARCH=$TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -sSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$na.tar.xz"; \
    echo "$ns  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    rm /tmp/node.tar.xz; \
    chown -R root:root /opt/node; \
    chmod -R go-w /opt/node
COPY slides/package.json slides/package-lock.json /opt/1arch-slides/
RUN set -eu; \
    echo "c509ea7ba243b8f9d225f23179be8af0a153106ad8a68f2aee381637f2332625  /opt/1arch-slides/package-lock.json" | sha256sum -c -; \
    cd /opt/1arch-slides; \
    PATH=/opt/node/bin:$PATH npm ci --omit=dev --ignore-scripts --no-audit --no-fund --cache /tmp/npm-cache; \
    rm -rf /tmp/npm-cache; \
    test -x /opt/1arch-slides/node_modules/.bin/marp; \
    chown -R root:root /opt/1arch-slides; \
    chmod -R go-w /opt/1arch-slides

# ---- 4. runtime: the walked tools image + Lean + TeX + the slide machinery + the entrypoint ----
FROM ${TOOLS_IMAGE} AS runtime
# latexmk and tlmgr are Perl, and the tools image carries only perl-base (its apt sources are already the two above).
# poppler-utils: pdftoppm for 1arch-figure. No browser and no browser fonts: marp makes HTML here, and the student's
# browser renders it with the student's fonts; 1arch-figure's PNG is rasterised from a PDF that carries its own fonts.
RUN apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends perl poppler-utils \
 && rm -rf /var/lib/apt/lists/*
COPY --from=lean /opt/elan /opt/elan
COPY --from=tex /opt/texlive /opt/texlive
COPY --from=node /opt/node /opt/node
COPY --from=node /opt/1arch-slides /opt/1arch-slides
COPY --chmod=0755 entrypoint.sh /usr/local/bin/1arch-entrypoint
COPY --chmod=0755 1arch-figure.sh /usr/local/bin/1arch-figure
# ELAN_HOME in THIS stage: a uid with HOME=/tmp would otherwise look in $HOME/.elan, find no toolchain and try to
# download one. TEXMFVAR: a uid's own luaotfload caches go to /tmp, never into the repository.
# LANG=C.UTF-8 (glibc's built-in UTF-8 locale; no locales package): the engines read text in the locale's encoding,
# and ias-check gives each engine only PATH, HOME and LANG. With no LANG (neither base image sets one), ias-cert-edges
# stopped on the template's lean/Paper/Example.lean ("cannot decode byte sequence starting from 206", the first byte
# of its alpha), the join recorded the lean checker as failed, and E2E-BUILD-ACTIVE exited 1 (run 44844658352, job
# 136661339128, 2026-11-21).
ENV ELAN_HOME=/opt/elan \
    PATH=/opt/elan/bin:/opt/texlive/bin:/opt/1arch-slides/node_modules/.bin:/opt/node/bin:$PATH \
    TEXMFVAR=/tmp/texmf-var \
    LANG=C.UTF-8

# ---- 5. test: ias-check run --build end to end, its canaries, T1 and the entrypoint, on this architecture, offline ----
FROM runtime AS test
ARG ONEARCH_REF
# jq reads the report in the test only; the image does not carry it
RUN apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/*
COPY smoke-test-build.sh /usr/local/share/1arch-tools-build/smoke-test-build.sh
# the own-paper fixture: synthetic, with no course-internal content
COPY fixtures/own-paper/ /usr/local/share/1arch-tools-build/fixtures/own-paper/
RUN --network=none ONEARCH_REF="$ONEARCH_REF" sh /usr/local/share/1arch-tools-build/smoke-test-build.sh

# ---- 6. slides-test: the template's talk to HTML as the lecture slides are built, and a TikZ figure on a slide ----
FROM runtime AS slides-test
COPY smoke-test-slides.sh /usr/local/share/1arch-tools-build/smoke-test-slides.sh
RUN --network=none sh /usr/local/share/1arch-tools-build/smoke-test-slides.sh

# ---- 7. the image: the runtime, carrying the guard's record and both tests' markers ----
FROM runtime
ARG TOOLS_IMAGE
ARG ONEARCH_REF
COPY --from=guard /guard/tools-image /usr/share/doc/1arch-tools-build/tools-image
COPY --from=test /usr/local/share/1arch-tools-build/test-passed /usr/share/doc/1arch-tools-build/test-passed
COPY --from=slides-test /usr/local/share/1arch-tools-build/slides-test-passed /usr/share/doc/1arch-tools-build/slides-test-passed
COPY smoke-test-build.sh smoke-test-slides.sh /usr/local/share/1arch-tools-build/
COPY NOTICE /usr/share/doc/1arch-tools-build/NOTICE
LABEL org.opencontainers.image.title="1arch-tools (-build)" \
      org.opencontainers.image.description="1arch-tools of one release + core Lean 4.32.0 + TeX Live 2023 + the course's slide machinery, no browser (Node 22, Marp, 1arch-figure): ias-check run --build and a group's talk in one container" \
      org.opencontainers.image.source="https://git.vake.works/ias/1archcodemathsprovedog" \
      org.opencontainers.image.revision="${ONEARCH_REF}" \
      org.opencontainers.image.base.name="${TOOLS_IMAGE}" \
      org.opencontainers.image.vendor="VakeWorks AB" \
      org.opencontainers.image.licenses="Apache-2.0 AND LicenseRef-1arch-tools-build-NOTICE"
# starts as root; the entrypoint runs the command as the mounted folder's owner
ENTRYPOINT ["/usr/local/bin/1arch-entrypoint"]
CMD ["ias-check"]
