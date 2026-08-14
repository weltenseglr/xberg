# Xberg Docker Images

This directory contains a single consolidated multi-stage `Dockerfile` for building Xberg Docker images with different feature sets. All runtime variants share one compiled binary and differ only in the runtime packages and model cache they bundle.

## Image Variants

| Image            | Description                                    | Base                | Size       |
| ---------------- | ---------------------------------------------- | ------------------- | ---------- |
| `xberg:builder`  | Build environment with all dev dependencies    | rust:1.95-trixie    | ~3-4GB     |
| `xberg:core`     | Minimal runtime, no cache warm                 | debian:trixie-slim  | ~1.0-1.3GB |
| `xberg:full`     | Full runtime + pre-warmed model cache          | debian:trixie-slim  | ~1.0-1.3GB |
| `xberg:omni`     | Full + transcription (audio/video)             | debian:trixie-slim  | ~1.0-1.3GB |

> **Note:** `xberg:cli` is a separate Alpine-based image built from `Dockerfile.cli` (musl static binary) and is not part of the multi-stage build.

## Base Image

Runtime images use **Debian 13 (Trixie) slim** - the latest stable Debian release for optimal package availability and security updates. The builder stage uses `rust:1.95-trixie`.

## Stage Hierarchy

```
builder (rust:1.95-trixie, all dev deps, libheif, ONNX, source)
├── build-binary (--features all) ──┬── core (runtime-base + minimal apt)
│                                   └── full (runtime-base + fontconfig/libssl3 + cache warm)
└── build-omni (--features all,transcription) └── omni (runtime-base + fontconfig/libssl3 + cache warm)

runtime-base (debian:trixie-slim, tesseract 12 langs, codec libs, user setup)
```

## Build Commands

Build individual targets from the consolidated `docker/Dockerfile`:

```bash
# Individual targets
docker buildx build --target builder -f docker/Dockerfile -t xberg:builder .
docker buildx build --target core -f docker/Dockerfile -t xberg:core .
docker buildx build --target full -f docker/Dockerfile -t xberg:full .
docker buildx build --target omni -f docker/Dockerfile -t xberg:omni .

# Or use the build script
./docker/build.sh [builder|core|full|omni|all]
```

The build script (`docker/build.sh`) sets `CARGO_BUILD_JOBS` automatically and builds `builder` first so subsequent targets hit the layer cache.

## Key Design Decisions

- **Core and Full share ONE compiled binary** (`--features all`) - they differ only in runtime packages
- **Omni compiles separately** with `--features all,transcription`
- **Core runtime** gains `libx264-164` + `libopenh264-8` (the binary links them from the shared builder)
- **Full/Omni** add `fontconfig` + `libssl3` + a pre-warmed model cache

## Size Comparison

| Component            | Core           | Full           | Omni          | Difference        |
| -------------------- | -------------- | -------------- | ------------- | ----------------- |
| Base (trixie-slim)   | ~120MB         | ~120MB         | ~120MB        | -                 |
| Tesseract + 12 langs | ~250MB         | ~250MB         | ~250MB        | -                 |
| Rust binary          | ~80MB          | ~80MB          | ~80MB         | - (same binary)  |
| System libraries     | ~100MB         | ~100MB         | ~100MB        | -                 |
| **Total (approx)**   | **~1.0-1.3GB** | **~1.0-1.3GB** | **~1.0-1.3GB** | **- (same size)** |

## Multi-Architecture Support

All images support:

- `linux/amd64` (x86_64)
- `linux/arm64` (aarch64)

Both architectures use the same pure-Rust PDF library — no architecture-specific binaries needed.

## Usage Modes

All images support three execution modes via ENTRYPOINT:

### 1. API Server (default)

```bash
docker run -p 8000:8000 xberg:core
# or override host/port:
docker run -p 8000:8000 xberg:core serve --host 0.0.0.0 --port 8000
```

### 2. CLI Mode

```bash
docker run -v $(pwd):/data xberg:core extract /data/document.pdf
docker run -v $(pwd):/data xberg:core detect /data/file.bin
docker run -v $(pwd):/data xberg:core batch /data/*.pdf
```

### 3. MCP Server Mode

```bash
docker run xberg:core mcp
```

## Testing

Test scripts are provided to verify image variants:

```bash
# Test core image
IMAGE_NAME=xberg:core ./scripts/test_docker.sh

# Test full image
IMAGE_NAME=xberg:full ./scripts/test_docker.sh
```

## GitHub Actions

The `.github/workflows/publish-docker.yaml` workflow builds and publishes all variants to GitHub Container Registry:

- `ghcr.io/xberg-io/xberg:VERSION-core` — Core image (minimal runtime)
- `ghcr.io/xberg-io/xberg:VERSION` — Full image (also published as `:latest`)
- `ghcr.io/xberg-io/xberg:VERSION-omni` — Omni image (with transcription)
- `ghcr.io/xberg-io/xberg:VERSION-builder` — Builder image (build environment)
- `ghcr.io/xberg-io/xberg-cli:VERSION` — CLI image (separate Alpine/musl build)

For local development, use the local tags shown in the build commands above.

## Recommendations

**Choose Core if:**

- ✅ Minimal runtime setup
- ✅ Standard document processing needs
- ✅ Cloud deployments with cost constraints
- ✅ Kubernetes or container orchestration

**Choose Full if:**

- ✅ Want maximum optional dependencies preinstalled
- ✅ Pre-warmed model cache for fast first use
- ✅ Development and testing environments
- ✅ "Batteries included" experience preferred

**Choose Omni if:**

- ✅ Need audio/video transcription (MP3, M4A, WAV, WebM, MP4) in addition to full document intelligence
- ✅ Single image covering both extraction and transcription workloads

**Choose Builder if:**

- ✅ Need a pre-built environment with all development dependencies (libheif, ONNX, Rust toolchain) to compile or test Xberg from source
