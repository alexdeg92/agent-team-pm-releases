# Failure modes of an agent team, and how to handle each

These are recurring failure classes observed running teams of 5–8 agents (Codex, Claude, Cursor) over multi-day projects. They are **runtime-agnostic**: each class shows up in every agent CLI, under different words. Detection is by **signal**, not by agent kind. The kind-specific strings live in `error-patterns.tsv`, one line per pattern, so supporting a new agent CLI is a data change, not a code change.

`scripts/team-watch.sh` detects classes 1–5 automatically. The rest are prevented by the brief and the PM's checks.

| # | Class | Typical signal | Response |
|---|---|---|---|
| 1 | **Provider-side stop**: capacity, overload, rate limit, quota, expired auth | The agent goes idle mid-task; the pane says "at capacity", "overloaded", "429", "rate limit", "quota", "please log in" | Re-prompt "resume <task>" once. If it repeats, switch the model (`-m`) or reassign the portion to another kind. Auth needs the user: `! <cli> login`. |
| 1b | **Provider policy stop**: the provider's safety filter blocks a legitimate task (e.g. security proofs) | The pane says "can't be shown", "we take extra care with some cybersecurity requests", "content policy" | Don't rephrase to get around it. Reassign that portion to a provider whose policy allows authorized defensive work, keeping the same charter and scope, or ask the user to enrol in the provider's trusted-access program. Pick the security reviewer's provider with this in mind. |
| 2 | **Silent stop**: finished, crashed or asked a question without reporting | The status is idle or done, with no new report or status file | Read the last 40 lines of the pane. If it's a question, answer it with a decision. If the work is finished, ask for the report. |
| 3 | **Prompt not delivered**: the agent is blocked, compacting or busy | The prompt call returns `agent_blocked`, or the text sits in the input box | `scripts/prompt-agent.sh` retries until delivered and verifies. Never fire and forget. |
| 4 | **Stall**: working, but no progress | The pane text is unchanged for N minutes while the status says working | Read the pane. A long test or image job is fine; a hung command means asking the agent to kill it and continue. |
| 5a | **PM unreachable**: the PM pane lost its name from the brief (reboot, resume) | Agents report `agent_not_found` for `pm`, and reports pile up unseen | team-watch emits `NOPM`; resolve `herdr pane current`, then restore the name from the brief (`pm` or `pm-<project>`); set `PM_NAME` for the watcher. Check after every move or resume. |
| 5 | **Process gone**: self-update exit, crash, reboot | The agent is missing from the list, the pane is at a shell prompt, or `agent_not_found` | Resume the session (SKILL §9). Resolve by pane title when the name was lost. |
| 6 | **Shared-tree contention**: two agents (or the PM's test run) in one checkout | Unrelated diffs in a report, or tests that fail because of the other agent's half-done files | **One worktree and branch per task.** One integrator merges. The PM's full suite runs on a committed or frozen tree. |
| 7 | **Late integration failure**: green targeted tests, red full suite | The full suite fails on goldens, i18n, export, budgets, or a race in a new test | The brief lists a **pre-report gate** (affected test dirs, build, privacy/portability gates). The PM's triage: rerun each failure alone 3×, which tells a flake from a real failure; fix flakes at the root (wait on conditions, not timing). |
| 8 | **Environment leak**: a test or dev run touched the real host | Real hostnames, home paths, user names or tokens in output or screenshots | The brief forbids real host probes. Every probe of a home dir, the network or an external service goes through an injected seam, and **a test asserts the seam is stubbed**. The PM greps evidence for known real values before accepting. |
| 9 | **Confident wrong conclusion**: "X isn't available", "can't be done" | A negative finding with no exhaustive evidence | Ask for the evidence (the exact calls and fields inspected), or give a second agent an independent look. Never relay a negative to the user unverified. |
| 10 | **Budget or gate collision**: a delivery exceeds a ceiling the team set | The report says "blocked by budget X" | This is a PM decision. Decide from the scale model (what N items will cost), record the rationale next to the constant, and plan the structural fix for when it's outgrown. |
| 11 | **PM bottleneck**: every defect relayed through the PM | A consumer finds a producer defect and waits | The consumer files it directly with the producer: `prompt-agent.sh <producer> "<defect + evidence path>"`, then a one-line note to the PM. The PM arbitrates only disagreements. |
| 11b | **Duplicate fix**: two agents fix the same breakage | A notice about a merge or failure makes every agent that sees the failing test fix it | When announcing a failure or merge, **name the single owner** of the follow-up and say "others: don't fix, report". Agents fix only files they own. |
| 12 | **Bad instructions to the user**: placeholders, wrong shell, wrong prefix | The user pastes a literal `<code>` or `!` into the wrong place | Give only complete, runnable commands. Say where each one runs (this session via `!`, or their own terminal). Never include placeholders the user must edit. |
| 13 | **Visual regressions that pass tests**: overlap, invisible effects, emoji-like props | Screenshots look wrong at real zoom | The PM inspects the real renderer at 2× for every visual delivery: front and rear angles, the smallest supported width, day and night. |

## Status semantics (normalize them before acting)
Agent CLIs report their state differently: herdr shows `working`, `idle`, `done` and `blocked`. Treat `idle` and `done` alike, as **"not working"**. A loop that waits for one exact word misses the other. Treat `blocked` as one of three things:
- (a) waiting on an approval or question: read the pane;
- (b) compacting or a queued prompt: wait and retry;
- (c) a provider error: class 1.

**The completion signal is the status file** (`<reports>/<task>.status.json`), not the terminal state.

## Scale notes
- The watcher is O(agents) per tick and keeps its state in a per-session directory. 20 agents cost the same per-agent work as 2.
- Patterns are data (`error-patterns.tsv`), so a new agent kind needs no new code.
- One heavy shared resource (the full test suite, a GPU, a deploy) is guarded by `scripts/run-exclusive.sh`. Agents and the PM queue on the same lock instead of colliding.
- Past roughly 8 agents, add a second integrator per subsystem rather than routing everything through one PM.

## Startup and provider handoffs
- **Codex self-update:** on `agent_not_ready`, inspect the visible pane. If it says "Updating Codex via npm…" or "Update ran successfully! Please restart Codex.", wait for the shell and start once more in that same pane. Never restart into a running TUI; it would receive the shell command as prompt text.
- **Codex folder trust (0.163+):** on "Trust this folder?", verify the foreground directory is the worktree the PM chose, then press Enter once for "1. Trust and continue". Wait for the composer before `/rename`; otherwise rename keystrokes land on the trust dialog. Stop on a directory mismatch.
- **Cursor title unset:** if `/rename` stays in the prompt bar, press Enter once more and re-check the session title. Stop after that retry so startup cannot submit unintended text repeatedly.
- **Provider handoff:** request a file containing state, findings, working commands and next steps, with no commit; wait for it, close the old pane, then send the original brief plus handoff to the replacement vendor. This preserves unfinished work without spending the exhausted provider's window.
