# SHI-51 — Brief (from the owner)

Source: https://linear.app/ship-pipeline/issue/SHI-51/minimise-the-mrpr-requirement-gate
Received: 2026-09-30T08:40:31Z

---

Minimise the MR/PR requirement gate

Only decisions that absolutely cannot be made by any of the agents should be raised to a human/user.

Pre-production confirmation by human remains in place but the rest the agents should attempt to resolve themselves.

Maybe consider adding another question/config on set up:

Full automation:

```
No human approvals or sign offs.
DEV:auto
QA:auto
UAT:auto
PROD:auto
```

Manual:

```
Every environment needs human approval/sign off.
DEV:manual
QA:manual
UAT:manual
PROD:manual
```

Semi Automation:

```
Some environments have full automation with others needing human approval/sign off. User must define whhat this looks like:
DEV:auto
QA:auto
UAT:auto
PROD:manual
```

Full automation means no human sign offs or approval, the agent should manage it themselves.

Attachments/links: none
