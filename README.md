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

22 files, in four subfolders (`agents/`, `skills/`, `loop-templates/`, `hooks/`). None of them is a
`settings.json`, so copying the template never touches your own settings — including the six scripts
in `hooks/`, which the agents and `/orchestrate` register themselves in their own frontmatter. See
[The audit hook](#the-audit-hook) and [the loop guard](#the-loop-guard-and-the-compaction-checkpoint).

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
`code-reviewer`, `docs-writer`, `implementer`, `test-runner`, `verifier`, `security-auditor` or `teacher`, or a skill named
`loop-init`, `loop-plan`, `orchestrate`, `retro` or `loop-handoff`, copying replaces it. Rename or skip those rather than
overwriting a project's own tuned agents with these generic ones.

**Then check the agents resolve** before trusting a run — just ask Claude *"which agents are
available?"* in the project. It reads the loaded list from its own context, which is the only check
that proves the **harness parsed** the files rather than merely that they exist on disk. A typo in
one agent's frontmatter leaves the file sitting there and the agent silently missing. You should see
eight project agents; `/doctor` reports duplicate names if a project of your own already defines one.

Don't reach for `/agents` — as of Claude Code v2.1.198 it no longer lists anything, it just prints a
reminder to edit `.claude/agents/` directly. (`claude agents` on the command line is unrelated: it
manages background sessions, not agent definitions.)

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
/orchestrate     # drive each task through build → test → verify → review → record
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
| Working state — plan, journal, lessons, packets, audit log | `loop/` | Per unit of work |

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

- **Every lesson is tagged with its audience** — `[planning]`, `[builder]`, `[reviewer]`, `[docs]`,
  `[testing]`, `[verifier]`, `[security]` — and each stage receives only its own slice. A lesson
  aimed at planning delivered to a builder reaches the one stage that can no longer act on it. That
  bug existed in the origin project for three milestones.
- **One file, not one per audience.** A lesson can carry several tags and is written once. Eight of
  the twelve seeded lessons are multi-audience, so splitting the file per stage would duplicate most
  of it — starting with the lesson that says a fact worth stating twice will drift.
- **Lessons get retired.** When a lesson becomes permanent instruction text, or a seeded lesson
  proves inapplicable, `/retro` moves it to `loop/lessons-archive.md` as a one-line pointer. The
  pointer still stops a future `/retro` re-deriving it, but a retired lesson has no audience by
  definition — leaving it in the delivered file made every agent pay for it on every spawn, forever.
- **A lesson must be falsifiable.** "Write better tests" is not a lesson. "An assertion that cannot
  fail is worse than an absent one, because it reads as coverage" is.
- **`/retro` reads the commits, not just the journal.** The journal is agents reporting on
  themselves; the commits are the only record that can't be self-serving.

You start with 12 seeded lessons marked `[seed]`, inherited from the origin project and its first adoption. They're about
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

## Which model runs what

Every stage pins its own model **and effort level** in frontmatter, so the loop costs the same
whatever your session settings are, and you never toggle `/model` by hand.

| Stage | Model | Effort | Why |
|---|---|---|---|
| `/loop-init`, `/loop-plan`, `/retro` | `opus` | `high` | Their output is durable and nothing downstream re-checks it |
| `implementer`, `security-auditor` | `opus` | `high` | The escalation tier diagnoses rather than retries; the auditor reads a whole unit at once |
| `/orchestrate` | `sonnet` | `medium` | Routing against heavily-scripted rules |
| `builder`, `code-reviewer`, `verifier` | `sonnet` | `medium` | The standard tier, all re-checked downstream |
| `docs-writer`, `/loop-handoff` | `sonnet` | `low` | Transcription into a fixed shape |
| `test-runner` | `haiku` | `low` | High-output, low-reasoning: run the suite, digest the log |

`teacher` is deliberately absent: it inherits your session's model and effort, because it isn't part
of the loop.

**`builder` at `medium` is the deliberate lever.** It's the most-spawned agent in the system, and
everything after it — tests, runtime verification, review — re-checks its work, so it's the one place
where buying effort back is cheapest and most easily caught if wrong. Treat it as a measurement, not
a settled answer: run a unit at `medium` and one at `high`, then compare `implementer` line counts in
`loop/AUDIT.log`. If escalations per unit don't rise, the lower setting is free. That's the same
method this README recommends below for the `/orchestrate` model choice, and the audit log exists
partly to make it cheap.

The rule is **durability, not difficulty**. `/loop-plan` writes packets that no later stage
re-verifies, `/loop-init` writes the profile every agent then trusts, and `/retro` writes lessons
that persist across milestones — a bad line in any of those is paid for repeatedly. `/orchestrate`
looks like the important one because it drives everything, but its judgment calls (prerequisite vs.
test failure, review severity, gate substitution) are all spelled out in the skill text; it is
following a decision table, not deriving one.

**If you'd rather run `/orchestrate` on Opus**, delete the `model:` line from
`.claude/skills/orchestrate/SKILL.md` and it inherits your session model. Worth measuring rather
than guessing: run a unit each way and compare `implementer` line counts in `loop/AUDIT.log`. If
escalations per unit don't rise on Sonnet, the downgrade is free.

One wrinkle: a `model:` override lasts for the rest of the current turn and then reverts. An
`/orchestrate` run that stops to ask you something resumes on your session model, not Sonnet.

## The audit hook

Optional, offered by `/loop-init`, and the only piece of the loop that goes in a settings file.

`.claude/hooks/audit-subagent.ps1` (and its `.sh` twin) is a `SubagentStop` hook. The harness runs it
as each spawn ends, and it appends one line to `loop/AUDIT.log`:

```
2026-08-17T17:38:53Z | builder          | T-003 | -                 | 7f3a91cc
2026-08-17T17:38:54Z | test-runner      | T-003 | TESTS PASSED      | bb20e4d1
2026-08-17T17:38:55Z | verifier         | T-003 | NOT VERIFIED      | 41c07de2
2026-08-17T17:41:02Z | code-reviewer    | T-003 | CHANGES REQUESTED | c9d81aa2
2026-08-17T18:02:17Z | security-auditor | T-006 | NO FINDINGS       | 5b1e9f34
```

**Why it earns its place:** `/retro` is built on the premise that agents reporting on themselves
can't be trusted, which is why it reads the commits too. This is a third record, and a stricter one —
written by the harness, so no agent can shape it, and written per spawn rather than per completed
task, so it's the only record that survives a run that died mid-task. When `docs-writer` records
"builder only, no respins" and the log shows three `builder` lines, that gap is the lesson.

It is deliberately structural — who ran, when, on what, with what verdict token. No report content,
so it never leaks a long summary and never needs truncating. The narrative stays in `loop/STATE.md`.

**Nothing to install.** Each of the seven spawned loop agents declares it in its own frontmatter as a
`Stop` hook; Claude Code converts that to `SubagentStop` and unregisters it when the agent finishes.
So it ships with the template, touches no settings file, and only ever fires for the loop's own
agents — an `Explore` or `Plan` spawn in the same project writes nothing.

Each of those agents ends its report with a `VERDICT: <token>` line, which is what the hook records.
Scanning the report's prose is only a fallback, and a poor one: it can't read a negation, so
"I am not APPROVED-ing this yet" logs as `APPROVED`.

Two things all three hooks need, both of which fail silently:

- **`jq` or `python3` on PATH**, to read the hook payload. With neither, you get an empty log that
  looks identical to "nothing has run yet".
- **Git Bash, on Windows.** Claude Code runs hook commands through bash, falling back to PowerShell
  on Windows only when Git Bash isn't installed — so the shipped `sh` command works whenever Git
  Bash is present, *even though `sh` is not on the Windows `PATH`*. Don't test the `PATH`; test for
  Git Bash. Without it, point each `command` line at the `.ps1` twin — get the full list from
  `grep -rl 'hooks/' .claude/agents .claude/skills` rather than from memory, since editing all but
  one leaves a hook that silently never fires. That's the one sanctioned edit to a machinery file,
  because it's platform-specific rather than project-specific.

Check the log has content after your first `/orchestrate` run.

## The loop guard and the compaction checkpoint

Two more hooks, declared in `/orchestrate`'s own skill frontmatter rather than an agent's — so they
register when you run `/orchestrate` and cover the whole session. Still no `settings.json`.

**`Stop` → loop guard.** When the session tries to stop, it checks the durable state against the
budgets in your profile and warns about a task that burned more spawns than allowed, a task the
ladder gave up on, and a task sitting at its final attempt.

It is **advisory and never blocks.** Exit code 2 on a `Stop` hook prevents Claude from stopping,
which in a foreground session you're sitting in front of is a foot-gun rather than a guardrail — so
the guard exits 0 and speaks through `systemMessage`, the one documented route to you from a
non-blocking hook. (A hook that "warns" by echoing to stdout or stderr is invisible: on exit 0 both
go to the debug log and nowhere else.) When nothing is over budget it prints nothing at all, which is
what makes it safe to leave registered for a whole session.

**`PreCompact` → checkpoint.** Fires immediately before the orchestrator's context is compacted —
the one moment no agent can anticipate from inside its own turn, and exactly when it loses the
working detail it hasn't flushed.

It never reads the transcript, because it doesn't need to. Everything a resume needs is already on
disk:

| Field | Derived from |
|---|---|
| In-flight task | first unchecked `T-00X` in `PLAN.md` whose packet isn't `blocked` |
| Attempt counter | that packet's own `Status:` line, verbatim |
| Stage, last verdicts | the last spawns for that task in `AUDIT.log` |
| Uncommitted changes | `git status --short` |

It writes the same `loop/HANDOFF.md` shape `/loop-handoff` writes, `Status: active` included, so
`/orchestrate` resumes from a compaction-written checkpoint by exactly the same path as a
hand-written one. There is no second resume mechanism.

The one thing it won't claim is **tree state** — whether a change is half-applied is a judgment, and
a shell script has no business making it. That field says so and tells you to run `git diff`.

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
- **It doesn't skip stages to go faster.** Four to five spawns per task is the design, not an
  oversight — the cost is in what each spawn carries, which is why lessons are sliced and why every
  agent has a length budget on what it hands the next one. Budget for more than that on a bad task:
  one that fails twice and escalates costs roughly nine, since each respin re-runs verification and
  review too.

## The security audit

`security-auditor` (Opus, read-only) runs once at the close of a unit, over everything that unit
changed. It is a built-in step in `/orchestrate`, not a profile gate — an earlier version of this
template made it a gate and it silently never ran, because nothing filled the section in.

**Why it isn't just more review:** `code-reviewer` sees one task's diff at a time, and the defects
worth catching usually aren't in one diff. A route added in T-001, an authorization check relaxed in
T-003, a field added to a response in T-005 — each diff individually reasonable, the combination
exposing something. Nothing else in the loop ever looks at the whole change set.

Three design decisions keep it from becoming noise, which is how this kind of stage normally dies:

- **Unit-scoped, not repo-scoped.** A whole-repo audit on a codebase with history re-reports the
  same pre-existing findings every milestone until nobody reads it. It reads widely — following a
  changed function to its callers, checking what a new route sits behind — but reports only on what
  this unit introduced. Pre-existing issues go in a separate labelled list.
- **Every finding names a path to harm.** "Input validation is missing" is a category nobody can
  act on. The entry point, the path from input to impact, who can reach it, and what they get — or
  it isn't a finding.
- **"No findings" is the expected outcome.** Most units don't introduce a security defect. A stage
  that always produces findings is manufacturing them, and it gets ignored exactly when it finally
  has something real.

It never fixes anything. Findings go to you with severity, because you own integration — anything
worth acting on becomes a new unit via `/loop-plan` or a tracker item. If your project has its own
SAST or dependency scan, `/loop-init` records it and both run: a scanner knows published
vulnerabilities and pattern signatures, the auditor knows what the unit was trying to do.

## Verifying against the running app

`verifier` is the one stage that tests the application rather than the tests. After `test-runner`
passes, it starts the app, exercises the task's acceptance criteria, and reports what it observed —
the actual status code, body, log line or output.

**Why it's worth a fifth spawn:** a green suite is evidence about the tests. It cannot see an
endpoint that was never registered, a migration that didn't run, config bound to the wrong key, or a
200 returned over a swallowed exception. Those reach a user without ever reaching a red test.

It's conditional on both counts, so it costs nothing where it has nothing to say:

- `/loop-init` records `applicable: no` with a reason for a library or a CLI with no process to
  start, and the stage never runs.
- `/loop-plan` marks each acceptance criterion `[runtime]` if it's observable against the running
  app. A refactor, an internal invariant or a docs task has none, and the stage is skipped.

`NOT VERIFIED` enters the same escalation ladder as a test failure. `BLOCKED` — the app wouldn't
start — does not, for the same reason a stopped Docker daemon doesn't burn a retry.

Where a project has **no test suite**, this becomes the primary gate rather than an optional one.
That's the honest answer to a green run that executed zero assertions.

### Browser-facing work

`verifier` has no browser. Its tools are a shell and file access, so it reaches a rendered page only
by driving the harness **your project already owns** — `/loop-init` detects Playwright, Cypress,
Puppeteer or WebdriverIO, verifies one spec actually runs, and records the invocation in the
profile's Browser observation fields.

If your project has a UI and no harness, the profile records that too, and a criterion needing a
rendered page comes back `NOT VERIFIED`. That is deliberate. The alternative — a stage that reports
success on something it structurally cannot see — is the failure three of the seeded lessons are
about, and it's worse than an honest gap because it closes the question.

**No Playwright agent ships with this template, on purpose.** Nic's loop has a Playwright-driven `qa`
agent; bundling one here would break the one rule, since a browser harness is a stack choice and
`.claude/` holds nothing project-specific. It would also duplicate work for the projects that already
own Playwright — their specs *are* the test suite, so `test-runner` already runs them — and it would
depend on an install the template can't perform. Detection adapts to whichever harness you chose;
bundling would pick one for you.
