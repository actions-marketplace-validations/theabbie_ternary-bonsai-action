#!/usr/bin/env bash
set -euo pipefail

: "${BONSAI_ROOT:?BONSAI_ROOT is required}"

MODEL_REPO="prism-ml/Ternary-Bonsai-27B-gguf"
MODEL_REVISION="abbae723028d71be674e71e1a71201a6f43fab22"
MODEL_NAME="Ternary-Bonsai-27B-Q2_0.gguf"
MODEL_SIZE="7165121600"
MODEL_SHA256="868c11714cf8fe47f5ec9eeb2be0ab1a337112886f92ee0ede6b855c4fa31757"
RUNTIME_RELEASE="prism-b9596-9fcaed7"
RUNTIME_ARCHIVE="llama-prism-b9596-9fcaed7-bin-ubuntu-x64.tar.gz"
RUNTIME_SHA256="e361c09f128a407c659d07361b008155e1eab0cd0ed0a12ccdcf7147f7c22948"
RUNTIME_URL="https://github.com/PrismML-Eng/llama.cpp/releases/download/${RUNTIME_RELEASE}/${RUNTIME_ARCHIVE}"

MODEL_DIR="$BONSAI_ROOT/model"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
RUNTIME_DIR="$BONSAI_ROOT/runtime"
HF_VENV="${RUNNER_TEMP:-/tmp}/ternary-bonsai-hf-cli"

mkdir -p "$MODEL_DIR" "$RUNTIME_DIR"

if [[ -z "${HF_TOKEN:-}" ]]; then
  unset HF_TOKEN
fi

if [[ ! -f "$MODEL_PATH" ]] || [[ "$(wc -c < "$MODEL_PATH")" != "$MODEL_SIZE" ]]; then
  rm -f "$MODEL_PATH"
  python3 -m venv "$HF_VENV"
  "$HF_VENV/bin/python" -m pip install --disable-pip-version-check --quiet "huggingface-hub==1.24.0"
  "$HF_VENV/bin/hf" download "$MODEL_REPO" "$MODEL_NAME" \
    --revision "$MODEL_REVISION" \
    --local-dir "$MODEL_DIR" \
    --max-workers 4
fi

if [[ "$(wc -c < "$MODEL_PATH")" != "$MODEL_SIZE" ]]; then
  echo "Model size verification failed." >&2
  exit 1
fi

printf '%s  %s\n' "$MODEL_SHA256" "$MODEL_PATH" | sha256sum --check --status

if [[ ! -x "$RUNTIME_DIR/llama-server" ]] || [[ ! -f "$RUNTIME_DIR/.release" ]] || [[ "$(< "$RUNTIME_DIR/.release")" != "$RUNTIME_RELEASE" ]]; then
  archive="$(mktemp)"
  extract_dir="$(mktemp -d)"
  trap 'rm -f "$archive"; rm -rf "$extract_dir"' EXIT
  curl --fail --location --silent --show-error "$RUNTIME_URL" --output "$archive"
  printf '%s  %s\n' "$RUNTIME_SHA256" "$archive" | sha256sum --check --status
  tar -xzf "$archive" -C "$extract_dir"
  server_path="$(find "$extract_dir" -type f -name llama-server -print -quit)"
  if [[ -z "$server_path" ]]; then
    echo "llama-server was not found in the runtime archive." >&2
    exit 1
  fi
  runtime_source="$(dirname "$server_path")"
  rm -rf "$RUNTIME_DIR"
  mkdir -p "$RUNTIME_DIR"
  cp -a "$runtime_source/." "$RUNTIME_DIR/"
  chmod +x "$RUNTIME_DIR"/llama-*
  printf '%s\n' "$RUNTIME_RELEASE" > "$RUNTIME_DIR/.release"
fi

"$RUNTIME_DIR/llama-server" --version
printf 'Model: %s\n' "$MODEL_PATH"
du -h "$MODEL_PATH"
