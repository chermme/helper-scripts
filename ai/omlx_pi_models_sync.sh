#!/usr/bin/env bash
# Sync the "oMLX (Local)" provider in ~/.pi/agent/models.json with the models
# currently served by a local oMLX instance.
set -euo pipefail

if [[ "${1:-}" == "--mbp16" ]]; then
  API="${OMLX_API:-http://192.168.29.108:8000/v1/models}"
  PROVIDER="${PI_PROVIDER:-oMLX (MBP16)}"
  OAUTH_TOKEN="${OMLX_AUTH:-omlx}"
else
  API="${OMLX_API:-http://localhost:8000/v1/models}"
  PROVIDER="${PI_PROVIDER:-oMLX (Local)}"
fi
CONFIG="${PI_MODELS_JSON:-$HOME/.pi/agent/models.json}"

if [[ -n "${OAUTH_TOKEN:-}" ]]; then
  models=$(curl -fsS -H "Authorization: Bearer $OAUTH_TOKEN" "$API")
else
  models=$(curl -fsS "$API")
fi

# oMLX exposes the plain OpenAI /v1/models schema: no loaded/vision metadata.
# Skip entries without a context length (non-LLM utilities); reasoning and
# text-only input default true / ["text"] since the API doesn't report them.
new_models=$(jq '[.data[]
  | select(.max_model_len != null)
  | {
    id: .id,
    contextWindow: .max_model_len,
    reasoning: true,
    name: .id,
    input: ["text"]
  }]' <<<"$models")

tmp=$(mktemp)
jq --arg p "$PROVIDER" --argjson m "$new_models" \
  '.providers[$p].models = $m' "$CONFIG" >"$tmp"
mv "$tmp" "$CONFIG"

echo "Updated \"$PROVIDER\": $(jq length <<<"$new_models") models."
