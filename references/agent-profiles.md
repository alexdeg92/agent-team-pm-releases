# Agent profiles: strengths, weaknesses, best roles

These are **heuristics, not facts.** Models and CLIs change every few months. Confirm them on the machine with `discover-agents.sh` and, for any agent you'll rely on heavily, a 5-minute **calibration task** (see the end of this file). Update this file when you learn something.

## Known profiles

### Claude Code (`claude`, Anthropic)
- **Strengths:**
  - long multi-step engineering with careful reading of an existing codebase;
  - architecture and specs;
  - refactors that keep behaviour, proven with characterisation tests;
  - precise writing (docs, briefs, UI copy);
  - follows a written brief and protocol reliably;
  - good at self-verification (tests, headless-browser screenshots);
  - good judgment about privacy and safety.
- **Weaknesses:**
  - no native image generation;
  - can over-report ("no S(n+1) code in the tree") when it starts the next step early, so verify;
  - long sessions eventually compact context.
- **Best roles:** architect/backend lead, frontend lead, spec writer, the PM itself, careful refactors, anything with privacy-sensitive data handling.

### Codex CLI (`codex`, OpenAI)
- **Strengths:**
  - **image generation** (the imagegen skill, when `image_generation` is enabled): logos, characters, illustrations, sprites; it can also post-process them with PIL or ImageMagick (rectification, trimming, anchors);
  - meticulous, adversarial **code review** that finds real bugs, with reproductions and file:line references;
  - honest about its limits ("not grid-perfect");
  - strong at self-contained algorithmic or numeric work.
- **Weaknesses:**
  - refuses slash commands while working (rename only when idle; two Enters);
  - very literal about tool-routing rules, so it may ask for explicit authorisation (e.g. "use PIL for production edits");
  - in its sandboxed mode it can't write outside the workdir on some hosts (bubblewrap namespaces), so use bypass mode in a trusted worktree;
  - **provider stops look like silent idling** ("Selected model is at capacity"): re-prompt "resume" once, then restart it with `-m <other model>`, or reassign;
  - it can **self-update and exit** on start, so check the pane after spawning;
  - it reports finished turns as `done` (not `idle`), so normalize statuses;
  - long sessions compact, and prompts sent during a compaction return `agent_blocked`, so use `prompt-agent.sh`;
  - it can write tests that read real host state (network, home dirs) unless the brief forbids it and requires a "stubbed" assertion.
- **Art caveat:** layered or overlay art (accessories, clothing) must be generated ON each target pose and then split into back and front layers using head and body landmarks. A single overlay scaled across poses floats or covers the face.
- **Best roles:** `artist` (all generated art), `reviewer` (independent QA, read-only), algorithmic modules, a second opinion on risky designs.

### Cursor agent (`cursor-agent` / `agent`)
- **Strengths:** a fast, competent implementer for **isolated modules** with a clear interface and tests; it brings a different model and perspective from Claude and Codex; it can pick the model per task (`--model`).
- **Weaknesses:**
  - its session is renamed with `/rename <name>` (one Enter);
  - less established in long protocol-heavy collaborations, so give tighter briefs, a small scope and explicit file ownership;
  - verify its reports closely.
- **Best roles:** a domain-module owner behind a contract (e.g. a "projects" backend module with an in-memory repository and tests), utilities, migrations of self-contained code.

### Gemini CLI (`gemini`, Google)
- **Strengths:** a very large context window, good for **reading huge codebases or logs in one go**, cross-file audits, docs synthesis and multimodal input (screenshots, PDFs).
- **Weaknesses:** usually weaker than Claude or Codex at long, careful edit sequences; verify its edits.
- **Best roles:** codebase cartographer or auditor, log and incident analysis, documentation, a second reviewer.

### Others herdr can start (opencode, copilot, amp, qwen, kimi, kiro, droid, cline, goose, aider, …)
- Treat each as **unknown until calibrated.** Many wrap a model you can choose, so the profile depends on the model.
- **Good first uses:** small isolated tasks (test writing, lint fixes, docs) with strict file ownership, or a parallel reviewer.
- **Never** give an uncalibrated agent the critical path, secrets-adjacent work or production access.

## How to allocate work
1. **Split the project into phases**, each with a clear deliverable and acceptance test (spec → foundations → vertical slices → hardening → cut-over). Inside a phase, split into **portions owned by directory or contract**, so agents can work in parallel without touching each other's files.
2. **Score each portion** on what it needs: image generation, a huge reading load, long careful refactoring, an isolated module, adversarial review, UI and visual judgment, privacy sensitivity.
3. **Match** each portion to the agent whose strengths cover its needs:
   - if a portion **needs** a capability only one agent has (e.g. image generation), that decides it;
   - put the **critical path** on the most reliable agent;
   - put **independent modules** on secondary agents;
   - always have **review** done by a different agent (ideally a different vendor) from the implementer.
4. **Plan for parallelism:** start the work that isn't blocked (art, specs, isolated modules, UI on mocks) while the critical path runs; keep contracts (API docs, schemas) as the hand-off points.
5. **Re-plan at each phase boundary,** using what the reports and reviews taught you about each agent.
6. **Name a fallback for each portion:** another agent kind or model that takes it over when the provider stops (capacity, quota, auth). A team that depends on one provider stalls when that provider does.

## Calibration task (5–10 minutes, read-only or scratch-only)
Give the candidate a small task from the real project in a scratch copy (e.g. "write tests for function X and report"). Score it on:
- did it follow the brief and the reporting protocol;
- were its claims accurate (test counts, files touched);
- did it stay inside its files;
- how good is the output;
- how fast was it.

Record the result in the brief's decisions log, then assign it to the role that fits.

## Model and effort per task class
Choose per portion, not per agent. Check with `scripts/agent-usage.py`.

| Task class | Model tier | Effort | Why |
|---|---|---|---|
| Architecture, security and critic reviews, the critical-path backend | top | high | Mistakes are expensive and compound. |
| Creative or visual production (art, UI design) | top, image-capable | high | Quality is the deliverable. |
| Integration across many files, migrations | top | medium–high | Breadth more than depth. |
| Mechanical work: renames, relays, copying, formatting, regenerating goldens, status checks | mid or small | low–medium | High effort is wasted reasoning here. |
| Exploration and inventories (find X across the repo) | small or fast | low | Read-heavy, little judgement. |

Rules of thumb:
- If reasoning tokens run far above visible output on simple tasks, lower the effort.
- If a mid-tier agent produces rework on a critical task, raise the effort or the tier.
- Long sessions cost more per call than fresh ones: hand finished agents their next unrelated task in a new session.
