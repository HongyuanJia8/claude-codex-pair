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
   (changes will get mixed into the new branch) or stop so they can commit/stash first.
4. Note the current branch name — it is the **base branch** for diffs and review.
5. **Record the baseline.** Detect the project's gate commands (see Phase 4) and run them
   *before* handing anything to Codex. Write down, for each: the command, its exit code, and
   the test runner's own count line (`42 passed`, `ok 17`, …). Everything in Phase 4 is judged
   against this baseline, not against zero — otherwise a suite that was already red burns a fix
   round on someone else's debt, and a suite that silently collects no tests looks like success.
   If a runner reports no count, record "count unavailable" and say so in the final report;
   never substitute a guess.

## Phase 1 — Clarify & plan (you, current session)

- If the task is ambiguous in a way that would change what gets built, ask the user
  at most 2–3 questions (AskUserQuestion). If it's clear, ask nothing.
- **standard/strict**: write a short handoff document to a temp file OUTSIDE the repo
  (use the session scratchpad dir, e.g. `<scratchpad>/pair-handoff.md`). Contents:
  - Goal: what to build/change and why (2–5 sentences).
  - Constraints: language/framework conventions, files or areas involved, things NOT to touch.
  - Acceptance criteria: observable behaviors and edge cases, written as things a test could
    assert. Name the **seams** — the public boundaries the new behavior should be tested
    through (the exported function, the HTTP route, the CLI invocation), not the internals
    behind them. Criteria the project cannot observe from outside are not criteria.
  - Pointers: relevant existing files/functions/patterns you found, so Codex doesn't re-explore blindly.
  - **Deliberately DO NOT prescribe the implementation approach** — no step-by-step design,
    no function signatures unless they are an external contract. Let Codex think.
  - End with: "Cover the new behavior with tests, written at the seams named above and
    following the project's existing testing conventions. A test whose expected value is
    recomputed the way the code computes it proves nothing — expected values must be
    independent literals. Do not mock the thing under test.
    Do not modify or delete existing tests to make a command pass. If an existing test now
    fails and you believe the test itself is wrong, stop and say so with your reasoning
    instead of changing it.
    Then run the project's own format/lint/typecheck/test commands and report each one's
    exit code and test count verbatim — do not summarize them as 'passing'.
    Do not commit; leave changes in the working tree. Do not touch anything outside this repository.
    Set up the project's own environment and install its declared dependencies yourself
    (project-local only). Anything system-level — package managers, global installs, sudo,
    new runtimes, containers — is off limits: say what you need and stop instead."
- **fast**: skip the doc; compose a single clear paragraph with the same spirit (goal + acceptance + don't commit).
- **strict only**: show the handoff doc to the user and wait for explicit approval before
  continuing. Include the seam list in what you ask them to approve — testing effort lands
  where the seams say it lands, so an unconfirmed seam is an unmade decision.

## Phase 2 — Branch

```bash
git checkout -b <short-kebab-slug>
```

Name the branch after the task, with no prefix — it is an ordinary feature branch.

Do not use a worktree by default. Only if the user asked to run multiple `/pair` tasks
in parallel, create a worktree per task instead (`git worktree add`).

## Environment & dependencies

The sandbox boundary is also the permission boundary: Codex may write inside the repo and
nowhere else, and since approvals are off it cannot escalate. Three tiers follow from that.

| Tier | What | Who does it |
|---|---|---|
| **1. Project-local** | Creating the project's virtualenv, installing deps already declared in its manifest, fetching modules — anything that writes only inside the repo (`.venv/`, `node_modules/`, in-repo build dirs) | Codex, on its own, no asking |
| **2. Package-manager caches** | The cache dirs those installers write to, which live outside the repo | Codex, via the explicitly granted `--add-dir` roots below |
| **3. System-level** | `brew`/`apt`/system package managers, global installs (`npm i -g`, `pipx`), `sudo`, installing an interpreter or runtime, container runtimes, changing global config, **adding a new heavyweight dependency to the manifest** | **Stop and ask the user** |

Grant the cache roots for the project's ecosystem, and only those — never `$HOME`, never a
config or credential directory:

| Ecosystem | Add |
|---|---|
| Python (uv / pip) | `--add-dir ~/.cache/uv --add-dir ~/Library/Caches/pip` (Linux: `~/.cache/pip`) |
| Node | `--add-dir ~/.npm` |
| Go | `--add-dir ~/go/pkg/mod` |
| Rust | `--add-dir ~/.cargo/registry` |

A writable cache means a poisoned artifact in it would execute on the next install. That is
the accepted cost of not re-downloading the world every task; widening the grant beyond
caches is not.

**Tier 3 is not a quality-gate failure.** If Codex reports a sandbox denial
("operation not permitted"), an externally-managed-environment refusal (PEP 668), or a
blocked `brew`/`sudo`, do not spend a fix round on it and do not work around it. Stop and
tell the user what is needed, why, and the exact command to run; continue with
`codex exec resume --last` once they have done it.

**Codex never runs containers.** The daemon socket is outside the workspace so it is
blocked anyway, but the real reason is that `docker run -v /:/host` is a complete sandbox
escape. If the quality gates need a container (a database for integration tests, say),
you (outside the sandbox) or the user start it before Phase 3; Codex only connects to it.

## Phase 3 — Codex implements

From the repo root:

```bash
codex exec -s workspace-write <cache --add-dir flags> \
  -c approval_policy=never - < <scratchpad>/pair-handoff.md
```

**Always pass `-s workspace-write` explicitly on every `codex exec` in this workflow.**
Since headless runs disable approvals, the sandbox is the only remaining boundary — it must
not be inherited from `~/.codex/config.toml`, where a temporary global `danger-full-access`
would otherwise make `/pair` run unsandboxed and unapproved without any visible signal.
Never use `--dangerously-bypass-approvals-and-sandbox` here.

(fast profile: pass the paragraph as the prompt argument instead of stdin.)

- Run with a generous timeout (10 min). For clearly large tasks, run in background and monitor.
- Codex's session is recorded; later fix rounds use `codex exec resume --last "<feedback>"`,
  which keeps Codex's full context — never re-send the whole handoff.
- Do NOT edit the code yourself in this phase. You orchestrate; Codex implements.

## Committing (applies to Phases 4–6)

**You commit, not Codex.** Codex leaves changes in the working tree; you stage and commit
after checking them. This keeps every commit gated and keeps build artifacts out.

Commit at each checkpoint where the tree is coherent — i.e. **right after the gates go
green** following a Codex turn:

| Checkpoint | Commit |
|---|---|
| Phase 4 gates pass on the initial implementation | one commit for the implementation |
| Phase 5 review round N fixed and gates pass again | one commit per review round |

So a task normally lands 1–3 commits on the branch, forming a readable trail
(what was built → what review round 1 changed → …). The branch is meant to be merged
as-is; do not squash or rewrite it afterwards.

Before every commit:

- Check `git status` for build artifacts (`__pycache__`, `node_modules`, `dist`, caches…)
  — never stage them; add/extend `.gitignore` if the project lacks one.
- Write a descriptive message: what changed and why. For review-round commits, say which
  finding it addresses. Never commit while a gate is red — if the fix rounds are exhausted
  and gates still fail, leave the work uncommitted and report.

## Phase 4 — Deterministic quality gates

Detect what the project actually has (package.json scripts, Makefile, justfile,
pyproject.toml, Cargo.toml, go.mod, CI config) and run the applicable subset, in order:
format check → lint → typecheck → tests → build.

**Exit codes decide pass/fail. Never trust an agent's claim that "tests pass".** That much is
necessary but not sufficient: a green suite proves you did not break what already worked, not
that the new behavior is tested. Three assertions, all against the Preflight baseline:

| Assertion | Fails when |
|---|---|
| **Exit code** | any gate command returns non-zero |
| **Test count** | the count is below baseline, or is zero, or the suite collected nothing (a runner that matches no files can still exit 0) |
| **Test integrity** | the diff weakens the suite — see below |

For test integrity, read `git diff <base-branch> -- <the project's test paths>` yourself before
committing. Treat as a **red gate**, not a style nit:

- a deleted test, or a deleted/loosened assertion in a test that still exists
- an assertion that now recomputes its expected value the way the code does
  (`expect(add(a,b)).toBe(a+b)`) — it passes by construction and can never disagree
- a newly mocked internal collaborator standing between the test and the thing under test
- `skip` / `only` / `xfail` / commented-out cases added to the suite

Any of these means the gate went green by lowering the bar. Send it back as a failure.

- **New behavior with no new test is also a red gate.** If the diff adds behavior and the test
  count did not move, the gates have not verified anything about it.
- On failure: send the failing command + trimmed output back to Codex:
  `codex exec -s workspace-write <cache --add-dir flags> -c approval_policy=never resume --last "Quality gate failed: <command>\n<output>\nFix the code — do not change the tests."`
  then re-run the gates. **Maximum 2 fix rounds**; if still failing, stop and report to the user
  with the failure output — do not loop further and do not fix it silently yourself.
- Gate-fix rounds do not get their own commits; they fold into the checkpoint commit below.
- **strict only — confirm the new tests can fail.** A test that has never been red may assert
  nothing. Stash the non-test part of the change (`git stash push -- <source paths>`), re-run
  the suite, and check the new tests now fail; `git stash pop` afterwards. A new test that
  still passes without the implementation is a red gate.
- **Once all three assertions hold, commit the implementation** (see Committing above).
- Report every assertion's outcome, including any you could not evaluate (a runner with no
  count, a project with no test paths). Never let an unavailable check read as a passing one.

## Phase 5 — Review (standard/strict; skip for fast)

Spawn a **fresh-context subagent** to review, so the reviewer shares no context with
this session's planning. The subagent must be read-only: instruct it to only use
Read/Grep/Glob/Bash(read-only) and to never edit files. Give it:

- The diff scope: `git diff <base-branch>...HEAD` plus untracked files.
- The acceptance criteria and seams from the handoff doc (not the implementation history).
- Instruction: report only real defects — each finding needs file:line, a one-sentence
  claim, and a **concrete failure scenario** (inputs/state → wrong behavior).
  Style nits and speculative concerns are out of scope.
- Instruction: judge the tests as well as the code, and treat a bad test as a defect in its
  own right. Specifically — does each acceptance criterion have a test that would actually
  fail if the behavior regressed? Is any test tautological (expected value recomputed the way
  the code computes it), coupled to internals rather than the named seam, or passing only
  because a collaborator was mocked out? Did the diff weaken the existing suite?

If there are real findings: send them to Codex via `codex exec -s workspace-write <cache --add-dir flags> -c approval_policy=never resume --last`,
re-run Phase 4 gates, and re-review only the changed areas. **Maximum 2 review rounds.**
Commit each round once its gates are green, with a message naming the findings it fixes.
Unresolved findings after that: report them to the user; they decide.

**strict only**: additionally run Codex's native reviewer:
```bash
codex exec -s read-only -c approval_policy=never review --base <base-branch>
```
Merge both reviewers' findings. If the two reviewers disagree on a high-severity
finding, stop and ask the user to arbitrate.

## Phase 6 — Finish

1. Verification before completion: gates green, acceptance criteria met (check each one),
   no stray debug output or leftover scratch files in the repo.
2. `git status` must be clean — everything from the checkpoints above is already committed.
   If anything is left over, decide whether it belongs in the change (commit it, gates first)
   or is junk (remove it); never leave the tree dirty without saying so.
3. Report to the user: what was built, the commits on the branch (`git log --oneline <base>..HEAD`),
   diffstat, gate results, review outcome (including any accepted-but-unfixed findings).
4. **Do NOT merge, push, or open a PR.** The user decides what happens to the branch.

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
