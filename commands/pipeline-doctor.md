---
description: Check whether this repository is ready for /ship — installed files, pipeline.env, the git remote and branches, the code host CLI and enforcement, hooks, CI files and the tracker workspace (through its CLI). Read-only; fixes only what the owner approves.
argument-hint: [--offline] [--with-tests]
---
1. If `scripts/pipeline/doctor.sh` is missing, the pipeline is not installed or predates the doctor: tell the owner to run `/pipeline-init`, and stop.
2. Run `bash scripts/pipeline/doctor.sh $ARGUMENTS` from the repository root. It changes nothing and takes seconds. It checks the tracker itself through `scripts/pipeline/tracker.sh` (`check`, then `setup --check`) and the code host through `scripts/pipeline/host.sh`.
3. **Tracker.**
   - A `FAIL tracker: … not signed in` means the owner runs `bash scripts/pipeline/connect.sh login` once, in a terminal.
   - A `FAIL tracker: missing …` lists the labels, fields and statuses the workspace lacks. Offer to create them all with `bash scripts/pipeline/tracker.sh setup`, naming each item. They belong to a shared workspace, so run it only after the owner says yes in this conversation.
   - Only with `TRACKER=connector` does the doctor print `TODO` lines instead. Then use the connector's tools: one harmless read call first (it is the only proof the connector works), compare the workspace with every `TODO` line, and offer to create what is missing.
4. **Everything else is advice.** For each `WARN` and `FAIL`, say what to do and who does it. Only the owner does these: pushes of unrelated history or force pushes, the sign-in (`connect.sh login`), environments and deploy secrets. Missing branches, branch protection, the deploy variable, CLIs and tracker items are set up by `/pipeline-init`, with the owner's one upfront approval. Tooling files are refreshed with `/pipeline-init`. A finding marked `[upgrade: …]` means the install predates v1.1.0 and a project-owned file (`pipeline.env` or a workflow) needs a change; `/pipeline-init` shows each change as a diff and applies only what the owner approves.

Reply with only:
- Ready: yes | no (no while any FAIL remains, tracker items included)
- What was checked: <the PASS count and the notable passes, on one line; the enforcement mode>
- Needs doing: <one bullet per WARN, FAIL or missing tracker item: what, who, how>
