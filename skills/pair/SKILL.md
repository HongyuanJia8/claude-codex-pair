---
name: pair
description: Dual-agent development workflow - Claude Code plans and reviews, Codex implements headlessly, git automated. ONLY runs when the user explicitly types /pair. NEVER activate automatically, no matter how well a task seems to match this workflow.
---

# /pair — Claude plans, Codex implements, Claude reviews

You (Claude Code) are the orchestrator and reviewer. Codex CLI is the implementer,
invoked headlessly via `codex exec` — the user never copies context between terminals.

## Arguments

`/pair [fast|strict] <task description>`

- First word `fast` or `strict` selects the profile; otherwise profile is **standard**.
- Everything else is the task description.

| Profile  | Plan handoff doc | Human plan approval | Claude review loop | Extra codex review |
|----------|------------------|---------------------|--------------------|--------------------|
| fast     | no (one-paragraph instruction) | no | no | no |
| standard | yes              | no                  | yes (max 2 rounds) | no |
| strict   | yes              | **yes — wait for approval** | yes (max 2 rounds) | yes (`codex exec review`) |

## Preflight (all profiles)

1. Verify this is a git repository (`git rev-parse --git-dir`). If not, ask the user whether to `git init` or abort.
2. Verify `codex` is on PATH. If not, stop and tell the user.
3. If the working tree has uncommitted changes, ask the user whether to proceed anyway
   (changes will get mixed into the pair branch) or stop so they can commit/stash first.
4. Note the current branch name — it is the **base branch** for diffs and review.

## Phase 1 — Clarify & plan (you, current session)

- If the task is ambiguous in a way that would change what gets built, ask the user
  at most 2–3 questions (AskUserQuestion). If it's clear, ask nothing.
- **standard/strict**: write a short handoff document to a temp file OUTSIDE the repo
  (use the session scratchpad dir, e.g. `<scratchpad>/pair-handoff.md`). Contents:
  - Goal: what to build/change and why (2–5 sentences).
  - Constraints: language/framework conventions, files or areas involved, things NOT to touch.
  - Acceptance criteria: observable behaviors, edge cases that must work, tests that must pass.
  - Pointers: relevant existing files/functions/patterns you found, so Codex doesn't re-explore blindly.
  - **Deliberately DO NOT prescribe the implementation approach** — no step-by-step design,
    no function signatures unless they are an external contract. Let Codex think.
  - End with: "When done, ensure the project's own format/lint/typecheck/test commands pass.
    Do not commit; leave changes in the working tree. Do not touch anything outside this repository."
- **fast**: skip the doc; compose a single clear paragraph with the same spirit (goal + acceptance + don't commit).
- **strict only**: show the handoff doc to the user and wait for explicit approval before continuing.

## Phase 2 — Branch

```bash
git checkout -b pair/<short-kebab-slug>
```

Do not use a worktree by default. Only if the user asked to run multiple `/pair` tasks
in parallel, create a worktree per task instead (`git worktree add`).

## Phase 3 — Codex implements

From the repo root:

```bash
codex exec -c approval_policy=never - < <scratchpad>/pair-handoff.md
```

(fast profile: pass the paragraph as the prompt argument instead of stdin.)

- Run with a generous timeout (10 min). For clearly large tasks, run in background and monitor.
- Codex's session is recorded; later fix rounds use `codex exec resume --last "<feedback>"`,
  which keeps Codex's full context — never re-send the whole handoff.
- Do NOT edit the code yourself in this phase. You orchestrate; Codex implements.

## Phase 4 — Deterministic quality gates

Detect what the project actually has (package.json scripts, Makefile, justfile,
pyproject.toml, Cargo.toml, go.mod, CI config) and run the applicable subset, in order:
format check → lint → typecheck → tests → build.

- **Exit codes decide pass/fail. Never trust an agent's claim that "tests pass".**
- On failure: send the failing command + trimmed output back to Codex:
  `codex exec -c approval_policy=never resume --last "Quality gate failed: <command>\n<output>\nFix it."`
  then re-run the gates. **Maximum 2 fix rounds**; if still failing, stop and report to the user
  with the failure output — do not loop further and do not fix it silently yourself.

## Phase 5 — Review (standard/strict; skip for fast)

Spawn a **fresh-context subagent** to review, so the reviewer shares no context with
this session's planning. The subagent must be read-only: instruct it to only use
Read/Grep/Glob/Bash(read-only) and to never edit files. Give it:

- The diff scope: `git diff <base-branch>...HEAD` plus untracked files.
- The acceptance criteria from the handoff doc (not the implementation history).
- Instruction: report only real defects — each finding needs file:line, a one-sentence
  claim, and a **concrete failure scenario** (inputs/state → wrong behavior).
  Style nits and speculative concerns are out of scope.

If there are real findings: send them to Codex via `codex exec -c approval_policy=never resume --last`,
re-run Phase 4 gates, and re-review only the changed areas. **Maximum 2 review rounds.**
Unresolved findings after that: report them to the user; they decide.

**strict only**: additionally run Codex's native reviewer:
```bash
codex exec review --base <base-branch>
```
Merge both reviewers' findings. If the two reviewers disagree on a high-severity
finding, stop and ask the user to arbitrate.

## Phase 6 — Finish

1. Verification before completion: gates green, acceptance criteria met (check each one),
   no stray debug output or leftover scratch files in the repo.
2. Check `git status` for build artifacts (`__pycache__`, `node_modules`, `dist`, caches…)
   before staging — never commit them; add/extend `.gitignore` if the project lacks one.
3. Commit everything to the pair branch with a descriptive message summarizing the change.
4. Report to the user: what was built, diffstat, gate results, review outcome
   (including any accepted-but-unfixed findings).
5. **Do NOT merge, push, or open a PR.** The user decides what happens to the branch.

## Hard human-decision gates

Regardless of profile, if the task turns out to involve any of the following, prepare
the work but STOP and ask before executing that part:

- merging into the main/default branch, or pushing anywhere
- database migrations
- deleting or overwriting user data
- auth, permissions, or payment logic changes
- breaking changes to a public API
- large dependency additions/upgrades

## Notes

- Keep the ceremony proportional: this skill only runs when explicitly invoked.
  Never suggest "we should run /pair for this" on ordinary tasks.
- If `codex exec` errors or hangs twice in a row, stop and show the user the raw output.
