---
name: pair-review
description: Standalone cross-review of current git changes with a fresh read-only reviewer, optionally adding Codex's native review. ONLY runs when the user explicitly types /pair-review. NEVER activate automatically.
---

# /pair-review — quick second pair of eyes on current changes

Lightweight standalone review, for when the full /pair workflow is not in play
(e.g. the user or Codex wrote code directly and just wants it checked).

## Arguments

`/pair-review [codex] [base <branch>]`

- No args: review **uncommitted** changes (staged + unstaged + untracked) with a fresh Claude subagent.
- `base <branch>`: review `git diff <branch>...HEAD` instead of uncommitted changes.
- `codex`: ALSO run Codex's native reviewer and merge findings:
  - uncommitted scope: `codex exec -s read-only -c approval_policy=never review --uncommitted`
  - base scope: `codex exec -s read-only -c approval_policy=never review --base <branch>`

  Pass `-s read-only` explicitly — reviewing never needs write access, and the sandbox must
  not be inherited from `~/.codex/config.toml`, which may be temporarily set to a laxer mode.

## Procedure

1. Confirm there is actually something to review (`git status --porcelain` / the diff is non-empty).
   If empty, say so and stop.
2. Spawn a **fresh-context subagent** as the reviewer. It must be read-only
   (Read/Grep/Glob/read-only Bash; never edit). Give it the diff scope and instruct:
   report only real defects, each with file:line, a one-sentence claim, and a concrete
   failure scenario (inputs/state → wrong behavior). No style nits, no speculation.
3. If `codex` was requested, run the codex review command in parallel with a generous timeout.
4. Merge and dedupe findings, ranked most severe first. Note which reviewer found what
   only when the two disagree.
5. Report the findings to the user. **Do not fix anything** unless the user then asks.
