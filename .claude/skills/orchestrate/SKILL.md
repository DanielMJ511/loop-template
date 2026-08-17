---
name: orchestrate
description: Drive one pass of the task loop, spawning builder, test-runner, code-reviewer and docs-writer for each task in loop/PLAN.md until the tasks are exhausted or a task gets stuck. Use when the user wants to implement the next planned task(s), or says "/orchestrate".
model: sonnet
---

Run in the main session. Write no feature code directly — every code change goes through `builder` or `implementer`. Never scheduled or backgrounded: this is a single foreground invocation that processes tasks until done or blocked, then returns control to the user.

## 1. Resume or start

Read `loop/PROFILE.md` (every command below comes from it), `loop/PLAN.md`, `loop/LESSONS.md` in full — you are the one who slices it for each agent — and the tail of `loop/STATE.md` (last ~20 entries).

Every lesson carries audience tags (`[planning]`, `[builder]`, `[reviewer]`, `[docs]`). Each spawn below gets only the entries tagged for it, verbatim, and never the whole file — an agent reading another stage's constraints is paying attention tax on things it cannot act on. Skip entries marked `RETIRED` entirely: their content is already permanent instruction text somewhere in `.claude/`, and passing them along re-introduces the duplication retirement removed.

Every spawn also gets the profile's Commands and Conventions sections. Agents do not read the project's build files to work out how to test it, and they do not infer conventions from whichever file they happened to open.

**Ground every spawn in the project directory, and require it to confirm before acting.** A subagent inherits the session's working directory, which is not always this project — and an agent that quietly reads the wrong repo produces a confident report about a codebase nobody asked about. Observed in practice: an agent asked to run a gate reported "PROFILE.md does not exist" along with a plausible summary of a completely different project's state, and the mistake was only visible because the two repos used different build tools.

Three requirements, in every spawn prompt:

- State the project's **absolute** path, and have the agent verify it — print the working directory and confirm a known file is present — before it does anything else.
- Require that any environment fact it reports names the absolute path it applies to. "The file is missing" is unfalsifiable; "missing at `<abs path>`" is checkable, and it is what turns a wrong-directory error from invisible into obvious.
- Require the agent to name the task id (`T-00X`) in its summary. Costs a token and makes every line of `loop/AUDIT.log` (below) attributable to a task without inferring it from ordering.

If `loop/AUDIT.log` exists, the `SubagentStop` hook is installed and each spawn appends a line to it as it ends. You do not write to that file and do not need to read it during a run — it exists for `/retro`, and for reconstructing a run whose session died. Its one use here: if you are resuming and `loop/HANDOFF.md` is absent or stale, `tail` it to see which agents actually ran for the in-flight task, which is more reliable than the transcript for a session that was interrupted.

If `loop/HANDOFF.md` has content newer than the last `STATE.md` entry, read it and resume from the task/stage it describes instead of restarting from `loop/PLAN.md`'s first unchecked task.

If `loop/PLAN.md` has no work item loaded or no tasks, stop and tell the user to run `/loop-plan` first.

## 2. Pick the next task

Take the next unchecked (`- [ ]`) task in `loop/PLAN.md` order. Read its full packet at `loop/tasks/T-00X.md`.

**Record the tree's current commit as this task's review base** — `git rev-parse HEAD` — before spawning anything. Step 5 diffs against it.

This matters whenever the profile's commit cadence is anything other than per-task. Under `per milestone` or `never`, nothing commits between tasks, so a bare `git diff` at step 5 shows T-001's and T-002's changes as well as T-003's. The reviewer then spends its attention on already-approved code and reports findings against a task that didn't write it.

Also run `git status --short` here. Anything already modified before the task started will show up in the step 5 diff too — the base is a commit, so it cannot exclude work that was uncommitted when you captured it. Record that file list and pass it to `code-reviewer` as out of scope, or the first task of a run in a dirty tree gets reviewed for changes it did not make.

## 3. Build

Spawn `builder` with: the task packet, the profile's Commands and Conventions sections, any decision records the packet references, and the `[builder]`-tagged lessons quoted verbatim.

## 4. Test

Spawn `test-runner` on `builder`'s (or `implementer`'s) output, with the profile's Commands and Prerequisites.

- **Pass** → step 5.
- **Fail** → increment this task's failure counter and persist it (below):
  - **1st failure**: respawn `builder` with the packet plus `test-runner`'s failure digest. Return to step 4.
  - **2nd consecutive failure**: escalate to `implementer`, passing the full history — both diffs and both failure digests — plus the same `[builder]` slice. Return to step 4.
  - **3rd failure (implementer also failed)**: stop working this task. Append a "task blocked" entry to `loop/STATE.md` (task id, failure history summary). Return control to the user — do not retry further.

**Persist the counter to the packet, don't hold it in your head.** The moment a task's count changes, edit its `loop/tasks/T-00X.md` `Status:` field to record where the ladder stands:

```
Status: in progress — attempt 2 of 3 (builder ×1 failed: <one-line reason>)
Status: in progress — attempt 3 of 3, escalated to implementer (<one-line reason>)
Status: blocked after 3 attempts — <one-line reason>
```

A counter that lives only in this session dies with it, and it dies *silently*: the next `/orchestrate` reads an unchecked task, starts at attempt 1, and spends two more spawns — including an Opus escalation — on a task that already exhausted the ladder. That is the single most expensive recoverable mistake the loop can make, and it costs one line of editing to prevent. `/loop-handoff` records the same number, but only if someone remembers to run it; this survives a session that dies without warning.

On resume, read the `Status:` line before spawning anything, and continue the ladder from where it says. If it disagrees with `loop/HANDOFF.md`, prefer whichever is newer and say which you used.

**A prerequisite failure is not a test failure.** If `test-runner` reports a missing prerequisite from the profile — a container runtime down, a service unreachable, a missing env file — fix the environment or tell the user, and do not count it against the task's failure counter. Spending an escalation on a stopped Docker daemon wastes the ladder's most expensive rung on a non-defect.

**A green gate that cannot go red is not a pass.** Check the profile's test-gate status before trusting this step:

- If the profile records **no test suite**, this step proves nothing and you must not treat it as verification. Several toolchains exit 0 on an empty test run without a warning, so the loop would report every task as passing while executing zero assertions. Substitute the strongest gate the project actually has, in this order: the build and type-check commands from the profile; the lint command; and the packet's own acceptance criteria, checked by running the thing and observing the stated outcome. Say explicitly in the `loop/STATE.md` entry which gate was used, so the journal never implies tests passed when none exist.
- If `test-runner` reports **zero tests executed** when the profile says a suite exists, that is a failure, not a pass — a test selection filter that matches nothing, or a suite that failed to load. Treat it as a step-4 failure and respin.

When a project has no test suite, say so once at the start of the run and recommend that a test harness become its own task. Do not silently proceed as if the gate were real, and do not refuse to run — a project without tests is still worth building in, as long as nobody is misled about what was verified.

## 5. Review

Spawn `code-reviewer` on this task's diff — `git diff <the base ref recorded in step 2>`, never a bare `git diff` — with the profile's Conventions section, the `[reviewer]`-tagged lessons, the out-of-scope file list from step 2 if the tree was dirty, and a one-line note on the unit's task-ownership split — which task(s), if any, own test coverage for the code this task touches (read `loop/PLAN.md`'s task list to determine this).

Without that note, `code-reviewer` will reasonably flag a diff with new behavior and no tests as a critical finding even when testing is a deliberate, separate, already-planned task. That happened in the loop's origin project and cost an extra review round for a non-defect. Include it on every spawn for a unit with a dedicated test task — don't remember it ad hoc per task.

- **Critical finding on the task's first review pass** (builder's first attempt, not yet escalated): escalate straight to `implementer` with the findings — do not spend a retry looping `builder` on a critical finding.
- **Non-critical findings, or any finding on a later pass**: respawn whichever agent is active for this task with the feedback appended. Return to step 4 (re-test), then re-review. Same bounded-retry counter as step 4 — a review-triggered respin counts toward the escalation threshold.
- **Approved**: step 6.

## 6. Record

Set the packet's `Status:` to `done (<n> attempt(s))` — you own that field, not `docs-writer`. Leaving it at `attempt 2 of 3` on a task that passed makes a later resume think the ladder is still live.

Spawn `docs-writer` to append the `loop/STATE.md` entry, check off the task in `loop/PLAN.md`, and draft a decision record only if one is warranted. Pass the `[docs]`-tagged lessons — these are the constraints on what may be stated as fact in a document that outlives this session.

If the task surfaced work you deliberately did not do — a reviewer finding ruled out of scope, a problem found while testing — do not let it live only in a `loop/STATE.md` paragraph. Follow "Filing follow-up work" below.

## 7. Commit

Only if the profile's Git section permits the loop to commit. If it says the user commits manually, stop here and summarize what's staged for them.

- `git add` only the files this task touched (never `git add -A`), plus `loop/PLAN.md` and `loop/STATE.md` if the loop is committed in this repo.
- Run the profile's full test command once more — the step 4 run may have been scoped to specific files, and the profile's pre-commit gate applies.
- Respect the profile's branch policy. If it forbids committing to the default branch and that's where you are, create a branch first.
- Use the profile's commit message format exactly.
- Do not push unless the profile says otherwise. Pushing stays a separate, explicit user action.

## 8. Loop or stop

If `loop/PLAN.md` still has unchecked tasks, return to step 2.

If all tasks are checked off, stop and tell the user the unit's implementation is complete. Then walk the profile's Milestone-close gates in order, doing the ones that have commands and prompting the user for the ones that are theirs.

Once the user reports the outcome of any gate that was theirs, append a close entry to `loop/STATE.md` recording it (unit, item ref, findings or "no findings"). Do this even though the loop has ended: no `docs-writer` runs after the last task, so without this step the journal's final entry reads "remaining steps are the user's" forever and the gate looks skipped.

Any deferred work from this unit becomes a follow-up item here, under the rules below.

## Filing follow-up work

Applies whenever any step above defers work to the tracker. **An item this loop files becomes the input `/loop-plan` plans from later, so an error written here is an error the loop hands itself.** Not hypothetical: two items filed by the loop in its origin project were both materially wrong — one undercounted its own deliverable, the other's named fix would have degraded real request handling well outside its stated target. Both were caught only because planning re-read the code. Filing carefully is far cheaper than re-deriving every item at every future read.

- **Never file unilaterally.** Propose it — title, body, labels — and file only once the user agrees.
- **Mark every claim observed or assumed.** Say which you ran and what it printed, versus which you reasoned to. An inferred number reads identically to a measured one unless you say so.
- **Derive every count, don't recall it.** If the body says "two files" or "22 cases", produce that number from a search you actually ran, and name the command so a future reader can re-run it.
- **State the blast radius.** For the fix you're naming, say what else it touches — which other callers, requests, or code paths see the same change. A global configuration change almost never has a local effect.
- **Label the deliverables as a hypothesis in the body itself.** One line near the top: that the scope below is this loop's best reading at filing time and should be re-derived from the code before any packet inherits it.

If the profile records no tracker, propose the item to the user as text and let them decide where it goes. Do not invent a `TODO.md`.
