# policies — the rulebook + the robot reviewer

> **Part of 图灵星球 Agent 军团.** New here? Start at the overview: **https://github.com/turingplanet/agent-legion**

This repo is the platform's shared logic. Member repos **reference** it by version (`@vN`) — they never copy it. A change here, published as a new version, reaches any member who bumps to it.

It holds two things:
- **the one review flow** (`.github/workflows/review-reusable.yml`) — the steps every member PR runs.
- **the one standing review agent** (`agent/`) — the AI reviewer (advice only).

## What the review flow does on every PR

```mermaid
flowchart TB
    PR["A member opens a Pull Request"] --> M["1. Read the manifest<br/>(the repo's instruction card)"]
    M --> S["2. Set up declared tools<br/>(e.g. Python + poetry)"]
    S --> CH["3. Run the HARD checks:<br/>install · tests · lint · security"]
    AI["🤖 AI reviewer<br/>reads the diff, writes advice"] -. "comments only — never blocks" .-> G
    CH --> G{"🚦 4. Gate:<br/>did the hard checks pass?"}
    G -- "yes ✅" --> OK["PR can merge"]
    G -- "no ❌" --> BACK["Sent back with the findings"]
```

The **gate** (the hard checks passing) is what decides pass/fail. The AI reviewer only adds comments — it can never block a merge.

## How a change here reaches everyone

```mermaid
flowchart LR
    DEV["Platform improves a<br/>check or the reviewer"] --> PUB["Publishes policies@v5<br/>(v1…v4 stay frozen)"]
    PUB --> ADOPT["Each member adopts with a<br/>one-line bump: @v4 → @v5"]
    ADOPT --> MA["member A ✓"]
    ADOPT --> MB["member B ✓"]
    ADOPT --> MC["member C ✓"]
```

Versions are **frozen tags** (`v1`, `v2`, …) protected from being moved — so `@v4` always means exactly what it meant. Publishing `@v5` is how a new check or a smarter reviewer ships.

**The "one-line bump", concretely.** In *your own* member repo, edit **`.github/workflows/review.yml`** (your thin pointer) and change the version on the `uses:` line:

```diff
 jobs:
   review:
-    uses: turingplanet/policies/.github/workflows/review-reusable.yml@v4
+    uses: turingplanet/policies/.github/workflows/review-reusable.yml@v5
     with:
       contract: v1
```

That single line is the whole adoption — commit it (ideally via a PR, so your own gate runs against the new version), and your next PR uses `@v5`. You never copy or fork the flow.

(Per the design's migration levers: bump the agent in `agent/` only when a check is AI-judged; everything else is a change to the flow.)
