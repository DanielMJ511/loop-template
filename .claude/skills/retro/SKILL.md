---
name: retro
description: Extract recurring friction from loop/STATE.md and the unit's own commits into actionable, audience-tagged constraints in loop/LESSONS.md, and retire lessons that have since become permanent skill text or proved inapplicable. Use after an /orchestrate run completes, or when the user says "/retro".
---

## 1. Read both records of the unit

Read `loop/STATE.md` from the most recent `boundary` marker onward — the entries `/loop-plan` and `/orchestrate` wrote for the unit just completed. Note the work item's reference.

Then read what the unit actually did, not only what its agents said they did. Find the commits: `git log --oneline` filtered by the item reference if the profile's commit format embeds one, otherwise by date since the boundary entry. Read the diffs of anything whose journal entry is vague, contested, or describes a revert.

`loop/STATE.md` is agents reporting on themselves. A report of what an agent was about to do is not evidence it happened, and the dangerous half-applied tree is the one that still passes. The commits are the only record that cannot be self-serving.

Then read `loop/AUDIT.md` for the same window. The `SubagentStop` hook writes it, so it records every spawn that happened — including the ones for a task that was later blocked, which no journal entry covers because `docs-writer` only runs on tasks that succeeded.

You now have three records of the same unit, and they fail differently: the journal is agents describing themselves, the audit log is what actually ran, and the commits are what actually landed. Where any two disagree, that gap is itself a candidate lesson — and say so plainly in the entry.

The most useful disagreement is a task with many audit lines and a short, untroubled journal entry: that is a task that fought back, written up as though it hadn't.

## 2. Identify recurring friction

Look for the same category of problem showing up more than once, not one-off mistakes. The shapes to look for: a convention `builder` repeatedly missed; a prerequisite that blocked progress; a decomposition problem (a task that had to be split or re-scoped mid-implementation); a review finding that recurred across tasks; a packet claim that turned out wrong.

Phrase each as an actionable constraint — something the receiving agent can act on when it's prepended to their prompt — not a narrative retelling.

**Prefer sharpening an existing lesson over adding a parallel one.** If a pattern is a more specific case of a lesson already in the file, say which one it refines and what it adds. A file of narrowing rules stays usable; a file of near-duplicates does not.

**Check whether the friction belongs in the profile instead.** A convention agents keep missing, or a command that keeps being wrong, is a profile defect, not a lesson — fix `loop/PROFILE.md` and don't write a lesson telling agents to work around it. A lesson is for how agents fail; the profile is for what this project is.

## 3. Tag each new lesson by audience

Every entry leads with its tags: `[planning]`, `[builder]`, `[reviewer]`, `[docs]`. `/orchestrate` and `/loop-plan` deliver each agent only its own slice, so an untagged lesson reaches nobody and a wrongly-tagged one reaches an agent that cannot act on it.

Ask specifically whether the lesson is aimed at *planning*. A constraint about what a task packet must establish before implementation starts belongs to `/loop-plan`, and tagging it `[builder]` out of habit hands it to the one stage that can no longer act on it.

Do not add `[seed]` to a new lesson — that tag marks only what was inherited on adoption.

## 4. Retire what no longer belongs

Two cases, both replacing the entry in place with a one-line pointer:

**Promoted to instruction text.** If a lesson's content is now permanent text in `.claude/skills/` or `.claude/agents/` — applied automatically rather than remembered — it is duplication, and a fact worth stating twice will drift.

```
- **RETIRED → <file> <location>** (<date>). <one-line summary.> Now permanent instruction text; the full rationale lives there.
```

**A seed that doesn't apply here.** If a `[seed]` lesson has had a real chance to bite and structurally cannot in this project — not merely "hasn't yet" — retire it with the reason:

```
- **RETIRED — not applicable here** (<date>). <one-line summary.> <Why this project cannot hit it.>
```

Be strict about the difference between "hasn't happened yet" and "cannot happen". A seed retired early is a lesson re-learned the expensive way.

Keep the pointer rather than deleting: it's what stops a future `/retro` from re-deriving the same lesson and re-adding it in full.

These are the only edits permitted to a prior entry, alongside correcting or adding audience tags. Never rewrite a prior lesson's substance, and never rewrite `loop/STATE.md` history.

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
