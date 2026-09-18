---
description: Install or update the ship pipeline in the current project (scaffolds scripts, agents, workflows, templates; never overwrites your project-specific files).
argument-hint: [--name NAME] [--team-key KEY] [--profile NAME] [--no-deploy-envs] [--no-marketing]
---
1. Before running anything, ask the owner these two questions and add the matching flag to the arguments:
   - "Does this project have deployable environments — hosts, an image, a deploy workflow, a health endpoint?" If no, add `--no-deploy-envs`: no `scripts/deploy/*` and no `deploy.yml` are created, and the deploy/dispatch/smoke steps are skipped. The branch/tag promotion model is unchanged.
   - "Does this project have a marketing function?" If no, add `--no-marketing`: the marketing persona is not invoked and the production gate does not ask for launch content.
   Both default to yes, which is the original behaviour. Only an explicit `no` turns a capability off. On an **existing** install `scripts/pipeline/pipeline.env` is never rewritten, so tell the owner to set `PIPELINE_HAS_DEPLOY_ENVS` / `PIPELINE_HAS_MARKETING` there by hand; nothing is ever deleted.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh" $ARGUMENTS` from the repository root, with those flags appended.
3. If `docs/pipeline/CONTEXT.md` was just created, fill it in **now** by inspecting the repository (build files, README, existing architecture docs): product summary, stack, exact test/build commands, environments, architecture rules, high-risk areas, brand/audience (for marketing), competitors (for research), regulatory notes. Ask the owner only for things the repo cannot tell you. Record the two capability answers there in prose, so the personas know the project's shape as well as the tooling does.
4. If `RELEASE_CHECKLIST.md` was just created, tailor its sections to this project (keep the Tickets, Security, Data and Infrastructure sections).
5. Set the URLs and `TRACKER_TEAM_KEY` in `scripts/pipeline/pipeline.env` from what the owner tells you, and check `PIPELINE_HAS_DEPLOY_ENVS` / `PIPELINE_HAS_MARKETING` match the answers from step 1.
6. Run `bash tests/pipeline/run-all.sh` and fix anything that fails.
7. Commit with message `chore: install ship pipeline`.

Reply with only:
- What was done: <created/updated/kept files, what you filled in>
- Impact: <what the owner must still set up (branches, GitHub environments, Linear labels, Hetzner hosts)>
