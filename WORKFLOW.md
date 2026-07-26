# The /pair Dual-Agent Workflow — Design Doc

> Claude Code plans and reviews, Codex implements, git is automated. Off by default; runs only when explicitly invoked.

## Design principles

1. **Invocation is the switch.** No resident framework, no change to default behavior. The skills run only when you type `/pair` / `/pair-review`; ordinary conversations carry zero overhead.
2. **Context isolation.** The implementer (Codex) and the reviewer (a fresh-context Claude subagent) share no conversation history. The reviewer is read-only and cannot "helpfully" edit code.
3. **Deterministic quality gates.** Format / lint / typecheck / test are judged by script exit codes — never by an agent claiming "tests pass".
4. **Don't constrain the base model.** The handoff document given to Codex states goals, constraints, acceptance criteria, and pointers to relevant files — deliberately not the implementation approach.
5. **Bounded loops.** Fix–gate cycles cap at 2 rounds, review–fix cycles cap at 2 rounds; at the cap the workflow stops and reports instead of spinning forever.

## The bridge (no manual context copying)

- Claude Code invokes Codex headlessly from within the session:
  `codex exec -s workspace-write -c approval_policy=never - < handoff.md` — the handoff travels via stdin and never pollutes the project directory.
- **The sandbox is pinned on the command line, never inherited.** Headless runs disable
  approvals, so the sandbox is the only remaining boundary; passing `-s` explicitly keeps a
  temporarily laxer `~/.codex/config.toml` (e.g. a global `danger-full-access`) from silently
  widening what `/pair` can do. Review invocations pin `-s read-only`.
- Fix rounds use `codex exec resume --last "<feedback>"` — Codex keeps its full implementation context, so only incremental feedback is sent.
- Codex's output returns to Claude Code through `git diff`; review, quality gates, and the commit are all automated.

## Usage

| Command | When | Flow |
|---|---|---|
| *(nothing)* | Small edits, questions | Normal chat; the workflow doesn't exist |
| `/pair fast <task>` | Small task, but let Codex do it | One-paragraph instruction → Codex → gates → commit |
| `/pair <task>` | Medium feature (default: standard) | Clarify → handoff doc → branch → Codex → gates → read-only Claude review (≤2 fix rounds) → commit |
| `/pair strict <task>` | High-risk / complex change | Standard + human plan approval + dual review (Claude subagent and `codex exec review`); stops to ask on high-severity disagreement |
| `/pair-review` | Just a second pair of eyes | Fresh read-only subagent reviews uncommitted changes; add `codex` to also run Codex's native review, `base <branch>` to review a branch diff |

Merging, pushing, and opening PRs are always your call — the workflow only commits to `pair/*` feature branches.

## Hard human-decision gates

Regardless of profile, the workflow stops and asks before:

- merging into the main branch, or pushing anywhere
- database migrations
- deleting or overwriting user data
- auth, permissions, or payment logic
- breaking changes to a public API
- large dependency additions/upgrades

## Trade-offs vs. community frameworks

- **Superpowers**: not installed. Four ideas were borrowed — a lightweight brainstorm before planning (at most 2–3 questions, and only when the task is ambiguous), the handoff plan as the inter-agent artifact, verification-before-completion, and capped fix/review loops. Its heavyweight defaults — full ceremony for every micro-task, mandatory TDD, a fresh subagent per task — were not adopted.
- **OpenSpec / Spec Kit**: neither installed. The strict-profile handoff doc already serves as a lightweight spec shared by both agents. Spec Kit can be re-evaluated if a large greenfield project ever calls for it.

## Optional extensions (add when needed)

- **Auto Draft PR**: with `gh` CLI installed and authenticated, Phase 6 can add `gh pr create --draft`.
- **Reverse direction**: add a custom command under `~/.codex/prompts/` so that Codex TUI can call `claude -p` for a review with one command — useful on Codex-first workdays.
- **Parallel tasks**: when running multiple `/pair` tasks at once, switch to `git worktree` so each task gets an isolated directory.

## File locations

- `~/.claude/skills/pair/SKILL.md` — main workflow
- `~/.claude/skills/pair-review/SKILL.md` — standalone cross-review
- `~/.claude/skills/pair/WORKFLOW.md` — this document
