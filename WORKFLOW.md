# The /pair Dual-Agent Workflow — Design Doc

> Claude Code plans and reviews, Codex implements, git is automated. Off by default; runs only when explicitly invoked.

## Design principles

1. **Invocation is the switch.** No resident framework, no change to default behavior. The skills run only when you type `/pair` / `/pair-review`; ordinary conversations carry zero overhead.
2. **Context isolation.** The implementer (Codex) and the reviewer (a fresh-context Claude subagent) share no conversation history. The reviewer is read-only and cannot "helpfully" edit code.
3. **Deterministic quality gates.** Format / lint / typecheck / test are judged by script exit codes — never by an agent claiming "tests pass". Exit codes alone only prove nothing already-working broke, so the gate also asserts the test count did not fall below the pre-handoff baseline and that the diff did not weaken the suite (see below).
4. **Don't constrain the base model.** The handoff document given to Codex states goals, constraints, acceptance criteria, and pointers to relevant files — deliberately not the implementation approach.
5. **Bounded loops.** Fix–gate cycles cap at 2 rounds, review–fix cycles cap at 2 rounds; at the cap the workflow stops and reports instead of spinning forever.
6. **A commit per gated step.** Claude Code commits — never Codex — each time the quality gates go green: one commit for the implementation, one per review round. Gate-fix rounds fold into the following checkpoint, so no commit is ever made while a gate is red. The branch carries a readable trail (what was built → what each review round changed) and is meant to be merged as-is, with no squashing or history rewriting. Committing stays with the orchestrator because that is where the artifact/`.gitignore` check and the gate results live; Codex is told to leave its changes in the working tree.

## The bridge (no manual context copying)

- Claude Code invokes Codex headlessly from within the session:
  `codex exec -s workspace-write -c approval_policy=never - < handoff.md` — the handoff travels via stdin and never pollutes the project directory.
- **The sandbox is pinned on the command line, never inherited.** Headless runs disable
  approvals, so the sandbox is the only remaining boundary; passing `-s` explicitly keeps a
  temporarily laxer `~/.codex/config.toml` (e.g. a global `danger-full-access`) from silently
  widening what `/pair` can do. Review invocations pin `-s read-only`.
- Fix rounds use `codex exec resume --last "<feedback>"` — Codex keeps its full implementation context, so only incremental feedback is sent.
- Codex's output returns to Claude Code through `git diff`; review, quality gates, and the commits are all automated.

## Environment & dependencies

The sandbox boundary turns out to be exactly the right permission boundary, so the policy needs no new enforcement mechanism — only a written rule so the implementer knows where the line is and a denial gets read as "this needs a human" rather than "the tool is flaky":

- **Project-local setup is self-service.** Creating the virtualenv, installing declared dependencies, fetching modules — these write only inside the repo, which is precisely what `workspace-write` allows.
- **Package-manager caches are granted explicitly.** They live outside the repo (`~/.cache/uv`, `~/.npm`, …), so the sandbox denies them by default and installs fail with an opaque error. Each `codex exec` grants the cache roots for the project's ecosystem via `--add-dir` — those directories only, never `$HOME`, never config or credential directories. A writable cache is real attack surface (a poisoned artifact executes on the next install); it is the accepted cost of not re-downloading everything each task.
- **System-level installs stop and ask.** Package managers, global installs, `sudo`, new interpreters or runtimes, container runtimes. The sandbox denies these and approvals are off, so they cannot be escalated — the workflow reports what is needed and the exact command, and resumes after the user has run it. This is not a quality-gate failure and does not consume a fix round.
- **Containers are never driven by the implementer.** Beyond the socket living outside the workspace, `docker run -v /:/host` is a complete sandbox escape; granting an agent container access cancels the sandbox. If the gates need a service, the orchestrator or the user starts it beforehand.

One known tension: dependency installation needs the network, so `sandbox_workspace_write.network_access` stays enabled for implementation. Review invocations, which never install anything, run under `-s read-only`.

## What the gates actually prove

A green test suite is evidence that nothing which used to work is broken. It is not evidence
that the new behavior is tested — a change no test touches leaves the suite green. Worse, the
instruction "make the tests pass" given to an agent with write access to the tests has an
obvious cheap solution: change the tests. So the gate is three assertions, not one:

1. **Exit codes** — every applicable gate command returns zero.
2. **Test count** — at or above the baseline recorded *before* the handoff, and non-zero. A
   runner that matches no files still exits 0; without a baseline that reads as success, and a
   pre-existing red suite burns a fix round on debt that was never ours.
3. **Test integrity** — the diff of the project's test paths is read before committing. A
   deleted test, a loosened assertion, a newly mocked-out collaborator, an added `skip`, or an
   expected value recomputed the way the code computes it are all red gates, not style nits.
   New behavior with a flat test count is likewise red.

The handoff asks for tests at named **seams** — the public boundaries the behavior is observed
through — because testing effort has to land somewhere deliberate, and a seam agreed up front
is the only version of that decision anyone can check later. The strict profile adds one more
step: stash the implementation, confirm the new tests actually fail without it, restore. A test
that has never been red may be asserting nothing.

Checks that cannot be evaluated (a runner that reports no count, a project with no test paths)
are reported as unavailable. An unavailable check must never read as a passing one.

## Usage

| Command | When | Flow |
|---|---|---|
| *(nothing)* | Small edits, questions | Normal chat; the workflow doesn't exist |
| `/pair fast <task>` | Small task, but let Codex do it | One-paragraph instruction → Codex → gates → commit |
| `/pair <task>` | Medium feature (default: standard) | Clarify → handoff doc → branch → Codex → gates → commit → read-only Claude review (≤2 fix rounds, commit per round) |
| `/pair strict <task>` | High-risk / complex change | Standard + human plan approval + dual review (Claude subagent and `codex exec review`); stops to ask on high-severity disagreement |
| `/pair-review` | Just a second pair of eyes | Fresh read-only subagent reviews uncommitted changes; add `codex` to also run Codex's native review, `base <branch>` to review a branch diff |

Merging, pushing, and opening PRs are always your call — the workflow only commits to the feature branch it created (named after the task, no prefix).

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
