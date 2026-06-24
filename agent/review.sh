#!/usr/bin/env bash
# THE ONE STANDING REVIEW AGENT (constant #1). Reads the manifest + the PR diff, asks Claude for an
# ADVISORY review, and writes findings to the run summary + the PR. Constant #3: this script must
# NEVER exit non-zero — the deterministic gate decides pass/fail; the agent only advises.
set -o pipefail

MANIFEST="${1:-agent.manifest.yaml}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
MODEL="claude-opus-4-8"   # the agent's model is an agent-behavior lever — bump the agent to change it

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

profile=$(yq '.profile' "$MANIFEST" 2>/dev/null || echo "unknown")
language=$(yq '.toolchain.language' "$MANIFEST" 2>/dev/null || echo "unknown")

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

body=$(printf '## Repo review agent — findings (advisory)\n\n- model: `%s` · profile: `%s` · language: `%s`\n\n%s\n\n_Advisory only — the deterministic gate (build / tests / lint / security) decides pass/fail._' \
  "$MODEL" "$profile" "$language" "$findings")

# 1) Always to the run summary.
printf '%s\n' "$body" >> "$SUMMARY"

# 2) Best-effort PR comment (needs pull-requests: write; fails closed on fork PRs — never gates).
if [ -n "$PR_NUMBER" ]; then
  printf '%s\n' "$body" | gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file - >/dev/null 2>&1 || true
fi

exit 0
