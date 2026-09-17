---
description: Install or update the ship pipeline in the current project (scaffolds scripts, agents, workflows, templates; never overwrites your project-specific files).
argument-hint: [--name NAME] [--team-key KEY] [--profile NAME]
---
1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh" $ARGUMENTS` from the repository root.
2. If `docs/pipeline/CONTEXT.md` was just created, fill it in **now** by inspecting the repository (build files, README, existing architecture docs): product summary, stack, exact test/build commands, environments, architecture rules, high-risk areas, brand/audience (for marketing), competitors (for research), regulatory notes. Ask the owner only for things the repo cannot tell you.
3. If `RELEASE_CHECKLIST.md` was just created, tailor its sections to this project (keep the Tickets, Security, Data and Infrastructure sections).
4. Set the URLs and `TRACKER_TEAM_KEY` in `scripts/pipeline/pipeline.env` from what the owner tells you.
5. Run `bash tests/pipeline/run-all.sh` and fix anything that fails.
6. Commit with message `chore: install ship pipeline`.

Reply with only:
- What was done: <created/updated/kept files, what you filled in>
- Impact: <what the owner must still set up (branches, GitHub environments, Linear labels, Hetzner hosts)>
