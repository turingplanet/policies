# policies — the logic (Platform-owned · REFERENCE target)

Referenced live by member repos as `@vN`. A change here reaches the whole fleet instantly,
with no per-repo work — so this folder carries everything that should propagate centrally:

- `.github/workflows/review-reusable.yml` — **the one flow**: read manifest → install + declared tests → checks → gate.
- `agent/` — **the one standing review agent** (advisory only; it reports, the gate decides).

Versioned by tag. Members pin `@v1`; publishing `@v2` is how Scenario **C** (new test/review flow)
and **D** (smarter agent) ship. Per the migration levers: bump the agent (`agent/`) only when a
check is LLM-judged; everything else is a workflow change in the same repo.
