#!/usr/bin/env bash
# Build script for xberg Docker images using the consolidated Dockerfile
# Usage: ./build.sh [builder|core|full|omni|all]

set -euo pipefail

IMAGE_BASE="xberg"

# Detect available CPUs for parallel compilation
AVAILABLE_CPUS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
# Leave 2 CPUs for system, use at least 4 for build
BUILD_JOBS=$((AVAILABLE_CPUS > 2 ? AVAILABLE_CPUS - 2 : 4))
echo "Using ${BUILD_JOBS} parallel jobs for cargo build (${AVAILABLE_CPUS} CPUs available)"

build_target() {
    local target=$1
    echo "Building ${target} target..."
    docker build \
        --target "${target}" \
        --build-arg CARGO_BUILD_JOBS=${BUILD_JOBS} \
        -f docker/Dockerfile \
        -t "${IMAGE_BASE}:${target}" \
        .
    echo "✓ Built: ${IMAGE_BASE}:${target}"
}

case "${1:-all}" in
    builder) build_target builder ;;
    core)    build_target core ;;
    full)    build_target full ;;
    omni)    build_target omni ;;
    all)
        # Build builder first so subsequent targets hit the layer cache
        build_target builder
        build_target core
        build_target full
        build_target omni
        echo ""
        echo "All images built successfully:"
        echo "  - ${IMAGE_BASE}:builder"
        echo "  - ${IMAGE_BASE}:core"
        echo "  - ${IMAGE_BASE}:full"
        echo "  - ${IMAGE_BASE}:omni"
        ;;
    *)
        echo "Usage: $0 [builder|core|full|omni|all]"
        echo "  builder - Build only the builder stage (all deps)"
        echo "  core    - Build core variant"
        echo "  full    - Build full variant"
        echo "  omni    - Build omni variant (with transcription)"
        echo "  all     - Build builder + core + full + omni (default)"
        exit 1
        ;;
esac
