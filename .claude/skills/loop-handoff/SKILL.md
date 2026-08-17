---
name: loop-handoff
description: Overwrite loop/HANDOFF.md with a checkpoint of the in-flight task, stage and next action, so /orchestrate can resume instead of restarting. Use when ending a session mid-unit, or when the user says "/loop-handoff". Distinct from a general-purpose conversation summary — this is a loop/-specific checkpoint.
---

Gather the current loop state:

- Which task (`T-00X`) is in flight, and which stage it's at (`builder`, `test-runner`, `code-reviewer`, `docs-writer`, or blocked/escalated).
- The failure counter for that task, if any respins have happened. Read it off the `attempt=` field on the task's `loop/PLAN.md` line rather than from the conversation — that line is the durable copy, and it is what a resumed session will trust.
- The last test result (pass/fail, which files or suites).
- `git status --short` output.
- One-line description of the next action when work resumes.

**Read the tree, don't trust the transcript.** If an agent reported what it was about to do and the session ended there, the report is not evidence it happened. Check `git status` and `git diff` before recording a stage. The dangerous case is a tree that still passes with a half-applied change in it.

Overwrite `loop/HANDOFF.md` — this is a single checkpoint, not a log; replace its contents entirely rather than appending:

```
# HANDOFF — session checkpoint
Written: <ISO-8601 timestamp, e.g. 2026-08-17T19:42:00Z>
Status: active

## Unit
<work item ref>

## Current task
<T-00X — title>

## Stage
<builder | test-runner | code-reviewer | docs-writer | blocked>

## Failure counter
<n of 2 before escalation, or "0 — no respins">

## Last test result
<pass/fail summary>

## Uncommitted changes
<git status --short output, or "none">

## Tree state
<"coherent — change and its tests are both present" | describe exactly what is half-applied>

## Next action
<one line>
```

Append a single line to `loop/STATE.md`: `## <date> — Handoff checkpoint written`. This is a journal record only — it is **not** how the checkpoint is found, and nothing should compare it against anything.

`/orchestrate` reads `loop/HANDOFF.md` first on its next invocation and resumes from the described task and stage whenever `Status: active`, instead of restarting from `loop/PLAN.md`'s first unchecked task. It flips the status to `consumed` as it resumes, so the same checkpoint is never replayed onto a task that has moved on.
