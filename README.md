# Loop template

An agent build loop that adapts itself to a project. Copy it in, run `/loop-init`, start looping.

Extracted from a real project where it drove nine milestones. Across four of them it escalated to
the expensive model twice and gave up on a task zero times.

## Adopt it

Copy `.claude/` into your project, then run `/loop-init`. That's the whole adoption — `/loop-init`
detects the stack, commands, conventions, tracker and git policy, proposes what it found with
evidence for each claim, and writes `loop/PROFILE.md`. **You are not asked to fill in a config file,
and no agent has to read this loop's machinery to work out how to adapt to your project.**

### Copying it in

20 files, in three subfolders (`agents/`, `skills/`, `loop-templates/`). None of them is a
`settings.json`. The loop's hooks ship as a *fragment*, and `/loop-init` merges them into whatever
`.claude/settings.json` you already have, showing you the diff first — so copying this template in
never overwrites your own settings.

**If the project has no `.claude/` folder yet** — copy the whole folder in:

```bash
cp -r /path/to/loop-template/.claude .
```
```powershell
Copy-Item -Recurse \path\to\loop-template\.claude .
```

**If the project already has a `.claude/` folder** — and any project you've used Claude Code in
will — copy the *contents*, don't paste the folder on top:

```bash
cp -r /path/to/loop-template/.claude/. .claude/
```
```powershell
Copy-Item -Recurse \path\to\loop-template\.claude\* .claude\
```

Note the `/.` and the `*`. Without them, `cp -r src/.claude .` copies the folder *inside* the
existing one and you get `.claude/.claude` — broken, and silently so.

**Watch for name collisions.** If the project already defines an agent named `builder`,
`code-reviewer`, `docs-writer`, `implementer`, `qa`, `security-auditor`, `test-runner` or `teacher`, or a skill named
`loop-init`, `loop-plan`, `orchestrate`, `retro` or `loop-handoff`, copying replaces it. Rename or
skip those rather than overwriting a project's own tuned agents with these generic ones.

**Then check the agents resolve** before trusting a run: confirm `builder` and `test-runner` appear
in your available agents. Takes seconds and derisks everything downstream.

### A brand-new project

`/loop-init` finds nothing to detect and switches to **greenfield mode**: four questions (what
you're building, the stack, whether a skeleton exists, whether others will contribute), then a
provisional profile with every field marked `(assumed)` and **the conventions section deliberately
left empty**. That emptiness is the point — inventing a layering rule for code that doesn't exist
gives you a constraint that fights the project's real shape a week later. Conventions fill in as
decisions get made.

Expect `test gate: no test suite`, so verification falls back to build and lint. Making the test
harness your first task is usually right; that's what turns the gate real.

### A long-settled project

`/loop-init` runs **brownfield mode**: finds every manifest, reads CI, derives the commands and
verifies them by running, reads conventions off your recently-changed source files, and infers your
commit format from `git log` rather than imposing one. It shows you everything with its evidence and
waits for confirmation.

Two things matter more here than anywhere else:

- **Read the conventions section before approving it.** It shapes every line the loop writes. Rules
  detected from a single example say so — check those first.
- **Choose the local footprint** for any repo with other contributors (see below). Teammates seeing
  unexplained agent config in a PR is a real cost.

### Then, either way

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

**Grilling is not bundled with this template, and the loop does not depend on it.** There are two
tiers:

- **Full session** — uses `mattpocock-skills:grill-with-docs`, a marketplace plugin. It is *not* part
  of `.claude/`, so copying this template does not bring it along. It also cannot be model-invoked
  (`disable-model-invocation: true`), so `/loop-plan` asks you to run it rather than running it
  itself.
- **Short form** — built into `/loop-plan` step 4. Five questions, nothing to install, works in every
  project immediately.

If you want the full session available everywhere, install the plugin at **user scope** via
`/plugin`, not project scope. A plugin installed with project scope is recorded against that one
project path and will not appear in your next repo — which is the usual reason grilling seems to
"disappear" when you adopt the loop somewhere new.

Either tier satisfies step 4. `/loop-plan` records which one ran in `loop/PLAN.md`, so the journal
never implies a full session happened when it didn't.

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
  the cost is in what each spawn carries, which is why lessons are sliced. Four is the clean path;
  a task that fails twice and escalates costs roughly nine, since every respin re-runs the test and
  review stages too. Budget against that number, not the happy one.
