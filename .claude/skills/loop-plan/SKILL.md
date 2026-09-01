---
name: loop-plan
description: Generate loop/PLAN.md and loop/tasks/ for the next unit of work — a milestone, a ticket, or a prompt — grill the breakdown with the user, and record resulting decisions before any code is written. Use when the user wants to start or re-plan a unit of work, or says "/loop-plan".
model: opus
effort: high
---

Run in the main session, never delegated to a subagent — the grilling step below is an interactive dialogue with the user that an isolated subagent cannot hold.

Read `loop/PROFILE.md` first. If it doesn't exist, stop and tell the user to run `/loop-init`. Everything below that refers to a command, a convention, or a tracker means the one recorded there.

## 1. Read the planning lessons

Read `loop/LESSONS.md` and take the entries tagged `[planning]` — skip the rest, and skip any marked `RETIRED`. These are constraints on this skill's own output, earned from milestones where planning got it wrong, and they carry the same weight as the steps written here.

Entries also marked `[seed]` were inherited on adoption rather than earned in this project. Treat them as active: they describe how agents fail, not how one stack behaves.

Nothing enforces these but you. No later agent re-checks a packet's claims before building from it.

## 2. Resolve the work item

Read `source` from the profile's Work items section and follow only that branch.

### `milestone-chain`

Run the profile's list command. Determine which single item is next by the profile's rule (typically: the one open item with no open blocking dependency). If zero or more than one resolves as next, stop and report the ambiguity rather than guessing.

Fetch it and parse the profile's required sections.

### `ticket`

Fetch the item the user named, with the profile's fetch command. **Do not assume any section structure.** Read the body as prose and extract: what outcome is wanted, and how anyone would know it was achieved.

If the item doesn't state verification criteria — most don't — derive them and confirm with the user in step 4. Do not proceed on invented acceptance criteria: a task whose "done" is unstated ends up unfalsifiable, and an unfalsifiable task passes review by default.

### `prompt`

The user's description is the work item; nothing is fetched.

Restate back to them, before decomposing: the goal in one sentence, and the specific observable conditions that will mean it's done. Get confirmation. This replaces the structure a tracked item would have supplied, and skipping it is how a prompt-sourced task ends up with tests that assert nothing.

### Every source: the deliverables are a hypothesis

**Whatever the source, treat its stated scope as the reporter's best guess — most of all when this loop wrote it.** Re-derive from the code before a packet inherits it: verify every count by counting, and check whether each named fix reaches further than its stated target. Two self-filed items in the loop's origin project were both materially wrong in exactly these two ways, written by agents with full context, and caught only because planning re-read the code (see the `[planning]` seed lessons).

Where your re-derivation disagrees with the item, the code wins. Note the discrepancy in `loop/PLAN.md` and raise it during grilling rather than silently planning around it.

**When the item you disprove is `loop/PROFILE.md` itself, correct it.** Re-deriving scope regularly disproves a profile fact, because `/loop-init` measured it once and the project moved. Leaving a known-false fact in place is the worst option available: every later agent reads the profile as settled and inherits the error with full confidence, and no downstream stage re-checks it.

Three stages may write to the profile, for different reasons: `/loop-init` detects it, you correct a measured fact you disproved while planning, and `/retro` fixes what repeated friction shows to be a profile defect. Every other stage — `docs-writer` most explicitly — reports the problem and leaves the file alone.

Two boundaries on that permission:

- **Measured facts only** — a test count, a baseline, a command, a stated root cause, a line-number citation. Correct them in place, and mark the correction with the date and that `/loop-plan` made it, so a reader can tell it from what `/loop-init` detected. Prefer citing a key or a symbol over a line number, since the task you are about to plan will shift the lines.
- **Never the judgment sections.** Conventions, git policy, loop budgets, work-item source, milestone-close gates are the user's, and `/retro`'s to revisit. If one of those looks wrong, say so and leave it.

`docs-writer` is forbidden from touching the profile at all, and that stays true — it records what happened rather than re-deriving anything. You are correcting a fact you just disproved with evidence in hand, which is a different act.

**Enumerate scope by the invariant being restored, not by the example that revealed it.** When a task is "fix instances of X", the count you write into the packet is a completeness claim, and searching for the symptom that brought the problem to your attention will under-count it every time. Search for the property instead.

This has now happened in both projects the loop has run in. In one, a packet listed two lock-ordering offenders when there were three. In the other, a packet named one namespace-root violation when there were two — because planning grepped for the *misspelling* that prompted the task rather than for namespace declarations, and the second file was spelled correctly while still carrying the wrong root. Both were caught downstream, which is luck: a review stage is not a scope-enumeration tool.

Concretely: write down the invariant in one sentence, derive the search that would find every violation of it, run that search, and record the command in the packet so a reviewer can re-run it.

## 3. Decompose into tasks

Read the existing source files for the areas the work touches — the profile's Architecture section names the patterns worth reading first.

Break the work into concrete `T-00X` tasks. Each should be small enough for `builder` to complete and get reviewed in one pass, but large enough to be a coherent unit. Prefer a task that delivers a working slice over a task that delivers a layer.

**That is the upper bound. The lower bound is missing, and its absence costs more.** Mechanical
changes that restore **one** invariant become **one** task, not one task per site.

A task carries a fixed overhead that has nothing to do with its size: the profile's Commands and
Conventions floor and the audience-sliced lessons reach *every* spawn, and a clean task spends four
of them. Measured in one adopting project, that floor is ~15k tokens per task before a line of the
packet is read. Splitting one invariant across five sites pays it five times for no additional
evidence — the five reviews check the same rule against the same pattern, and the five journal
entries say the same thing five ways.

Decide the batch the way step 2 already decides scope, and reuse that work rather than repeating it:
write the invariant in one sentence, derive the search that finds every violation of it, run that
search, and record the command in the packet. For a "fix instances of X" unit step 2 has already
produced exactly that search, and the batch is its result set.

Two guards, so a batch cannot quietly become one giant task:

- **Every member shares one acceptance-criteria shape.** A batch whose members need different
  evidence is not one invariant but several, and it splits.
- **No member carries its own `[runtime]` criterion.** `verifier` attributes runtime observations
  per task, and a batch collapses that attribution — so a unit with runtime criteria stays split
  even where the edits look identical.

A batch is one packet with one `Status:` line, so the escalation ladder applies to it whole: a batch
that fails twice escalates once rather than five times. That is the saving. It is also the risk —
a batch that was really several invariants fails as a unit and takes the whole set back through the
ladder, which is what the first guard exists to prevent.

**Where a task's approach depends on how a dependency behaves internally, settle it now — while writing the packet — not later at build time.** Decompile it, read its source, ask the database for its actual plan or lock state, print what the framework actually constructed. Then state the finding in the packet as a verified fact and name how it was verified. The same claim costs a build failure if the builder has to discover it and nothing at all if the packet already answers it. A verified internal is also what lets you choose an implementation *shape* the guard can observe — a decision only planning can make.

### Probes that edit the tree

The strongest probes change a file — flip a compiler option, apply a candidate fix, run the suite, read what actually happens. That is legitimate and often the only way to settle a claim. **It also means this skill, which writes no application code, spends part of its run with application code modified.** Three rules:

- **Revert every probe the moment it has answered its question**, before starting the next one. Not at the end of the run: at the end of each probe. What survives is the *finding* in the packet — the claim, the command, the output — never the edit.
- **`git status` before you stop, and again after any interruption.** A probe left in the tree looks exactly like a builder's work to whatever runs next, and `/orchestrate` step 2 will hand it to `code-reviewer` as this task's diff. This is not hypothetical: a run interrupted mid-probe left a modified `tsconfig.json` behind and caught it only on resume.
- **Record the probes you rejected, not just the one that worked.** A candidate fix you ran and disproved is worth a line in the packet, because otherwise the builder tries it. Say what it produced — "clears the compile error and yields `EventBus is not a function`" tells the builder more than "this approach is wrong".

### Choosing a task's route

Every packet carries a `Route:` field that `/orchestrate` reads at step 2. You own it; no later
stage changes it except the promotion rule below, and it is a **planning** decision precisely
because the evidence needed to make it is in front of you now and gone by build time.

- **`full`** — the default. Every task gets it unless all four conditions below hold.
- **`direct`** — `/orchestrate` collapses its build and test stages into a single `builder` spawn
  that runs the profile's test command itself and reports the measured output. Review and recording
  are unchanged. Four spawns become three.

**Eligibility is evidence, not size.** A one-line change to a load-bearing branch is not eligible; a
fifty-line rename across one file is. All four must hold, and the packet must say which reason
carried each:

1. **No `[runtime]` or `[runtime:ui]` acceptance criteria.** A criterion observable against the
   running app needs `verifier`, and `verifier` runs only on the full route.
2. **No new files.** A created file changes the diff recipe `/orchestrate` builds at review time,
   and a file that has never been reviewed gets the full pass.
3. **One file, or one mechanical pattern across files that the batching rule above already
   grouped.** "Mechanical" means the edit is determined by the invariant — a rename, a constant, a
   signature applied uniformly — not chosen per site.
4. **The change does not alter behavior the suite covers.** This is the load-bearing one. On the
   direct route the test verdict is self-reported by the agent that wrote the code, so it is a
   regression check, not the evidence for the change. Where the suite's result *is* the evidence,
   the route is `full`, whatever the diff looks like.

**When you cannot settle a condition, write `full`.** The route is an optimization, and an
optimization that has to be argued for is one that has already cost more than it saves.

If the profile's Loop budgets section reads `Direct route: disabled`, write `full` on every packet
and say in `loop/PLAN.md` that project policy set it.

Overwrite `loop/PLAN.md`:

```
# PLAN — <work item title>
Regenerated by /loop-plan on <date>.

## Summary
- Source: <milestone #n | ticket ABC-123 | prompt>
- Unit base: <left blank — /orchestrate records the starting commit here on its first run, and the milestone-close security audit reviews the range from it to HEAD>
- Goal: <one line>
- Verification criteria: <where they came from — the item's own section, or derived and confirmed with the user on <date>>
- Scope discrepancies found: <what the code said that the item didn't, or "none">
- Decisions recorded: (filled in after step 4)

## Tasks
- [ ] T-001 — <title> (loop/tasks/T-001.md)

## Verification
<!-- /orchestrate walks these once every task is done, checking each off or noting why
     it could not be confirmed. These are NOT tasks: only `- [ ] T-00X` lines are. -->
- [ ] <observable scenario 1>
```

Clear `loop/tasks/T-*.md` and write fresh packets, numbering from `T-001` (numbering resets each unit of work). **Match `T-*.md`, not `*.md`** — the wider glob also matches `loop/tasks/README.md`, which `/loop-init` writes once and nothing restores, so the first run of this skill would delete it permanently:

```
# T-00X — <title>
Unit: <work item ref>   Status: pending   Route: <full | direct>
<!-- Status is owned by /orchestrate from here on: it records the escalation
     ladder's position there so a dead session doesn't restart it at zero.
     Route is owned by you, set once from the four conditions above; the only
     later change is /orchestrate promoting a direct task to full on a review
     finding, which it records in Status rather than here. -->

## Route reason
<which of the four conditions decided it, in one line — omit on a `full` packet
whose ineligibility is obvious from its runtime criteria>


## Description
<what to build>

## Acceptance criteria
<observable conditions, scoped to this task. Mark each `[runtime]` if it can be
observed against the running app — a request, a command, a rendered output, a log
line. /orchestrate spawns `verifier` for the runtime ones. Unmarked criteria are
checked by the suite and by review.

Mark `[runtime:ui]` where observing it needs a rendered page — a click, a console
message, a layout. `verifier` has no browser and can only drive the harness the
profile's Browser observation fields name; where that reads `none`, a `[runtime:ui]`
criterion will come back NOT VERIFIED. Check that field while writing the packet, and
say so here rather than letting the gap surface at verification time.>

## Relevant conventions
<the profile rules that apply, decision records to read, domain terms in play>

## Files likely touched
<best guess from reading the existing code>

## Verified dependency internals
<each internal probed for this task: the claim, the command that settled it, its output — omit if none>

## Constraints from LESSONS.md
<the [builder]-tagged entries, carried in verbatim at spawn time by /orchestrate — leave empty here>
```

## 4. Grill the breakdown before any code is written

Note the current highest number in the profile's decision-record directory, for later comparison.

Present `loop/PLAN.md` and the task packets and stress-test them with the user.

**Check for `mattpocock-skills:grill-with-docs` on disk, never in your own skill listing.** It sets `disable-model-invocation: true`, which is exactly what keeps it *out* of that listing — so "it isn't in my available skills" is not evidence of anything, and treating it as evidence means the full tier is never offered to anyone. Look for the file instead:

```
ls ~/.claude/plugins/cache/*/mattpocock-skills/*/skills/engineering/grill-with-docs/SKILL.md
```

- **Found** → ask the user to run `/mattpocock-skills:grill-with-docs`. You cannot invoke it, and you must not replicate it by other means. Wait for them.
- **Not found, or the glob is inconclusive** → say which you got and offer the short form below rather than announcing it isn't installed. A plugin can live at a path this glob doesn't cover, and the user knows what they have.

The full session interrogates edge cases and writes decision records only where a decision is hard to reverse, surprising without context, and the result of a real trade-off.

Wait for grilling to reach its own definition of done — the decision tree resolved, nothing silently assumed — before continuing.

When fact-finding is needed mid-grilling (not a decision, just information the codebase already has), find it yourself rather than asking the user. Grilling's questions are reserved for the user's actual decisions.

### Two guards on what grilling may declare settled

Grilling's failure mode is closing a question confidently instead of leaving it open. In the loop's origin project it concluded a dependency-down scenario was untestable; the task shipped a weaker assertion and handed the user manual verification work. It was testable one layer out, by stopping that dependency's container against a running app.

- **A negative verdict — "untestable", "impossible", "not worth it" — must name the layer it applies to, and check one layer out before it sticks.** Ask whether the container, the compose stack, a live process, or a real request can observe what an in-process test cannot.
- **A claim about a dependency's internals must be probed, not reasoned, before grilling records it as decided.** Same rule as step 3; grilling is where it's cheapest to run.

### Short form

When the full session won't happen — a deadline, a small unit of work, a repo that isn't yours — run this instead of skipping grilling entirely. A defined short form beats silent abandonment. These are the question types that actually caught things:

1. **Which packet claim would be most expensive to be wrong about?** Verify that one now.
2. **For each acceptance criterion: what would make it fail?** Any criterion with no failure mode isn't a criterion.
3. **What did we declare impossible or untestable, and at which layer?** Apply the guard above.
4. **What does this change touch beyond its stated target?** Callers, config shared with other paths, anything reading the same state.
5. **What's the ugliest thing that happens if two of these run at once, or one fails halfway?**

Record the answers in `loop/PLAN.md` under a `## Grilling notes` heading. Unwritten answers do not survive the session.

## 5. Reconcile

If grilling changed scope — added an edge case needing its own task, ruled out an approach a packet assumed — update `loop/PLAN.md` and the affected packets.

Diff the decision-record directory against the number from step 4 and fill in the "Decisions recorded" line.

## 6. Log and stop

Append to `loop/STATE.md`:

```
## <date> — <work item> boundary
- Source: <ref>
- Tasks planned: T-001..T-00N
- Decisions recorded: <refs, or "none">
- Grilling: <full | short form | skipped, with reason>
```

Stop. **Write no application code.** Tell the user to review `loop/PLAN.md` and any new decision records, then run `/orchestrate`.
