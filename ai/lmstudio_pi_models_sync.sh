#!/usr/bin/env bash
# Sync the "LMStudio (Local)" provider in ~/.pi/agent/models.json with the
# models currently served by a local LM Studio instance.
set -euo pipefail

API="${LMSTUDIO_API:-http://localhost:1234/api/v1/models}"
CONFIG="${PI_MODELS_JSON:-$HOME/.pi/agent/models.json}"
PROVIDER="${PI_PROVIDER:-LMStudio (Local)}"

models=$(curl -fsS "$API")

# Map LM Studio's schema -> pi's model schema. Only currently-loaded LLMs are
# synced; contextWindow is the loaded instance's actual context_length.
# reasoning defaults true (LM Studio doesn't report it).
new_models=$(jq '[.models[]
  | select(.type == "llm" and (.loaded_instances | length) > 0)
  | {
    id: .key,
    contextWindow: .loaded_instances[0].config.context_length,
    reasoning: true,
    name: .display_name,
    input: (["text"] + (if .capabilities.vision then ["image"] else [] end))
  }]' <<<"$models")

tmp=$(mktemp)
jq --arg p "$PROVIDER" --argjson m "$new_models" \
  '.providers[$p].models = $m' "$CONFIG" >"$tmp"
mv "$tmp" "$CONFIG"

echo "Updated \"$PROVIDER\": $(jq length <<<"$new_models") models."
