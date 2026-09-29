# SHI-54 — Brief (from the owner)

Source: https://linear.app/ship-pipeline/issue/SHI-54/improve-performance
Received: 2026-09-29T09:45:32Z

---

Title: Improve performance
--- description
* **Parallelize execution:** Run independent tasks or agent evaluations at the same time using async programming.
* **Implement caching:** Cache frequent tool outputs, embedding lookups, or static LLM responses.
* **Stream tokens:** Use token streaming between agents or to the end user so the pipeline *feels* faster and processes data incrementally.
* **Prune context:** Use a summary agent or a memory management strategy to keep context windows lean.
* Status %: Add an estimated percentage of status/progress for each step.
