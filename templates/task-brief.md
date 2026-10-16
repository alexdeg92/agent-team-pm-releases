PM here (project manager). Read CLAUDE.md, then <BRIEF path>. In particular read "Team roster" (your role and owned files), "Reporting protocol", "Where we work" and the "Decisions log". The task file is <reports>/<task>-brief.md.

You are **<agent>**. Task <task>: <one-line goal>.
Read first: <docs/contracts and the existing code this extends>. Start the report with a short gap analysis (what exists, what is missing).

## Deliverables
1) <deliverable>
2) <deliverable>

## Design rules (every task)
- **Generic core, specifics at the edge.** No vendor, runtime, user or instance specifics in core or UI code. They go behind an adapter or registry entry, and adding the next one is one new file or data entry.
- **Scale.** It works for 1…N of every plural thing (agents, users, runtimes, items, packs). Say what grows with N (time, bytes, requests) and where the next ceiling is.
- **Open vocabularies.** External names are data, with a label registry and a fallback. Lists in the UI come from the module or registry, never hand-copied.

## Frontend layout (mandatory for any UI, design or frontend task)
Read `references/frontend-layout.md` from the PM skill before you touch any layout. The project copy may be in docs/architecture/layout-frames.md.
- **The document never scrolls.** Each page is a frame: fixed head, bar and foot rows, plus ONE scrolling body. Other scrollers are only for independent panes, with `overscroll-behavior: contain`.
- `min-height: 0` / `minmax(0,1fr)` on every grid or flex ancestor of a scroller.
- The footer is the last grid row, anchored at the bottom with short or long content. Never `fixed` or `sticky` for frame rows.
- One title per page (no hero repeating the topbar). Use the space efficiently. Tabs, filters and selectors stay visible; only the content scrolls.
- **Mobile carries the same weight as desktop:** `dvh`, safe areas, bottom nav as a frame row, no horizontal document scroll.
- **Prove it before reporting.** Run the browser layout test at desktop and mobile sizes, with short and long content, scrolled top and bottom, and include screenshots. A layout the owner has to correct is a failed task.

## Isolation (every task)
- **Work only in** <worktree path> on branch <branch>. Don't edit other checkouts; other agents own them.
- **Never touch the real host state** in tests or dev runs: the home config dirs of any tool, the real network (DNS, public IP, VPNs), external services or production data. Every such probe goes through an injected seam. **Add a test that asserts the seam is stubbed** in the test environment.
- No personal or instance literals (names, hostnames, paths, tokens) in committed files, fixtures or screenshots meant for sharing.
- No services restarted, no production touched, no pushes (the PM integrates).

## Decide, don't stall
Make sensible decisions yourself and record them under "Decisions" in the report. Stop and ask the PM only for: anything touching production, real user data, money or publishing; a contradiction in the brief; or a budget or gate that must move. To ask, send the question to the PM with `prompt-agent`, then continue with whatever isn't blocked.

## Gate before reporting
Run, and paste the counts into the report:
- the targeted tests for every file you touched, **plus the whole test directory of each area you touched**;
- the build, and any generated-file stamps;
- the repo's privacy, portability and budget gates, if any (<commands>);
- `git diff --check`.

For any test you add that waits on a UI or a process, wait on conditions, never on fixed sleeps, and guard reads during reloads. Visual work: headless screenshots at <desktop> and <phone> widths, light and dark, and every angle or state you changed.

**Heavy shared resources** (the full suite, deploys, GPU jobs) run only through `run-exclusive.sh <name> …`, and the full suite is the PM's.

## Team board and inbox (every agent)
- `team inbox` when you start and between steps. Messages there are durable, and herdr nudges only tell you to look.
- Your task is on the board: `team task list --mine`. Move it: `team task set <id> working` → `team task set <id> review --commit <hash> --report <path>`. The reviewers are notified automatically.
- When you're free: `team task claim` takes the best ready task.
- To reach a teammate: `team msg <name> "…"`; to reach everyone: `team msg all "…"`.

## Completion protocol
1. Write `<reports>/<task>.md`: the gap analysis, what was built, decisions, files, tests with exact counts, evidence links, known limits.
2. Commit on your branch (if the brief allows it) and give the hash.
3. Write `<reports>/<task>.status.json`: `{"task":"<task>","agent":"<agent>","state":"done|blocked|failed|needs-decision","report":"<path>","commit":"<hash|null>","summary":"<one line>"}`.
4. Send `herdr agent prompt <pm-name> "<agent>: <one line>. Report: <path>"` (retry after a minute on `agent_blocked`).
5. **To message a teammate:** `herdr agent prompt <name> "<message>"` (the names are in the brief roster; retry after a minute on `agent_blocked`).
6. **Defects in another agent's output:** send them straight to that agent with the evidence path, and copy the PM in one line. Then continue with your next item.
