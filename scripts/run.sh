#!/usr/bin/env bash
set -euo pipefail

: "${BONSAI_ROOT:?BONSAI_ROOT is required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

MODEL_PATH="$BONSAI_ROOT/model/Ternary-Bonsai-27B-Q2_0.gguf"
RUNTIME_DIR="$BONSAI_ROOT/runtime"
SERVER="$RUNTIME_DIR/llama-server"
CONTEXT_SIZE="${BONSAI_CONTEXT_SIZE:-4096}"
TEMPERATURE="${BONSAI_TEMPERATURE:-0.7}"
TOP_P="${BONSAI_TOP_P:-0.95}"
MAX_TOKENS="${BONSAI_MAX_TOKENS:-}"
RESPONSE_FILE="${BONSAI_RESPONSE_FILE:-bonsai-response.txt}"
SYSTEM_PROMPT="${BONSAI_SYSTEM_PROMPT:-You are a helpful assistant.}"

if [[ -n "${BONSAI_PROMPT:-}" ]] && [[ -n "${BONSAI_PROMPT_FILE:-}" ]]; then
  echo "Use either prompt or prompt-file, not both." >&2
  exit 1
fi

if [[ -n "${BONSAI_PROMPT_FILE:-}" ]]; then
  PROMPT="$(< "$GITHUB_WORKSPACE/$BONSAI_PROMPT_FILE")"
else
  PROMPT="${BONSAI_PROMPT:-}"
fi

if [[ -z "$PROMPT" ]]; then
  echo "prompt or prompt-file is required." >&2
  exit 1
fi

if [[ ! "$CONTEXT_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "context-size must be a positive integer." >&2
  exit 1
fi

if [[ -n "$MAX_TOKENS" ]] && [[ ! "$MAX_TOKENS" =~ ^[1-9][0-9]*$ ]]; then
  echo "max-tokens must be empty or a positive integer." >&2
  exit 1
fi

if ! jq -en --arg value "$TEMPERATURE" '$value | tonumber | . >= 0 and . <= 2' >/dev/null; then
  echo "temperature must be between 0 and 2." >&2
  exit 1
fi

if ! jq -en --arg value "$TOP_P" '$value | tonumber | . > 0 and . <= 1' >/dev/null; then
  echo "top-p must be greater than 0 and at most 1." >&2
  exit 1
fi

if [[ ! -f "$MODEL_PATH" ]] || [[ ! -x "$SERVER" ]]; then
  echo "Local model or runtime is missing." >&2
  exit 1
fi

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
SERVER_LOG="${RUNNER_TEMP:-/tmp}/ternary-bonsai-server.log"
API_RESPONSE="${RUNNER_TEMP:-/tmp}/ternary-bonsai-response.json"
export LD_LIBRARY_PATH="$RUNTIME_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$SERVER" \
  -m "$MODEL_PATH" \
  --host 127.0.0.1 \
  --port "$PORT" \
  -ngl 0 \
  -fa on \
  -c "$CONTEXT_SIZE" \
  --temp "$TEMPERATURE" \
  --top-p "$TOP_P" \
  --top-k 20 \
  --min-p 0 \
  --jinja \
  >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  wait "$SERVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready="false"
for _ in $(seq 1 300); do
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    cat "$SERVER_LOG" >&2
    exit 1
  fi
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:$PORT/health" || true)"
  if [[ "$status" == "200" ]]; then
    ready="true"
    break
  fi
  sleep 2
done

if [[ "$ready" != "true" ]]; then
  cat "$SERVER_LOG" >&2
  echo "llama-server did not become ready." >&2
  exit 1
fi

request="$(
  jq -n \
    --arg system "$SYSTEM_PROMPT" \
    --arg prompt "$PROMPT" \
    --arg temperature "$TEMPERATURE" \
    --arg top_p "$TOP_P" \
    '{
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $prompt}
      ],
      stream: false,
      temperature: ($temperature | tonumber),
      top_p: ($top_p | tonumber)
    }'
)"

if [[ -n "$MAX_TOKENS" ]]; then
  request="$(jq --arg max_tokens "$MAX_TOKENS" '. + {max_tokens: ($max_tokens | tonumber)}' <<<"$request")"
fi

http_status="$(
  curl --silent --show-error \
    --max-time 3600 \
    --output "$API_RESPONSE" \
    --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data "$request" \
    "http://127.0.0.1:$PORT/v1/chat/completions"
)"

if [[ "$http_status" != "200" ]]; then
  cat "$API_RESPONSE" >&2
  exit 1
fi

response="$(jq -r '.choices[0].message.content // empty' "$API_RESPONSE")"
reasoning="$(jq -r '.choices[0].message.reasoning_content // empty' "$API_RESPONSE")"
timings="$(jq -c '.timings // {}' "$API_RESPONSE")"

if [[ -z "$response" ]]; then
  if [[ -n "$reasoning" ]]; then
    echo "The completion ended before a final answer. Increase max-tokens or leave it empty." >&2
  else
    echo "llama-server returned no final answer." >&2
  fi
  exit 1
fi

if [[ "$RESPONSE_FILE" = /* ]]; then
  OUTPUT_PATH="$RESPONSE_FILE"
else
  OUTPUT_PATH="$GITHUB_WORKSPACE/$RESPONSE_FILE"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
printf '%s' "$response" > "$OUTPUT_PATH"

delimiter="bonsai_${RANDOM}_$(date +%s)"
{
  printf 'response<<%s\n%s\n%s\n' "$delimiter" "$response" "$delimiter"
  printf 'reasoning<<%s\n%s\n%s\n' "$delimiter" "$reasoning" "$delimiter"
  printf 'response-file=%s\n' "$OUTPUT_PATH"
  printf 'model-path=%s\n' "$MODEL_PATH"
  printf 'timings=%s\n' "$timings"
} >> "$GITHUB_OUTPUT"

printf '%s\n' "$response"
