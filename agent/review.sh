#!/usr/bin/env bash
# The standing review agent's body. Reads the manifest (the seam) and emits ADVISORY findings.
# Constant #3: this script must NEVER exit non-zero to block a merge — the gate decides, not the agent.
set -euo pipefail

MANIFEST="${1:-agent.manifest.yaml}"

profile=$(yq -r '.profile' "$MANIFEST")
language=$(yq -r '.toolchain.language' "$MANIFEST")

{
  echo "## Repo review agent — findings (advisory)"
  echo
  echo "- profile: \`$profile\`  ·  language: \`$language\`"
  echo "- TODO: call the LLM with the diff + manifest context and append findings here."
  echo
  echo "_The gate (build / tests / security) decides pass/fail. These notes never block a merge._"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
