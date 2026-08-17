---
name: loop-handoff
description: Overwrite loop/HANDOFF.md with a checkpoint of the in-flight task, stage and next action, so /orchestrate can resume instead of restarting. Use when ending a session mid-unit, or when the user says "/loop-handoff". Distinct from a general-purpose conversation summary — this is a loop/-specific checkpoint.
model: sonnet
---

Gather the current loop state:

- Which task (`T-00X`) is in flight, and which stage it's at (`builder`, `test-runner`, `code-reviewer`, `docs-writer`, or blocked/escalated).
- The failure counter for that task, if any respins have happened — without it, a resumed session restarts the escalation ladder from zero and can burn two more attempts on a task already at its limit. **Read it from the packet's `Status:` line** (`/orchestrate` persists it there on every change) rather than from the transcript, and copy that line verbatim. If the transcript and the packet disagree, the packet is the record that survived.
- The last test result (pass/fail, which files or suites).
- `git status --short` output.
- One-line description of the next action when work resumes.

**Read the tree, don't trust the transcript.** If an agent reported what it was about to do and the session ended there, the report is not evidence it happened. Check `git status` and `git diff` before recording a stage. The dangerous case is a tree that still passes with a half-applied change in it.

Overwrite `loop/HANDOFF.md` — this is a single checkpoint, not a log; replace its contents entirely rather than appending:

```
# HANDOFF — session checkpoint
Written: <timestamp>

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

Append a single line to `loop/STATE.md`: `## <date> — Handoff checkpoint written`.

`/orchestrate` reads `loop/HANDOFF.md` first on its next invocation and resumes from the described task and stage if it's newer than the last `loop/STATE.md` entry, instead of restarting from `loop/PLAN.md`'s first unchecked task.
