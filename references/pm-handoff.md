# Transfer the PM role across vendors

Use this procedure before the PM's provider runs out of allowance, such as Claude reaching 97% of its weekly limit. Pick an installed, authenticated vendor with enough headroom for coordination. Moving builders alone does not preserve the PM's ability to finish the project.

## Write PM-HANDOFF.md first

Put `PM-HANDOFF.md` in the project's reports directory, accessible to the replacement. Include:

- **State:** project and worktree paths, branches and exact HEADs, dirty files, live roster and pane ids, report and evidence paths, completed work and checks still pending.
- **Coordination:** the exact PM reporting name, workspace id, team root, watcher PID/state directory and settings, active board claims, pending inbox messages and who owns integration.
- **Approved decisions:** the user's scope, release/privacy constraints, approvals and their source. Distinguish user approval from teammate recommendations and drafts.
- **Remaining chain:** ordered tasks and dependencies, owners, acceptance checks and next action. For every approved PR still to open, copy the exact approved title and body verbatim; include its branch and commit. Carry any limits on opening, merging or publishing alongside it. Do not paraphrase approvals or turn draft text into approved text.
- **Open choices:** blockers and questions awaiting the user, provider usage, the chosen replacement vendor and its checked headroom.

Finish writing before renaming or starting the replacement. Keep the file in the private reports area; it may contain operational details that must not enter a public package.

## Move the reporting name, then verify delivery

1. Read `herdr agent list` and record the **exact name** and outgoing pane. If your pane moved, use `herdr pane current`; inherited pane ids may be stale. Choose an unused retired name for the outgoing PM.
2. Rename the outgoing herdr agent with `herdr agent rename <outgoing-pane> <retired-name>`. Re-read the live list: the retired name must point to the outgoing pane, and the original reporting name must be free. Stop on a mismatch. Terminal titles do not establish ownership of a name. Before spawning, register the outgoing agent under its retired name with `scripts/team member register <retired-name> --role pm --runtime <outgoing-kind>` and set the spawner's `TEAM_AGENT` to that retired name, so the replacement is not recorded as its own parent.
3. Start the replacement through `scripts/spawn-agent.sh` with `--role pm`, the **same original reporting name**, the other vendor's `--kind`, the chosen project directory and workspace. Record its returned pane id.
4. Re-read the live list and check that the exact original PM name maps to the returned **new pane**, distinct from the retired pane. Keep the same `PM_NAME`, briefs, inbox address and teammate reporting instructions. Set the replacement's `TEAM_AGENT` to that original reporting name and give it the same team root.
5. Send the **first prompt** with `scripts/prompt-agent.sh <original-pm-name> "Read <absolute-handoff-path>. Acknowledge the handoff and restate the remaining chain and approval limits before acting."` Compare the printed delivery pane with the new pane. A title-fallback warning or a different pane means verification failed: correct the live registration before continuing.
6. Read the acknowledgement in the **new pane** and confirm the replacement understood the state, exact approved PR texts and next action. A successful prompt response from herdr proves delivery only; it does not prove the replacement read the handoff.
7. Transfer watcher and board ownership explicitly. Keep exactly one watcher; preserve its state and configuration when restarting it. The outgoing PM stops coordinating once the replacement acknowledges, and the replacement becomes the sole active PM. Retire or close the old pane after takeover is confirmed.

If startup or verification fails, keep the handoff file and the recorded pane ids. Repair the registration or return the reporting name to the outgoing PM before resuming coordination; never allow both PMs to act as owner.
