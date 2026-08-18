---
name: retro
description: Extract recurring friction from loop/STATE.md and the unit's own commits into actionable, audience-tagged constraints in loop/LESSONS.md, and retire lessons that have since become permanent skill text or proved inapplicable. Use after an /orchestrate run completes, or when the user says "/retro".
model: opus
effort: high
---

## 1. Read every record of the unit

Read `loop/STATE.md` from the most recent `boundary` marker onward — the entries `/loop-plan` and `/orchestrate` wrote for the unit just completed. Note the work item's reference.

Read `loop/lessons-archive.md` too, if it exists. It holds the pointers for lessons retired in earlier units, and you are its only reader. Check it before adding anything in step 5: a lesson you are about to write because this unit re-learned it may already be there, retired because its content became permanent instruction text — in which case the friction is a sign that text isn't working, which is a different and more useful finding than re-adding the lesson.

Then read what the unit actually did, not only what its agents said they did. Find the commits: `git log --oneline` filtered by the item reference if the profile's commit format embeds one, otherwise by date since the boundary entry. Read the diffs of anything whose journal entry is vague, contested, or describes a revert.

`loop/STATE.md` is agents reporting on themselves. A report of what an agent was about to do is not evidence it happened, and the dangerous half-applied tree is the one that still passes. The commits are the only record that cannot be self-serving.

Where the journal and the commits disagree, that gap is itself a candidate lesson — and say so plainly in the entry.

### The audit log, if it exists

If `loop/AUDIT.log` is present, the `SubagentStop` hook is installed and the harness appended one line as each spawn ended:

```
<utc timestamp> | <agent> | <task, or "-"> | <verdict token, or "-"> | <agent id>
```

It is written by the harness rather than by an agent, so it is the one record no agent can shape — and unlike `loop/STATE.md`, which `docs-writer` writes only after a task completes, it captures runs that died mid-task. Read the lines since the unit's boundary and use it for the questions the journal answers unreliably:

- **Does the spawn count match the journal?** `docs-writer` reports respins and escalations from what the orchestrator told it. Three `builder` lines for one task where the entry says "builder only, no respins" is a discrepancy worth a lesson.
- **Which stage does this unit actually burn its time in?** Counting lines per agent is the cheapest measure of where friction lives, and it points at whether the fix belongs in the packet, the profile, or a lesson.
- **Which tasks escalated?** An `implementer` line is an escalation, whether or not anything recorded it.

Treat a count from this file as measured; treat a task attribution of `-` as unknown rather than as "no task". The agent names the task in its own summary, so a line can miss it while the spawn was real.

If the file is absent, the hook simply is not installed. Note it once and move on — it is not a finding.

## 2. Identify recurring friction

Look for the same category of problem showing up more than once, not one-off mistakes. The shapes to look for: a convention `builder` repeatedly missed; a prerequisite that blocked progress; a decomposition problem (a task that had to be split or re-scoped mid-implementation); a review finding that recurred across tasks; a packet claim that turned out wrong.

Phrase each as an actionable constraint — something the receiving agent can act on when it's prepended to their prompt — not a narrative retelling.

**Prefer sharpening an existing lesson over adding a parallel one.** If a pattern is a more specific case of a lesson already in the file, say which one it refines and what it adds. A file of narrowing rules stays usable; a file of near-duplicates does not.

**Check whether the friction belongs in the profile instead.** A convention agents keep missing, or a command that keeps being wrong, is a profile defect, not a lesson — fix `loop/PROFILE.md` and don't write a lesson telling agents to work around it. A lesson is for how agents fail; the profile is for what this project is.

## 3. Tag each new lesson by audience

Every entry leads with its tags: `[planning]`, `[builder]`, `[reviewer]`, `[docs]`, `[testing]`, `[verifier]`, `[security]`. `/orchestrate` and `/loop-plan` deliver each agent only its own slice, so an untagged lesson reaches nobody and a wrongly-tagged one reaches an agent that cannot act on it.

Ask specifically whether the lesson is aimed at *planning*. A constraint about what a task packet must establish before implementation starts belongs to `/loop-plan`, and tagging it `[builder]` out of habit hands it to the one stage that can no longer act on it.

The last three tags are the easiest to forget, because their stages report and do not build — but they are where a unit's most repeatable friction shows up. A suite that misreports, a runtime behaviour this stack makes hard to observe, a trust boundary that keeps needing a second look: those belong to `test-runner`, `verifier` and `security-auditor` respectively, and a lesson about them tagged `[builder]` reaches a stage that will never run that check.

Tag for every audience that can act, and write the lesson once. Two near-copies aimed at two stages is the drift this file's own lessons warn about.

Do not add `[seed]` to a new lesson — that tag marks only what was inherited on adoption.

## 4. Retire what no longer belongs

Two cases. In both, **remove the entry from `loop/LESSONS.md` and append its one-line pointer to `loop/lessons-archive.md`** (create that file if it doesn't exist). You are the only reader of the archive — step 1 above reads it, no spawn ever receives it.

Moving rather than leaving in place is the point. A retired lesson has no audience by definition: its content is either already permanent instruction text somewhere in `.claude/`, or it cannot apply here. Left in `loop/LESSONS.md` it is read on every `/orchestrate` run for the life of the project, by agents that can act on none of it. The pointer still does its one job — stopping a future `/retro` re-deriving the same lesson — from the archive.

The two pointer shapes:

**Promoted to instruction text.** If a lesson's content is now permanent text in `.claude/skills/` or `.claude/agents/` — applied automatically rather than remembered — it is duplication, and a fact worth stating twice will drift.

```
- **RETIRED → <file> <location>** (<date>). <one-line summary.> Now permanent instruction text; the full rationale lives there.
```

**A seed that doesn't apply here.** If a `[seed]` lesson has had a real chance to bite and structurally cannot in this project — not merely "hasn't yet" — retire it with the reason:

```
- **RETIRED — not applicable here** (<date>). <one-line summary.> <Why this project cannot hit it.>
```

Be strict about the difference between "hasn't happened yet" and "cannot happen". A seed retired early is a lesson re-learned the expensive way.

Archive the pointer rather than deleting it: it's what stops a future `/retro` from re-deriving the same lesson and re-adding it in full.

Retiring and re-tagging are the only edits permitted to a prior entry. Never rewrite a prior lesson's substance, and never rewrite `loop/STATE.md` history.

## 5. Append

Append to `loop/LESSONS.md` under a new dated, unit-tagged heading:

```
## <unit> retro (<date>)
- `[tag]` <actionable constraint>
- `[tag] [tag]` <actionable constraint>
```

If nothing recurring is found — the unit went cleanly, no repeated friction — say so and don't force an entry. A lesson invented to have something to write is worse than no lesson. Step 4's retirement pass is still worth running on its own.

## 6. Report what moved

Tell the user: which lessons were added and to which audiences, which were retired and why, any profile fix made instead of a lesson, and any journal/commit discrepancy from step 1 that didn't rise to a lesson but is worth knowing.
