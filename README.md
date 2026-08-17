# Loop template

An agent build loop that adapts itself to a project. Copy it in, run `/loop-init`, start looping.

Extracted from a real project where it drove nine milestones. Across four of them it escalated to
the expensive model twice and gave up on a task zero times.

## Adopt it

```bash
cp -r /path/to/loop-template/.claude /your/project/
```

Then, in the project:

```
/loop-init
```

That's the whole adoption. `/loop-init` detects the stack, the commands, the conventions, the
tracker and the git policy, proposes what it found with evidence for each claim, and writes
`loop/PROFILE.md`. **You are not asked to fill in a config file, and no agent has to read this
loop's machinery to work out how to adapt to your project.**

It works on an empty directory too — greenfield mode asks four questions and writes a provisional
profile, so a brand-new project can start looping immediately.

Then:

```
/loop-plan       # decompose the work, grill it, record decisions — writes no code
/orchestrate     # drive each task through build → test → review → record
/retro           # bank recurring friction as constraints; retire what no longer applies
/loop-handoff    # checkpoint mid-session so /orchestrate resumes instead of restarting
```

## The one rule

**Everything project-specific lives in `loop/PROFILE.md`. Nothing project-specific goes in
`.claude/`.**

| Layer | Where | Edited per project? |
|---|---|---|
| Machinery — skills and agents | `.claude/` | Never |
| Profile — commands, conventions, tracker, git policy | `loop/PROFILE.md` | Generated once, then evolves |
| Working state — plan, journal, lessons, packets | `loop/` | Per unit of work |

If the loop does the wrong thing for your project, the fix is in the profile. Editing a skill to
suit one project forks the machinery and you lose every later improvement.

## When detection guesses wrong

Expected, and cheap to fix. `/loop-init` cites evidence for each detected fact precisely so a wrong
guess is visible rather than buried.

- **A command is wrong** → fix that row in the profile. Nothing else needs touching.
- **A convention is wrong or missing** → fix the Conventions section. Both `builder` and
  `code-reviewer` read that one list, so a single edit changes what gets written *and* what gets
  checked.
- **Work items come from somewhere else** → change `source` in the Work items section.
- **Agents keep missing the same convention** → that's a profile defect, not a lesson. Make the rule
  more specific and cite a real precedent for it.
- **The whole stack changed** → re-run `/loop-init`.

## Why the lessons file works this way

`loop/LESSONS.md` is the part most worth understanding, because it's the part that makes the loop
improve instead of just repeat.

- **Every lesson is tagged with its audience** — `[planning]`, `[builder]`, `[reviewer]`, `[docs]` —
  and each stage receives only its own slice. A lesson aimed at planning delivered to a builder
  reaches the one stage that can no longer act on it. That bug existed in the origin project for
  three milestones.
- **Lessons get retired.** When a lesson becomes permanent instruction text, or a seeded lesson
  proves inapplicable, it's replaced by a one-line pointer. Without this the file grows forever and
  every agent pays for it on every spawn.
- **A lesson must be falsifiable.** "Write better tests" is not a lesson. "An assertion that cannot
  fail is worse than an absent one, because it reads as coverage" is.
- **`/retro` reads the commits, not just the journal.** The journal is agents reporting on
  themselves; the commits are the only record that can't be self-serving.

You start with 11 seeded lessons marked `[seed]`, inherited from the origin project. They're about
how *agents* fail rather than about any one stack, so they transfer. `/retro` retires any that turn
out not to apply here.

## Grilling

`/loop-plan` stress-tests the task breakdown with you before any code is written. This is where the
loop earns its keep: in the origin project, one task verified four framework claims during grilling
and cost zero respins, while its sibling skipped that and burned two failed builds on a claim that
turned out to be false.

It's the only stage that needs your attention, and it can't be delegated. When there isn't time for
the full session, `/loop-plan` has a five-question short form — a defined short form beats silent
abandonment, which is what actually happens under deadline.

The full session uses `mattpocock-skills:grill-with-docs` if you have it; the short form needs
nothing installed.

## Working in someone else's repo

`/loop-init` defaults to a zero committed footprint for any repo with other contributors: loop paths
go in `.git/info/exclude`, which is per-clone and never committed, so the shared `.gitignore` is
untouched and teammates see no agent config.

It also reads the repo's real commit format from `git log` rather than imposing one, respects branch
policy, and won't commit at all if you tell it not to.

## What this doesn't do

- **It doesn't replace human review.** `code-reviewer` is the pass before a human's, sized to catch
  what would waste their time.
- **It doesn't run unattended.** Every skill is a foreground invocation. Nothing is scheduled.
- **It doesn't skip stages to go faster.** Four spawns per task is the design, not an oversight —
  the cost is in what each spawn carries, which is why lessons are sliced.
