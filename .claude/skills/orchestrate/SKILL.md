---
name: orchestrate
description: Drive one pass of the task loop, spawning builder, test-runner, verifier, code-reviewer and docs-writer for each task in loop/PLAN.md until the tasks are exhausted or a task gets stuck. Use when the user wants to implement the next planned task(s), or says "/orchestrate".
model: sonnet
effort: medium
hooks:
  Stop:
    - hooks:
        - type: command
          command: sh "${CLAUDE_PROJECT_DIR}/.claude/hooks/loop-guard.sh"
  PreCompact:
    - hooks:
        - type: command
          command: sh "${CLAUDE_PROJECT_DIR}/.claude/hooks/precompact-checkpoint.sh"
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: sh "${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-git-destructive.sh"
---

Run in the main session. Write no feature code directly — every code change goes through `builder` or `implementer`. Never scheduled or backgrounded: this is a single foreground invocation that processes tasks until done or blocked, then returns control to the user.

## 1. Resume or start

Read `loop/PROFILE.md` (every command below comes from it), `loop/PLAN.md`, `loop/LESSONS.md` in full — you are the one who slices it for each agent — and the tail of `loop/STATE.md` (last ~20 entries).

Every lesson carries audience tags (`[planning]`, `[builder]`, `[reviewer]`, `[docs]`, `[testing]`, `[verifier]`, `[security]`). Each spawn below gets only the entries tagged for it, verbatim, and never the whole file — an agent reading another stage's constraints is paying attention tax on things it cannot act on. `/retro` moves retired lessons out to `loop/lessons-archive.md`, which you never read and never pass on; if you find a `RETIRED` entry still sitting in `loop/LESSONS.md`, skip it and mention it at the end of the run.

Every spawn also gets the profile's Commands and Conventions sections. Agents do not read the project's build files to work out how to test it, and they do not infer conventions from whichever file they happened to open.

**Ground every spawn in the project directory, and require it to confirm before acting.** A subagent inherits the session's working directory, which is not always this project — and an agent that quietly reads the wrong repo produces a confident report about a codebase nobody asked about. Observed in practice: an agent asked to run a gate reported "PROFILE.md does not exist" along with a plausible summary of a completely different project's state, and the mistake was only visible because the two repos used different build tools.

Three requirements, in every spawn prompt:

- State the project's **absolute** path, and have the agent verify it — print the working directory and confirm a known file is present — before it does anything else.
- Require that any environment fact it reports names the absolute path it applies to. "The file is missing" is unfalsifiable; "missing at `<abs path>`" is checkable, and it is what turns a wrong-directory error from invisible into obvious.
- **Name the task id in the spawn prompt.** Each agent declares it back as a `TASK: T-00X` first line, and that requirement now lives in the agent files rather than depending on you writing it into every prompt — which is where it was being lost: a real run logged three of twenty-five spawns with a missing or wrong id. An agent still cannot declare an id it was never given, so this half stays yours. Together they make every line of `loop/AUDIT.log` (below) attributable without inferring it from ordering.

If `loop/AUDIT.log` exists, the `SubagentStop` hook is installed and each spawn appends a line to it as it ends. You do not write to that file and do not need to read it during a run — it exists for `/retro`, and for reconstructing a run whose session died. Its one use here: if you are resuming and `loop/HANDOFF.md` is absent or stale, `tail` it to see which agents actually ran for the in-flight task, which is more reliable than the transcript for a session that was interrupted.

**Three hooks register when you are invoked**, declared in this skill's own frontmatter, and stay registered for the rest of the session. None needs anything installed and none touches a settings file:

- `Stop` → `loop-guard`. When the session tries to stop, it reads the profile's Loop budgets, the task packets and `loop/AUDIT.log`, and warns the user about a task over its spawn budget, a blocked task, or one at its final attempt. **Advisory only** — it exits 0 and speaks through `systemMessage`, because a `Stop` hook that blocks would trap a foreground session. You do not invoke it and do not need to react to it; it exists so a runaway is visible to the *user* at the moment they would otherwise walk away.
- `PreCompact` → `precompact-checkpoint`. Writes `loop/HANDOFF.md` from durable state before your context is compacted. This is the reason you can afford to lose context mid-task.
- `PreToolUse` → `guard-git-destructive`. **Blocking, unlike the other two.** Refuses `git stash`, `git checkout -- <path>` and `git restore <path>` — the three commands that have destroyed uncommitted work in this loop's history — and returns the reason to whoever ran it. The same hook is declared in every Bash-capable agent's frontmatter, so it covers your own calls and each subagent's; a subagent's copy fires only while that subagent runs. Read-only inspection is deliberately untouched: `git stash list`, `git status` and `git diff` all still work, and the first of those is what the verification procedure uses to confirm a tree is intact. You do not invoke it. If it refuses something you genuinely need, that is a finding for `/retro`, not a reason to work around it.

If `loop/HANDOFF.md` exists and reads `Status: active`, resume from the task and stage it describes instead of restarting from `loop/PLAN.md`'s first unchecked task. Rewrite that line to `Status: consumed (resumed <ISO-8601 timestamp>)` as you resume.

A checkpoint written by the hook says so on its `Written by:` line, and resumes by exactly this path — there is no second mechanism. Read it slightly differently, though: it derives the stage from the last `loop/AUDIT.log` spawn and deliberately does **not** assess whether the tree is half-applied, because a shell script cannot judge that. Run `git status` and `git diff` before trusting a hook-written checkpoint's picture of the working tree. A checkpoint from `/loop-handoff` has had an agent look at the tree; this one has not.

**Decide this on the status field, never by comparing dates.** `/loop-handoff` appends its own entry to `STATE.md` as its final act, so a checkpoint can never be "newer than the last journal entry" — the test it used to face was one it always failed. Journal entries are date-granular anyway. A checkpoint left `active` after a resume fails the other way: it gets replayed onto a task that has since moved on.

If `loop/PLAN.md` has no work item loaded or no tasks, stop and tell the user to run `/loop-plan` first.

**Record the unit's base commit** — `git rev-parse HEAD` — in `loop/PLAN.md` under the Summary heading as `Unit base: <sha>`, if it isn't there already. Step 8's security audit reviews the whole unit's change set and needs a range; a resumed session that never captured it has no way to reconstruct where the unit began. Write it to the file rather than holding it: this run may not be the one that closes the unit. Do not overwrite an existing value — the first run of the unit owns it.

## 2. Pick the next task

Take the next unchecked (`- [ ]`) task in `loop/PLAN.md` order. Read its full packet at `loop/tasks/T-00X.md`.

**Skip a task whose packet `Status:` line reads `blocked`.** It stays `- [ ]` in `loop/PLAN.md`, so picking by checkbox alone walks straight back into the task that just exhausted the ladder — and starts it at attempt 1, spending two more spawns including an Opus escalation on the failure a human was asked to look at. Read the packet's `Status:` before selecting, not after. Report every blocked task together when the run ends, and if all remaining tasks are blocked, stop and say so rather than looping.

**A task line is one whose checkbox is followed by a `T-00X` id.** `loop/PLAN.md`'s `## Verification` list uses the same checkbox syntax in the same file, so matching on the checkbox alone hands you a verification scenario as though it were a task — and step 8 checks those boxes off too, which makes a completed one indistinguishable from a finished task.

**Record the tree's current commit as this task's review base** — `git rev-parse HEAD` — before spawning anything. Step 5 diffs against it.

This matters whenever the profile's commit cadence is anything other than per-task. Under `per milestone` or `never`, nothing commits between tasks, so a bare `git diff` at step 5 shows T-001's and T-002's changes as well as T-003's. The reviewer then spends its attention on already-approved code and reports findings against a task that didn't write it.

Also run `git status --short` here. Anything already modified before the task started will show up in the step 5 diff too — the base is a commit, so it cannot exclude work that was uncommitted when you captured it. Record that file list and pass it to `code-reviewer` as out of scope, or the first task of a run in a dirty tree gets reviewed for changes it did not make.

## 3. Build

Spawn `builder` with: the task packet, the profile's Commands and Conventions sections, any decision records the packet references, and the `[builder]`-tagged lessons quoted verbatim.

## 4. Test

Spawn `test-runner` on `builder`'s (or `implementer`'s) output, with the profile's Commands and Prerequisites, and the `[testing]`-tagged lessons — what this project's suite has been caught misreporting.

- **Pass** → step 4b.
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

**A green gate that cannot go red is not a pass.** Check the profile's Test gate status before trusting this step:

- If the profile records **no test suite**, this step proves nothing and you must not treat it as verification. Several toolchains exit 0 on an empty test run without a warning, so the loop would report every task as passing while executing zero assertions. Substitute the strongest gate the project actually has, in this order: **step 4b**, which becomes the primary gate rather than an optional one and should run for every task it possibly can; then the build and type-check commands from the profile; then the lint command. Say explicitly in the `loop/STATE.md` entry which gate was used, so the journal never implies tests passed when none exist.
- If `test-runner` reports **zero tests executed** when the profile says a suite exists, that is a failure, not a pass — a test selection filter that matches nothing, or a suite that failed to load. Treat it as a step-4 failure and respin.

When a project has no test suite, say so once at the start of the run and recommend that a test harness become its own task. Do not silently proceed as if the gate were real, and do not refuse to run — a project without tests is still worth building in, as long as nobody is misled about what was verified.

## 4b. Verify against the running app

**Conditional.** Skip it — and say you skipped it — unless both hold:

- The profile's Runtime verification section says `applicable: yes`.
- At least one of the packet's acceptance criteria is observable at runtime. A criterion about an internal invariant, a refactor with no behavioural change, or a docs-only task has nothing to observe.

When both hold, spawn `verifier` with the packet's acceptance criteria, the profile's Runtime verification section **including its Browser observation fields**, Prerequisites, and the `[verifier]`-tagged lessons. It starts the app, exercises each criterion, and reports what it observed.

The Browser observation fields decide whether a UI criterion is reachable at all — `verifier` has no browser and drives only the harness this project owns. Omitting them leaves it guessing about the one thing it cannot improvise.

This is the only stage that tests the application rather than the tests. A green suite cannot see an endpoint that was never registered, a migration that didn't run, config bound to the wrong key, or a 200 returned over a swallowed exception — those reach a user without ever reaching a red test.

- **VERIFIED** → step 5.
- **NOT VERIFIED** → treat exactly as a step 4 test failure: same counter, same ladder, respawn with the observation. A criterion the app doesn't meet is a defect regardless of what the suite says.
- **BLOCKED** (app wouldn't start, prerequisite missing) → **not a test failure.** Same rule as step 4: fix the environment or tell the user, and do not count it against the task's counter.
- **A criterion `verifier` could not exercise is not verified.** Decide explicitly: accept it with the gap recorded in the `loop/STATE.md` entry, or fix what blocked it. Do not let it pass silently as though it had been checked.

## 5. Review

Produce the diff first. `git diff` does not show untracked files, so a task that **added** files produces an empty-looking diff and gets reviewed as though it changed nothing:

```
NEWLIST="$(git rev-parse --git-dir)/loop-new-files"
git ls-files --others --exclude-standard -z > "$NEWLIST"   # snapshot: files this task created
[ -s "$NEWLIST" ] && git add -N --pathspec-from-file="$NEWLIST" --pathspec-file-nul
git diff <base>
[ -s "$NEWLIST" ] && git reset -q --pathspec-from-file="$NEWLIST" --pathspec-file-nul
rm -f "$NEWLIST"
```

Three details, each of which corrupts the user's index or the review if dropped:

- **Snapshot the list once; never re-run `git ls-files` for the `reset`.** `add -N` puts those paths *into* the index, so a second `--others` listing comes back empty — and the `reset` then runs against an empty pathspec.
- **`git reset` with an empty pathspec resets the entire index.** It is not a no-op; it silently unstages everything the user had staged. That is why the `[ -s "$NEWLIST" ]` guard is on both lines and not decoration.
- **Use the NUL-delimited form, never a shell variable.** `NEW=$(git ls-files ...)` splits on whitespace, so one created path containing a space aborts the whole `git add` with `fatal: pathspec 'my' did not match any files`, and the diff then omits *every* file the task created — the exact failure this recipe exists to prevent.

Scope both commands to that snapshot, never to `.` — losing someone's index to a review step is not a trade the loop gets to make.

Spawn `code-reviewer` on that diff — `git diff <the base ref recorded in step 2>`, never a bare `git diff` — with the profile's Conventions section, the `[reviewer]`-tagged lessons, the out-of-scope file list from step 2 if the tree was dirty, and a one-line note on the unit's task-ownership split — which task(s), if any, own test coverage for the code this task touches (read `loop/PLAN.md`'s task list to determine this).

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

If all tasks are checked off, tell the user the unit's implementation is complete. Then walk `loop/PLAN.md`'s own `## Verification` list, **before** the profile's close gates.

### Walk the unit's verification list

These are the observable scenarios `/loop-plan` recorded as the definition of done for the whole unit — what makes it falsifiable rather than merely finished. Nothing has checked them: `docs-writer` checks off tasks, and the profile's close gates are a different list, so today they sit unchecked forever and the step reads as skipped because it was.

For each item: spawn `verifier` where it is observable against the running app, `test-runner` where a test covers it, or say plainly that it is the user's to confirm and ask. Then check it off, or leave it unchecked with a one-line reason.

**An unchecked item at the end of a unit is a result, not an oversight** — it records exactly what the unit did not prove, which is the most useful thing the plan carries into the next one. Do not mark an item verified because the tasks all passed: that is what the item is testing for, and treating it as proof turns the list into a restatement of "the work is done".

**Then spawn `security-auditor` on the unit's cumulative change set** — the range from the commit the unit started at to `HEAD`, plus the working tree if the loop hasn't committed. Give it the unit's goal from `loop/PLAN.md`, the profile's Architecture section, and the `[security]`-tagged lessons — the shapes this codebase has been caught getting wrong before.

This is the loop's only holistic look at the change set. `code-reviewer` sees one task's diff at a time, so a defect that emerges from how several tasks compose — a route added in one, an authorization check relaxed in another — passes every per-task review while being plain across the unit.

- **NO FINDINGS** → record it in the close entry and continue. This is the normal outcome and is not a reason to doubt the stage.
- **FINDINGS** → do not fix them here and do not quietly open new tasks. Report them to the user with severity, since they own integration. A `critical` finding is worth saying plainly that you would not merge on. Anything they want fixed becomes a new unit via `/loop-plan`, or a tracker item under "Filing follow-up work" below.
- **Pre-existing issues** it lists separately are follow-up items, never a reason to hold this unit.

Then walk the profile's Milestone-close gates in order, doing the ones that have commands and prompting the user for the ones that are theirs. If the profile's gates include a SAST or dependency-scan command, run it as well — it and `security-auditor` catch different things, and neither substitutes for the other: the scanner knows published vulnerabilities and pattern signatures, the auditor knows what this unit was trying to do.

Once the user reports the outcome of any gate that was theirs, spawn `docs-writer` one final time to append the **unit-close entry** to `loop/STATE.md`. Pass it: the unit and item ref, the security audit verdict and any findings (or "no findings"), the outcome of each item on the Verification list including the ones left unchecked and why, and the outcome of each profile gate. There is no task to check off. Say so in the spawn prompt, and tell it to declare exactly `TASK: -` — not `TASK: unit-close`, not the unit's name. The hook parses `T-00X` or `-` and nothing else; any other wording drops through to a prose scan that attributes the whole unit-close entry to whichever task the summary names first.

Do this even though the loop has ended. Without it the journal's final entry reads "remaining steps are the user's" forever, and every gate after the last task looks skipped — `/retro` then reads a unit that appears to have stopped early. `docs-writer` owns `loop/STATE.md` for the same reason it owns the task entries: one writer, one format, and the length budgets that apply to what agents hand each other never apply to what gets written to a file.

Any deferred work from this unit becomes a follow-up item here, under the rules below.

## Filing follow-up work

Applies whenever any step above defers work to the tracker. **An item this loop files becomes the input `/loop-plan` plans from later, so an error written here is an error the loop hands itself.** Not hypothetical: two items filed by the loop in its origin project were both materially wrong — one undercounted its own deliverable, the other's named fix would have degraded real request handling well outside its stated target. Both were caught only because planning re-read the code. Filing carefully is far cheaper than re-deriving every item at every future read.

- **Never file unilaterally.** Propose it — title, body, labels — and file only once the user agrees.
- **Mark every claim observed or assumed.** Say which you ran and what it printed, versus which you reasoned to. An inferred number reads identically to a measured one unless you say so.
- **Derive every count, don't recall it.** If the body says "two files" or "22 cases", produce that number from a search you actually ran, and name the command so a future reader can re-run it.
- **State the blast radius.** For the fix you're naming, say what else it touches — which other callers, requests, or code paths see the same change. A global configuration change almost never has a local effect.
- **Label the deliverables as a hypothesis in the body itself.** One line near the top: that the scope below is this loop's best reading at filing time and should be re-derived from the code before any packet inherits it.

If the profile records no tracker, propose the item to the user as text and let them decide where it goes. Do not invent a `TODO.md`.
