# Running the pipeline without your laptop (cloud sessions)

You have two ways to start `/ship` from the Claude iOS app or the Windows Desktop app so the work runs while your laptop is off.

| | A. Claude cloud sessions (recommended) | B. Always-on Hetzner box + Remote Control |
|---|---|---|
| Where Claude runs | Anthropic-managed VM (4 vCPU, 16 GB) | Your Hetzner server |
| Git host | **GitHub required**: cloud sessions clone from GitHub and push only to GitHub | Any, including GitLab |
| Your maintenance | None | A server, a systemd service, and Claude login on the box |
| Start from phone | iOS app → **Code** tab → new session | iOS app → **Code** tab → your server's session |
| Start from Windows | Desktop app → select **Cloud** → new session | Desktop app / claude.ai/code → your server's session |
| Where the requirement lives | The Linear ticket (attach docs there) | The Linear ticket (attach docs there) |
| Cost | Included in your plan's usage limits | A small Hetzner VM |

The pipeline in this repo is already GitHub-based, so **A is the shortest path**. It means moving <project> from GitLab to GitHub.

---

## Option A — Claude cloud sessions

### One-time setup
1. **Move the repo to GitHub** (keep GitLab as a read-only mirror for a while if you like):
   ```bash
   gh repo create <you>/reputabill --private --source . --push
   git push --all origin && git push --tags origin
   ```
   Recreate any CI variables as GitHub environment secrets/vars (see README → One-time setup).
2. **Connect GitHub to Claude:** open claude.ai/code (or the iOS **Code** tab), follow onboarding, and install the Claude GitHub App on the repo.
3. **Create a cloud environment** called `<project>`. At claude.ai/code, open the environment selector, then choose **Add cloud environment**:
   - **Network access:** set **Custom**, and tick *Also include default list of common package managers*. Allowed domains:
     ```
     dev.yourdomain
     qa.yourdomain
     staging.yourdomain
     yourdomain
     ```
     These are needed for the dev/QA/staging checks and for Playwright/curl testing. GitHub itself always works through Claude's GitHub proxy.
   - **Environment variables:** none needed. Leave `GH_TOKEN` unset so the GitHub proxy authenticates `gh`. Don't put secrets here: anyone using the environment can read them.
   - **Setup script:** paste the contents of `scripts/pipeline/cloud-setup.sh`.
4. **Commit everything under `.claude/`** (agents, commands, settings/hooks). Cloud sessions only see what's in the repo, not your laptop's `~/.claude`.
5. **Required:** enable the **Linear** connector for your sessions. Tickets are how the personas hand off work.

### Daily use
From the iOS app (**Code** tab) or the Windows Desktop app (**Cloud**):
1. Pick the repo, choose the `<project>` environment, and choose a permission mode that lets it run unattended. The repo hook and the CI/deploy gates still block unsafe merges and deploys.
2. Make sure the requirement is written on the Linear ticket, then send:
   ```
   /ship REP-142
   ```
3. Close the app. The session keeps running.
4. Come back when it asks you something, or asks "Promote `<sha>` to production?". Reply in the same session (`go`, or your answers), and it continues.
5. Check any ticket: `/pipeline-status REP-123`.

### How the cloud differs (handled automatically)
- **Branches.** Pushes only go to the session's branch. `/ship` stays on it and records the ticket in `.claude/.pipeline-ticket`.
- **Merging.** `promote.sh dev` merges via the PR (GitHub REST API) rather than pushing to master directly. Pipeline Gate must pass as a required check.
- **Deploys** run in GitHub Actions (`deploy.yml`), not in the session, so no SSH keys ever enter the VM.
- **Usage.** Cloud sessions share your plan's usage limits. `STATUS.md` makes every run resumable.
- **Idle sessions** eventually release their VM. Reopening restores the conversation, and `/ship <TICKET>` resumes from STATUS.md.

### Optional: scheduled runs
Create a routine (a scheduled cloud session) such as "Every weekday 07:00: list Linear REP tickets whose Owner label isn't chris and whose Stage isn't done or on-hold, and run `/ship` on each."

---

## Option B — Always-on Hetzner box (keeps GitLab)

Use this if you stay on GitLab. It requires the GitLab port of `deploy.yml` / `pipeline-gate.yml` and `glab` instead of `gh`.

1. Create a small Hetzner VM and install git, Java 21, Maven, Node 20, Docker, pandoc, poppler-utils and the Claude Code CLI.
2. Clone the repo to `/srv/reputabill`. As the service user, run `claude`, then `/login` (claude.ai account), and accept workspace trust.
3. Run `claude remote-control` once interactively and answer `y` to enable Remote Control.
4. Install a service at `/etc/systemd/system/claude-rc.service`:
   ```ini
   [Unit]
   Description=Claude Code Remote Control (reputabill)
   After=network-online.target
   [Service]
   User=claude
   WorkingDirectory=/srv/reputabill
   ExecStart=/usr/bin/env claude remote-control --name reputabill --spawn worktree
   Restart=always
   RestartSec=10
   [Install]
   WantedBy=multi-user.target
   ```
   Then enable it: `sudo systemctl enable --now claude-rc`.
5. In the iOS app or Desktop app, open the **Code** tab. The `reputabill` server shows with a green dot. Start a session and run `/ship …`.

Notes:
- `--spawn worktree` gives each session its own git worktree, so parallel tickets don't collide.
- After a restart, older sessions can be brought back with `claude remote-control --continue` (within about 4 hours).
- Enable push notifications with `/config` on the box, so the phone pings you for questions and go-live.
