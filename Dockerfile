# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 VakeWorks AB
#
# lean-checker -- CLEAN, PUBLIC proof-checker image for ScaDaMaLe labs.
# Core-only Lean 4 (v4.32.0) via elan -- NO Mathlib, no internal certificates,
# no crunch tooling. It contains only what a student runs:
# a Lean toolchain that elaborates a mounted Check.lean. Native amd64 + arm64
# (built on native runners, combined into one manifest -- no qemu).
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# elan = the Lean toolchain manager; pin the exact toolchain the labs use.
ENV ELAN_HOME=/opt/elan \
    PATH=/opt/elan/bin:/opt/elan/toolchains/leanprover--lean4---v4.32.0/bin:$PATH
RUN curl -fsSL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o /tmp/elan-init.sh \
 && sh /tmp/elan-init.sh -y --default-toolchain leanprover/lean4:v4.32.0 \
 && rm /tmp/elan-init.sh \
 && lean --version

# Run as a non-root student; the lab dir is bind-mounted at /lab.
RUN useradd -m student
USER student
WORKDIR /lab
CMD ["lean", "--version"]
