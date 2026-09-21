---
description: Check whether this repository is ready for /ship — installed files, pipeline.env, the git remote and branches, host enforcement, hooks, workflows and the tracker workspace. Read-only; fixes only what the owner approves.
argument-hint: [--offline] [--with-tests]
---
1. If `scripts/pipeline/doctor.sh` is missing, the pipeline is not installed or predates the doctor: tell the owner to run `/pipeline-init`, and stop.
2. Run `bash scripts/pipeline/doctor.sh $ARGUMENTS` from the repository root. It changes nothing. Add `--with-tests` only when the owner asked for it or the tooling was just updated: the suite is slow.
3. **Tracker** (the `TODO` lines; the list lives in `scripts/pipeline/tracker-schema.txt`). Use the tracker connector tools in this session:
   - First make one harmless read call, such as listing the teams or reading the team named by `TRACKER_TEAM_KEY`, and report whether it answered. Connector tool names can be opaque, so this call is the only proof that the connector works. If there is no connector or the call fails, report it as a FAIL and skip the rest of this step.
   - Compare the workspace with every `TODO` line: the team, both label groups and their labels, the kind labels, and each workflow status. A label group must be single-select (a Linear label group, or a single-select field in Jira), so a ticket carries one `Stage` and one `Owner` at a time.
   - List what is missing and offer to create it, naming each item. Labels and statuses belong to a shared workspace, so create nothing until the owner says yes in this conversation, and create only what they approved. If the connector cannot create an item (workflow statuses often need the tracker's settings screen), give the owner the exact steps.
4. **Everything else is advice.** For each `WARN` and `FAIL`, say what to do and who does it. Only the owner does these: pushes of unrelated history or force pushes, creating the base or staging branch on the host, branch protection or rulesets, repository variables, environments and secrets. Tooling files are refreshed with `/pipeline-init`. A finding marked `[upgrade: …]` means the install predates v1.1.0 and a project-owned file (`pipeline.env` or a workflow) needs a change; `/pipeline-init` shows each change as a diff and applies only what the owner approves.

Reply with only:
- Ready: yes | no (no while any FAIL remains, tracker items included)
- What was checked: <the PASS count and the notable passes, on one line; the enforcement mode>
- Needs doing: <one bullet per WARN, FAIL or missing tracker item: what, who, how>
