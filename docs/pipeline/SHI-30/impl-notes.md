# SHI-30 — Implementation notes

Status: ready-for-dev

## Tickets worked
- SHI-30 (eng, the ticket itself; engineering only): /pipeline-init signs in before the tracker questions and offers the real Linear teams / Jira projects, the detected one recommended.

## Changes
- `scripts/pipeline/connect.sh`
  - New verb `teams [--hint KEY]`: after the sign-in, lists the Linear teams (GraphQL, with the workspace URL) or the Jira projects of the site (REST `project/search`). Prints `SITE <url>`, one `TEAM <KEY> <name>` per team/project, and `RECOMMENDED <KEY> (<why>)`: the one matching the hint (the detected prefix, any case) or, failing that, the only one. Exit 3 for trackers with no team list (GitHub/GitLab issues, connector), 4 not signed in, 5 curl/jq missing, 1 API error or empty list.
  - New options before the verb: `--git-host --git-url --tracker --tracker-url`. They describe a project that is not installed yet; when any is given, `pipeline.env` is not read, so the plugin's own settings never leak into the consumer's sign-in.
  - `login` for Jira with no site now says to pass `--tracker-url` instead of prompting against an empty site.
  - `PIPELINE_CURL_CMD` test double; file mode set to executable in git.
- `commands/pipeline-init.md`: Call 1 no longer asks for a key (the Jira option carries the site). New step 2b: `connect.sh <flags> status`, the one owner sign-in (moved before the install), then `connect.sh <flags> teams --hint <detected prefix>`. Call 2 question 5 lists the real teams/projects (recommended first); GitHub/GitLab Issues, or a failed listing, still ask for the prefix. Step 4 only re-asks for a sign-in if a CLI installed later still needs one.
- `README.md`: the question table and the "one manual step" paragraph describe the new order.

## CI/CD & infra changes
- none

## Migrations
- none

## Config / env vars
- none (no new pipeline.env keys; no new script paths, so nothing new to classify in scripts/init.sh)

## Tests
Suite before: 1224  after: 1256 (bash tests/pipeline/run-all.sh: ALL PIPELINE TESTS PASSED, 0 failed)
- `tests/pipeline/test_adapters.sh`: 90 → 119 (flags override pipeline.env; teams for Linear one/several teams, hint any case, no match, not signed in makes no API call, API error, empty list; Jira list, site, auth, no site, not signed in, not answering). Tracker API stubbed with a fake curl; no network.
- `tests/pipeline/test_init.sh`: 302 → 305 (the teams step exists, the sign-in comes before Call 2, Call 1 asks no key).

## How to check it
- In a throwaway repo with the plugin installed from this branch, run `/pipeline-init`, pick Linear: after Call 1 it asks you to run `connect.sh --git-host … --tracker linear login`, then Call 2 offers your Linear teams with the only/detected one recommended, and the install gets `--team-key` and the workspace URL.
- `bash scripts/pipeline/connect.sh --tracker linear teams --hint shi` on a signed-in machine prints `SITE`, `TEAM` and `RECOMMENDED` lines.

## Docs updated
- [x] README.md  - [ ] BRANCHING.md (no change needed)  - [ ] TICKETS.md (no change needed)  - [ ] CLOUD.md (no change needed)

## Known limitations
- Jira lists at most 100 projects (one page of `project/search`); a key beyond that is typed via Other.
- If jq or curl is missing before the install, the list cannot be read and the key is asked as typed text (the old behaviour).
- No CHANGELOG entry: CHANGELOG.md has no Unreleased section; release notes are written at go-live.
- Pre-existing, not changed here: 17 other `scripts/**/*.sh` files are stored as 100644 in git (not executable).
