#!/usr/bin/env bash
# Sync the "oMLX (Local)" provider in ~/.pi/agent/models.json with the models
# currently served by a local oMLX instance.
set -euo pipefail

API="${OMLX_API:-http://localhost:8000/v1/models}"
CONFIG="${PI_MODELS_JSON:-$HOME/.pi/agent/models.json}"
PROVIDER="${PI_PROVIDER:-oMLX (Local)}"

models=$(curl -fsS "$API")

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
