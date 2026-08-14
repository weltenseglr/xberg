# =============================================================================
# Xberg consolidated multi-stage Dockerfile
#
# Consolidates Dockerfile.core, Dockerfile.build-full, Dockerfile.full,
# and Dockerfile.omni into 7 named stages built via --target.
#
# Stages:
#   1. builder       - rust base, all dev deps (superset), libheif, ONNX, source
#   2. build-binary  - compiles xberg-cli --features all (shared by core + full)
#   3. build-omni    - compiles xberg-cli --features all,transcription
#   4. runtime-base  - debian:trixie-slim, common runtime deps, user, dirs
#   5. core          - minimal runtime (libx264 + libopenh264 only), no cache warm
#   6. full          - + fontconfig/libssl3, cache warm, binary from build-binary
#   7. omni          - + fontconfig/libssl3, cache warm, binary from build-omni
#
# Build commands:
#   docker buildx build --target core -f docker/Dockerfile -t xberg:core .
#   docker buildx build --target full -f docker/Dockerfile -t xberg:full .
#   docker buildx build --target omni -f docker/Dockerfile -t xberg:omni .
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: builder - install all dev deps, build libheif, download ONNX Runtime
# -----------------------------------------------------------------------------
FROM rust:1.95-trixie AS builder

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        cmake \
        g++ \
        pkg-config \
        libssl-dev \
        libleptonica-dev \
        libtesseract-dev \
        libde265-dev \
        libaom-dev \
        libx265-dev \
        libdav1d-dev \
        libx264-dev \
        libopenh264-dev \
        clang \
        curl \
        file \
        ca-certificates \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN cd /tmp && \
    curl -fsSL -o libheif.tar.gz https://github.com/strukturag/libheif/releases/download/v1.23.0/libheif-1.23.0.tar.gz && \
    tar -xzf libheif.tar.gz && \
    cd libheif-1.23.0 && \
    cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF -DBUILD_TESTING=OFF && \
    cmake --build build -j"$(nproc)" && \
    cmake --install build && \
    ldconfig && \
    cd / && rm -rf /tmp/libheif*

ARG ONNXRUNTIME_VERSION=1.24.2
ARG TARGETARCH
ENV ONNXRUNTIME_VERSION=${ONNXRUNTIME_VERSION}

RUN mkdir -p /build/onnxruntime && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        ORT_ARCH="aarch64"; \
    else \
        ORT_ARCH="x64"; \
    fi && \
    curl -fL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNXRUNTIME_VERSION}/onnxruntime-linux-${ORT_ARCH}-${ONNXRUNTIME_VERSION}.tgz" \
        -o /build/onnxruntime.tgz && \
    tar -xzf /build/onnxruntime.tgz -C /build/onnxruntime --strip-components=1 && \
    rm /build/onnxruntime.tgz

COPY Cargo.toml Cargo.lock ./
COPY crates/xberg/ crates/xberg/
COPY crates/ttf-parser-compat/ crates/ttf-parser-compat/
COPY crates/xberg-gliner/ crates/xberg-gliner/
COPY crates/xberg-cli/ crates/xberg-cli/
COPY crates/xberg-libheif/ crates/xberg-libheif/
COPY crates/xberg-libwpd/ crates/xberg-libwpd/
COPY crates/xberg-tesseract/ crates/xberg-tesseract/
COPY crates/xberg-paddle-ocr/ crates/xberg-paddle-ocr/
COPY crates/xberg-candle-ocr/ crates/xberg-candle-ocr/

RUN sed -i '/xberg-py/d; /xberg_rb/d; /xberg-node/d; /xberg-ffi/d; /xberg-jni/d; /xberg-php/d; /xberg-rag/d; /xberg_rustler/d; /xberg_nif/d; /packages\/dart\/rust/d; /packages\/swift\/rust/d; /"crates\/xberg-wasm"/d; /^\[profile\.release\.package\.xberg-wasm\]$/,$d; /benchmark-harness/d; /e2e-generator/d; /snippet-runner/d; /e2e\/rust/d' Cargo.toml

# -----------------------------------------------------------------------------
# Stage 2: build-binary - compile xberg-cli --features all (core + full share this)
# -----------------------------------------------------------------------------
FROM builder AS build-binary

ARG CARGO_BUILD_JOBS=8
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    cargo build --release --package xberg-cli --features all -j ${CARGO_BUILD_JOBS} && \
    cp target/release/xberg /build/xberg && \
    strip /build/xberg

# -----------------------------------------------------------------------------
# Stage 3: build-omni - compile xberg-cli --features all,transcription
# -----------------------------------------------------------------------------
FROM builder AS build-omni

ARG CARGO_BUILD_JOBS=8
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/build/target \
    cargo build --release --package xberg-cli --features all,transcription -j ${CARGO_BUILD_JOBS} && \
    cp target/release/xberg /build/xberg && \
    strip /build/xberg

# -----------------------------------------------------------------------------
# Stage 4: runtime-base - common runtime setup shared by core, full, omni
# -----------------------------------------------------------------------------
FROM debian:trixie-slim AS runtime-base

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        tini \
        tesseract-ocr \
        tesseract-ocr-eng \
        tesseract-ocr-osd \
        tesseract-ocr-spa \
        tesseract-ocr-fra \
        tesseract-ocr-deu \
        tesseract-ocr-ita \
        tesseract-ocr-por \
        tesseract-ocr-chi-sim \
        tesseract-ocr-chi-tra \
        tesseract-ocr-jpn \
        tesseract-ocr-ara \
        tesseract-ocr-rus \
        tesseract-ocr-hin \
        libde265-0 \
        libaom3 \
        libx265-215 \
        libdav1d7 \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -r xberg && \
    useradd -r -g xberg -d /app -s /sbin/nologin xberg && \
    mkdir -p /app/.xberg && \
    chown -R xberg:xberg /app

RUN mkdir -p /etc/xberg /app/.config/xberg && \
    chown -R xberg:xberg /etc/xberg /app/.config/xberg

RUN mkdir -p /app/.xberg/huggingface && \
    chown -R xberg:xberg /app/.xberg/huggingface

RUN mkdir -p /app/.xberg/paddle-ocr && \
    chown -R xberg:xberg /app/.xberg/paddle-ocr

RUN set -eux; \
    echo "Setting up tessdata permissions..."; \
    for dir in /usr/share/tesseract-ocr/*/tessdata /usr/share/tesseract-ocr/tessdata /usr/share/tessdata; do \
        if [ -d "$dir" ]; then \
            chmod -R a+rx "$dir" 2>/dev/null || true; \
            if [ -f "$dir/eng.traineddata" ]; then \
                echo "✓ Found tessdata with eng.traineddata at: $dir"; \
            fi; \
        fi; \
    done; \
    echo "✓ Tessdata permissions configured"

ENV XBERG_CACHE_DIR=/app/.xberg \
    HF_HOME=/app/.xberg/huggingface \
    RUST_LOG=info \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/lib:/lib

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/xberg", "--version"]

ENTRYPOINT ["/usr/bin/tini", "--", "xberg"]
CMD ["serve", "--host", "0.0.0.0", "--port", "8000"]

# -----------------------------------------------------------------------------
# Stage 5: core - minimal runtime, no fontconfig, no libssl3, no cache warm
# -----------------------------------------------------------------------------
FROM runtime-base AS core

LABEL org.opencontainers.image.source="https://github.com/xberg-io/xberg"
LABEL org.opencontainers.image.description="Xberg document intelligence - core variant"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libx264-164 \
        libopenh264-8 \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=build-binary /usr/local/lib/libheif* /usr/local/lib/
COPY --from=build-binary /usr/local/lib/pkgconfig/libheif.pc /usr/local/lib/pkgconfig/libheif.pc
RUN ldconfig

COPY --from=build-binary /build/onnxruntime/lib/libonnxruntime.so* /usr/local/lib/
RUN ldconfig

COPY --from=build-binary /build/xberg /usr/local/bin/xberg
RUN chmod +x /usr/local/bin/xberg

USER xberg

# -----------------------------------------------------------------------------
# Stage 6: full - fontconfig + libssl3 + cache warm, binary from build-binary
# -----------------------------------------------------------------------------
FROM runtime-base AS full

LABEL org.opencontainers.image.source="https://github.com/xberg-io/xberg"
LABEL org.opencontainers.image.description="Xberg document intelligence - full variant"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fontconfig \
        libssl3 \
        libx264-164 \
        libopenh264-8 \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=build-binary /usr/local/lib/libheif* /usr/local/lib/
COPY --from=build-binary /usr/local/lib/pkgconfig/libheif.pc /usr/local/lib/pkgconfig/libheif.pc
RUN ldconfig

COPY --from=build-binary /build/onnxruntime/lib/libonnxruntime.so* /usr/local/lib/
RUN ldconfig

COPY --from=build-binary /build/xberg /usr/local/bin/xberg
RUN chmod +x /usr/local/bin/xberg

RUN XBERG_CACHE_DIR=/app/.xberg \
    /usr/local/bin/xberg cache warm --cache-dir /app/.xberg --format json && \
    chown -R xberg:xberg /app/.xberg && \
    echo "All models ready (PaddleOCR + layout detection)"

USER xberg

# -----------------------------------------------------------------------------
# Stage 7: omni - transcription build, fontconfig + libssl3 + cache warm
# -----------------------------------------------------------------------------
FROM runtime-base AS omni

LABEL org.opencontainers.image.source="https://github.com/xberg-io/xberg"
LABEL org.opencontainers.image.description="Xberg document intelligence - omni variant (with transcription)"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fontconfig \
        libssl3 \
        libx264-164 \
        libopenh264-8 \
        && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=build-omni /usr/local/lib/libheif* /usr/local/lib/
COPY --from=build-omni /usr/local/lib/pkgconfig/libheif.pc /usr/local/lib/pkgconfig/libheif.pc
RUN ldconfig

COPY --from=build-omni /build/onnxruntime/lib/libonnxruntime.so* /usr/local/lib/
RUN ldconfig

COPY --from=build-omni /build/xberg /usr/local/bin/xberg
RUN chmod +x /usr/local/bin/xberg

RUN XBERG_CACHE_DIR=/app/.xberg \
    /usr/local/bin/xberg cache warm --cache-dir /app/.xberg --format json && \
    chown -R xberg:xberg /app/.xberg && \
    echo "All models ready (PaddleOCR + layout detection)"

USER xberg
