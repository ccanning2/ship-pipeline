# SHI-30 — Brief (from the owner)

Source: https://linear.app/ship-pipeline/issue/SHI-30/pipeline-init-detect-the-tracker-team-or-project-after-sign-in
Received: 2026-09-25T10:44:02Z

---

pipeline-init: detect the tracker team or project after sign-in

The prefix question (Linear team key or Jira project key) comes before sign-in, so the owner has to know the key already. In the sandbox the owner picked Linear without a key. After sign-in there was a single team, `SHI`, which made the answer obvious.

**Needed:** for Linear and Jira, run the sign-in before the tracker questions, then list the real teams or projects as options, with the detected one recommended. Stop asking for the key up front.
