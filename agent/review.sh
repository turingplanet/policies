#!/usr/bin/env bash
# THE ONE STANDING REVIEW AGENT (constant #1). Reads the manifest + the PR diff, asks Claude for an
# ADVISORY review, and writes findings to the run summary + the PR. Constant #3: this script must
# NEVER exit non-zero — the deterministic gate decides pass/fail; the agent only advises.
set -o pipefail

MANIFEST="${1:-agent.manifest.yaml}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
MODEL="claude-opus-4-8"   # the agent's model is an agent-behavior lever — bump the agent to change it
# Pricing for $MODEL — USD per TOKEN (claude-opus-4-8: $5 / $25 per 1M input/output; cache read 0.1×, write 1.25×).
# KEEP IN SYNC with MODEL above: update these four rates whenever the model changes.
PRICE_IN=0.000005
PRICE_OUT=0.000025
PRICE_CACHE_READ=0.0000005
PRICE_CACHE_WRITE=0.00000625

ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
PR_NUMBER="${PR_NUMBER:-}"
REPO="${REPO:-}"

note() { printf '%s\n' "$1" >> "$SUMMARY"; }

# Graceful no-op when the key isn't available — e.g. fork PRs never receive secrets.
if [ -z "$ANTHROPIC_API_KEY" ]; then
  note "## Repo review agent — skipped"
  note ""
  note "_No \`ANTHROPIC_API_KEY\` available (fork PR, or the secret isn't configured on this repo). The deterministic gate still decided this PR._"
  exit 0
fi

profile=$(yq '.profile // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
language=$(yq '.toolchain.language // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")

# The change under review.
diff=$(gh pr diff "$PR_NUMBER" --repo "$REPO" 2>/dev/null || true)
if [ -z "$diff" ]; then
  note "## Repo review agent — nothing to review"
  note ""
  note "_Could not read a diff for this PR (advisory step)._"
  exit 0
fi

# Bound the payload for cost + context safety; flag if truncated.
max=200000
truncated=""
if [ "${#diff}" -gt "$max" ]; then
  diff="${diff:0:$max}"
  truncated=" (diff truncated to ${max} chars)"
fi

system="You are the single standing code-review agent for the 图灵星球 Agent 军团 platform. \
You review one pull request's diff and write concise, actionable findings. \
You are ADVISORY ONLY: a separate deterministic gate (build, tests, lint, security) decides pass/fail — \
never tell the author the PR is blocked or approved. \
Focus on issues introduced by THIS diff: correctness bugs, security problems, and clear quality issues. \
For each finding give a short title, the file/area, a severity (high/medium/low), and a one-line explanation. \
Report everything noteworthy, including low-confidence items — a human filters downstream. \
If you find nothing noteworthy, say so in one line. Output GitHub-flavored markdown with no preamble."

user=$(printf 'Repo profile: %s · language: %s%s\n\nReview this pull request diff:\n\n```diff\n%s\n```' \
  "$profile" "$language" "$truncated" "$diff")

payload=$(jq -n --arg model "$MODEL" --arg sys "$system" --arg user "$user" \
  '{model:$model, max_tokens:4000, system:$sys, messages:[{role:"user", content:$user}]}')

resp=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -d "$payload" 2>/dev/null || true)

# Extract text blocks; handle API errors / refusals gracefully (constant #3 — still never gate).
findings=$(printf '%s' "$resp" | jq -r '[.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null || true)
if [ -z "$findings" ]; then
  err=$(printf '%s' "$resp" | jq -r '.error.message // .stop_reason // "no response text"' 2>/dev/null || echo "no response text")
  findings="_The review model returned no findings (${err})._"
fi

# Token usage + estimated cost (advisory observability). Fields are absent on an API error/refusal → default 0.
in_tok=$(printf '%s' "$resp"     | jq -r '.usage.input_tokens // 0'                2>/dev/null || echo 0)
out_tok=$(printf '%s' "$resp"    | jq -r '.usage.output_tokens // 0'               2>/dev/null || echo 0)
cwrite_tok=$(printf '%s' "$resp" | jq -r '.usage.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)
cread_tok=$(printf '%s' "$resp"  | jq -r '.usage.cache_read_input_tokens // 0'     2>/dev/null || echo 0)
cost=$(awk -v i="$in_tok" -v o="$out_tok" -v cw="$cwrite_tok" -v cr="$cread_tok" \
  -v pi="$PRICE_IN" -v po="$PRICE_OUT" -v pcw="$PRICE_CACHE_WRITE" -v pcr="$PRICE_CACHE_READ" \
  'BEGIN { printf "%.4f", i*pi + o*po + cw*pcw + cr*pcr }' 2>/dev/null || echo "0.0000")
usage_line=$(printf 'usage: %s in · %s out tokens · est. cost $%s (model %s)' "$in_tok" "$out_tok" "$cost" "$MODEL")
# Surface in the Actions log as an annotation (shows in the run-summary UI, not just buried in step logs).
printf '::notice title=Review agent usage::%s\n' "$usage_line"

body=$(printf '## Repo review agent — findings (advisory)\n\n- model: `%s` · profile: `%s` · language: `%s`\n- %s\n\n%s\n\n_Advisory only — the deterministic gate (build / tests / lint / security) decides pass/fail._' \
  "$MODEL" "$profile" "$language" "$usage_line" "$findings")

# 1) Always to the run summary.
printf '%s\n' "$body" >> "$SUMMARY"

# 2) Best-effort PR comment (needs pull-requests: write; fails closed on fork PRs — never gates).
if [ -n "$PR_NUMBER" ]; then
  printf '%s\n' "$body" | gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file - >/dev/null 2>&1 || true
fi

exit 0
