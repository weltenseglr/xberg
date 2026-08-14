# Handover: `weltenseglr/xberg` with transcription

This fork adds the `transcription` feature to the xberg server image so `ash_storage_xberg` can run Whisper transcription via the REST sidecar instead of the in-process NIF.

## What to patch

Two files. That's it.

### 1. `crates/xberg-cli/Cargo.toml`

Add a `transcription` feature flag after line 185 (after the `all` block closes):

```diff
 183:     "summarization",
 184:     "summarization-llm",
 185: ]
+186: transcription = ["xberg/transcription"]
```

**Why:** The `xberg` library crate already has a `transcription` feature that self-registers `TranscriptionExtractor` via `#[cfg(feature = "transcription")]`. The CLI crate just doesn't expose it. This one line forwards the flag.

### 2. `docker/Dockerfile`

The builder stage is now part of the single `docker/Dockerfile`, parameterized with `FEATURES` arg (default: `all`). The `cargo build` command uses `${FEATURES}` instead of hardcoded `all`.

**Why:** This allows the `full` and `omni` targets to reuse the heavy build dependencies (libheif, ONNX runtime, tesseract, cargo cache) while only differing in the final feature set.

## Docker image architecture

One multi-stage Dockerfile with layer reuse:

- **`--target builder`**: Multi-stage build
  - Stage 1 (builder): Install deps, copy source, cargo build with `--features ${FEATURES}`
  - Stage 2 (runtime): debian:trixie-slim + runtime deps, copy binary from builder
  - Build with: `docker build --target builder -f docker/Dockerfile -t xberg:build-base .`

- **`--target full`**: Uses the build-base image
  - Stage 1: `FROM xberg:build-base` (already has binary at /build/xberg)
  - Stage 2: Runtime image
  - Build with: `docker build --target full -f docker/Dockerfile -t xberg:full .`

- **`--target omni`**: Uses the build-base image, rebuilds with transcription
  - Stage 1: `FROM xberg:build-base`, then `cargo build --features all,transcription`
  - Stage 2: Runtime image
  - Build with: `docker build --target omni -f docker/Dockerfile -t xberg:omni .`

**Layer reuse:** The heavy deps (libheif, ONNX, tesseract, cargo registry cache) are in the build-base image, so they're built once and reused by both `full` and `omni` variants. Only the final cargo build step differs.

## Build instructions

Use the provided build script:

```bash
cd ~/Workspace/xberg

# Build all variants (base + full + omni)
./docker/build.sh all

# Or build individual variants
./docker/build.sh full   # base + full
./docker/build.sh omni   # base + omni
./docker/build.sh base   # just the builder stage
```

The build script automatically detects available CPUs and uses parallel compilation (leaves 2 CPUs for system, minimum 4 jobs). It uses the legacy Docker builder (`DOCKER_BUILDKIT=0`) for better CPU utilization.

Or manually with custom parallelization:

```bash
# 1. Build the base image (builder stage with all deps)
# Use legacy builder for better CPU utilization
DOCKER_BUILDKIT=0 docker build \
  --build-arg CARGO_BUILD_JOBS=12 \
  --target builder \
  -f docker/Dockerfile \
  -t xberg:build-base .

# 2. Build the full variant
DOCKER_BUILDKIT=0 docker build --target full -f docker/Dockerfile -t xberg:full .

# 3. Build the omni variant (with transcription)
DOCKER_BUILDKIT=0 docker build \
  --build-arg CARGO_BUILD_JOBS=12 \
  --target omni \
  -f docker/Dockerfile \
  -t xberg:omni .
```

**Build time:** First build: 1–3 hours (single-threaded), ~20–40 min (parallel with 12+ cores). Subsequent builds: ~10–20 min (cargo cache reused). The `transcription` feature pulls `symphonia` (pure-Rust audio decoder, ~5 MB) and `lofty` (audio tags, ~2 MB). Image size goes up ~30 MB for omni vs full. Whisper model weights are **not** baked in — they download from HF Hub into `HF_HOME=/app/.xberg/huggingface` on first audio call, or pre-warm with `POST /cache/warm`.

## Verify the omni variant

```bash
# Run the omni image
docker run --rm -p 8000:8000 \
  -v xberg-cache:/app/.xberg \
  xberg:omni

# In another terminal, verify transcription is registered
curl -s http://localhost:8000/health | jq .
# Expected: "plugins.extractors_count" should be 45 (was 44 in full), and "ocr_backends" unchanged

# Test transcription with a sample audio file
curl -X POST http://localhost:8000/extract \
  -F "files=@/path/to/tone.wav" \
  -F 'config={"transcription":{"enabled":true,"model":"tiny"}}'
```

## Publish to GHCR

```bash
# Login
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin

# Tag and push
docker tag xberg:full ghcr.io/weltenseglr/xberg:1.0.14-full
docker tag xberg:omni ghcr.io/weltenseglr/xberg:1.0.14-omni
docker push ghcr.io/weltenseglr/xberg:1.0.14-full
docker push ghcr.io/weltenseglr/xberg:1.0.14-omni
```

For multi-arch (amd64 + arm64), use `docker buildx`:

```bash
docker buildx create --use

# Build and push all variants
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target builder \
  -f docker/Dockerfile \
  --push \
  -t ghcr.io/weltenseglr/xberg:build-base \
  .

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target full \
  -f docker/Dockerfile \
  --push \
  -t ghcr.io/weltenseglr/xberg:1.0.14-full \
  .

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target omni \
  -f docker/Dockerfile \
  --push \
  -t ghcr.io/weltenseglr/xberg:1.0.14-omni \
  .
```

## Wire into `ash_storage_xberg`

Update `.devcontainer/docker-compose.yml`:

```diff
   xberg:
-    image: ghcr.io/xberg-io/xberg:latest
+    image: ghcr.io/weltenseglr/xberg:1.0.14-omni
     environment:
       XBERG_MAX_MULTIPART_FIELD_BYTES: "209715200"
       XBERG_MAX_REQUEST_BODY_BYTES: "209715200"
```

Then `Variants.Transcript` and `Analyzers.Audio` will work against the sidecar.

## Verify end-to-end

```bash
# Bring up the devcontainer
devcontainer up --workspace-folder ~/Workspace/ash_storage_xberg

# Run the transcript integration test
devcontainer exec --workspace-folder ~/Workspace/ash_storage_xberg bash -lc '
  XBERG_URL=http://xberg:8000 mix test --include transcript
'
```

Expected: `tone.wav` produces a transcript. First run downloads Whisper `tiny` model (~75 MB) into the cache volume.

## Maintenance: tracking upstream

When upstream releases a new version (e.g. `1.0.15`):

```bash
cd ~/Workspace/xberg

# Fetch upstream
git fetch upstream

# Rebase your fork onto upstream/main
git checkout main
git rebase upstream/main

# Resolve conflicts (should be trivial — your patch is two lines)
# The patch context may shift, but the diff itself is stable.

# Rebuild and push
./docker/build.sh all

# Tag and push to GHCR
docker tag xberg:full ghcr.io/weltenseglr/xberg:1.0.15-full
docker tag xberg:omni ghcr.io/weltenseglr/xberg:1.0.15-omni
docker push ghcr.io/weltenseglr/xberg:1.0.15-full
docker push ghcr.io/weltenseglr/xberg:1.0.15-omni

# Update ash_storage_xberg's devcontainer image tag
```

**Conflict risk:** Very low. Your patch touches two lines that upstream is unlikely to change. If they do, the rebase will flag it; you'll see the conflict, re-apply the two-line patch, and continue.

## Alternative: submit upstream PR

Before committing to the fork long-term, consider submitting the two-line patch to `xberg-io/xberg` as a PR. If they accept, you can drop the fork on the next release. The patch is genuinely minimal and doesn't bloat the default build (transcription is opt-in).

**Arguments for upstream:**
- One-line feature flag, no code changes
- Opt-in via `--features transcription`, doesn't affect default builds
- Aligns with the library's plugin architecture (extractors self-register)

**Arguments against:**
- Whisper models are large; they may want to keep the server image lean
- They may prefer the NIF path for media features

If they say no, the fork is the right answer.
