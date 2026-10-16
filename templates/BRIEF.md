# <Project> — shared brief (single source of truth for every agent)

If you need to change a decision, say so in your report to <pm-name>. Don't diverge silently.

Set `<pm-name>` to the actual registered PM name (`pm` or `pm-<project>`) throughout this brief; reports must reach this team.

## Reporting protocol (mandatory)
- **The PM (agent `<pm-name>`) is the project manager.** The user doesn't read your pane, so never address them.
- **When you finish a task or a batch, or you're blocked:**
  1. write `<area>/reports/<agent>-NN.md` with what you did, the files changed, the **exact test counts and tree state at this moment**, what you could not do, and your questions;
  2. run `herdr agent prompt <pm-name> "<agent>: <one-line summary>. Report: <path>"`.
- **Questions go to <pm-name> the same way.** While you wait, continue with anything that doesn't depend on the answer.
- **The PM replies in your pane.** PM instructions override earlier ones, but never the Hard rules.

## Team roster (agent name = role; all run in no-approval mode)
| agent | tool | role | owns (may edit) |
| --- | --- | --- | --- |
| `<pm-name>` | Claude | coordination, decisions, reviews, snapshots, staging, git | this brief |
| `architect` | Claude | backend architecture + implementation | `src/**`, `test/**`, `docs/architecture/**` |
| `frontend` | Cursor | UI | `public/**`, `test/frontend/**` |
| `reviewer` | Codex | independent QA; never edits code | `<area>/reports/review-*.md` |

Cross-area changes: ask the owner through pm. Contracts between areas live in `docs/architecture/*.md`.

## Where we work
- **Worktree:** `<path>`, branch `<branch>`. Never touch the production checkout `<path>`.
- **Test instance:** `<service>` runs a **frozen snapshot** taken by the PM after tests pass in it, at `<url>`. If it shares real backends, it is read-only. Only the PM restarts it.
- **Tests must pass from any checkout path.**

## Hard rules
- **Never read, print or commit secrets** (env files, tokens, keys). Treat the repo as shareable.
- **Never run anything against live production systems** unless a PM task says so explicitly.
- **No commits:** the PM handles git.
- **Language for user-facing text:** <language>.
- **Stay inside the files you own.**

## Decisions log
- <date>: <decision> (PM, on <report>)

## Quality checklist
- Exact test counts in every report.
- Visual work is checked in a headless browser at desktop and phone width, in light and dark, with screenshots in the report.
- No PII or real ids in fixtures, samples or reports.
