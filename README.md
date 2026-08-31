# ScaDaMaLe lab images

Native multi-architecture (linux/amd64 + linux/arm64, **no qemu**) OCI image builds for the
[ScaDaMaLe](https://vake.works/courses/ScaDaMaLe) course labs. Each image is built on real
hardware per architecture, then combined into one manifest so `docker pull` serves each student
their own architecture (Intel/AMD laptops and Apple-Silicon Macs alike).

## Images

| Image | Purpose |
|-------|---------|
| `vakeworks/lean-checker:v4.32.0` | Clean core-only Lean 4 toolchain (no Mathlib). Elaborates a mounted `Check.lean` — the Lab 0 proof-checker. |

## How it is built (human-runnable — no automation required to understand or reproduce)

The build is a GitLab CI pipeline (`.gitlab-ci.yml`) with three jobs:

1. **`build:amd64`** — on a native amd64 runner: `docker build --platform linux/amd64`, then a
   **kernel self-test** (the toolchain must *accept* `1 + 1 = 2` and *reject* `1 + 1 = 3`), then push `…:v4.32.0-amd64`.
2. **`build:arm64`** — identical, on a native arm64 runner → push `…:v4.32.0-arm64`.
3. **`manifest`** — `docker manifest create`/`push` combines the two arch tags into the multi-arch
   `vakeworks/lean-checker:v4.32.0`.

No qemu/binfmt emulation anywhere: each arch is compiled on its own real CPU.

### Reproduce it yourself (single arch, on your own machine)

```sh
docker build --platform linux/amd64 -t vakeworks/lean-checker:v4.32.0-amd64 .
printf 'theorem t : 1 + 1 = 2 := rfl\n' > Check.lean
docker run --rm -v "$PWD:/lab" -w /lab vakeworks/lean-checker:v4.32.0-amd64 lean Check.lean   # accepts
printf 'theorem t : 1 + 1 = 3 := rfl\n' > Check.lean
docker run --rm -v "$PWD:/lab" -w /lab vakeworks/lean-checker:v4.32.0-amd64 lean Check.lean   # rejects (non-zero exit)
```

## CI variables (set once, in project → Settings → CI/CD → Variables)

- `DOCKERHUB_USER` — Docker Hub username with push access to `vakeworks/*`.
- `DOCKERHUB_TOKEN` — a Docker Hub access token (masked).

## Licence

Apache-2.0. Copyright (c) 2026 VakeWorks AB.
