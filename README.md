# claude-codex-pair

A lightweight, **opt-in** dual-agent development workflow for [Claude Code](https://claude.com/claude-code) + [Codex CLI](https://github.com/openai/codex):

> **Claude Code plans and reviews. Codex implements. Git is automated. You decide what merges.**

No frameworks, no mandatory state machine, no context copy-pasting between terminals. The whole workflow is two slash commands that do nothing until you explicitly invoke them.

See [WORKFLOW.md](WORKFLOW.md) for the full design doc.

## How it works

```
you: /pair <task>
 │
 ▼
Claude Code — clarifies (only if ambiguous), writes a short handoff:
              goal + constraints + acceptance criteria. No implementation details.
 │
 ▼
git checkout -b pair/<slug>
 │
 ▼
Codex implements headlessly:
              codex exec -s workspace-write -c approval_policy=never - < handoff.md
 │
 ▼
Deterministic quality gates:  format → lint → typecheck → test
              (exit codes decide — an agent's "tests pass" is never trusted)
 │  fail → codex exec resume --last "<failure output>"   (max 2 rounds)
 ▼
Fresh-context, read-only Claude subagent reviews the diff
 │  findings → codex exec resume --last "<findings>"     (max 2 rounds)
 ▼
Auto-commit to the pair/* branch → report to you.
Merge / push / PR: always your call.
```

Key mechanics:

- **No manual context shuttling** — the handoff goes to Codex via stdin; fix rounds use `codex exec resume --last`, which keeps Codex's full session context so only incremental feedback is sent.
- **Implementer/reviewer isolation** — the reviewer is a fresh subagent with read-only tools; it shares no conversation history with the planner and cannot "helpfully" edit code.
- **Bounded loops** — fix/review cycles cap at 2 rounds each, then stop and report.
- **Human gates** — merges, migrations, data deletion, auth/payment logic, and breaking API changes always stop and ask, regardless of profile.

## Commands

| Command | When | What runs |
|---|---|---|
| *(nothing)* | Small edits, questions | Normal Claude Code / Codex chat — the workflow doesn't exist until invoked |
| `/pair fast <task>` | Small task, but let Codex do it | One-paragraph instruction → Codex → gates → commit |
| `/pair <task>` | Medium feature (default: standard) | Handoff doc → branch → Codex → gates → read-only review loop → commit |
| `/pair strict <task>` | Risky / complex change | Standard + human plan approval + dual review (Claude subagent **and** `codex exec review`) |
| `/pair-review` | Just want a second pair of eyes | Fresh read-only subagent reviews uncommitted changes; add `codex` to also run Codex's native review, `base <branch>` to review a branch diff |

## Install

Requirements: Claude Code CLI, Codex CLI, git. (`gh` optional, only for the auto-PR extension.)

```bash
./install.sh          # copies skills/ into ~/.claude/skills/
```

Or manually:

```bash
cp -R skills/pair skills/pair-review ~/.claude/skills/
```

Then `/pair` and `/pair-review` are available in every project. Installing changes nothing about normal usage — the skills explicitly refuse to auto-activate and only run when you type the command.

## License

[MIT](LICENSE)
