# PROFILE — <project name>

Written by `/loop-init` on <date>. Mode: <brownfield | greenfield>.

**This is the loop's only project-specific file.** Every skill and agent reads it instead of
hardcoding a build command, a convention, or a tracker. If the loop does the wrong thing for this
project, the fix belongs here, not in `.claude/`.

Each fact below carries the evidence that established it. A fact with no evidence is a guess, and
must say so — an agent that cannot tell a detected fact from an assumed one will act on both with
equal confidence. Mark provisional fields `(assumed)` and they will be treated as open questions
rather than constraints.

---

## Commands

| Purpose | Command | Evidence |
|---|---|---|
| Build / compile | `<cmd>` | `<file or command that established it>` |
| Full test suite | `<cmd>` | |
| Single test class/file | `<cmd>` | |
| Single test case | `<cmd>` | |
| Lint / format check | `<cmd, or "none">` | |
| Type check | `<cmd, or "none">` | |
| Run the app locally | `<cmd, or "n/a">` | |

**Prerequisites** — anything that must be true before the test suite can pass, and the exact
symptom when it isn't. `test-runner` checks these first, because a missing prerequisite produces a
failure that reads like a code bug.

- `<e.g. container runtime running — check with "docker version"; when down, the integration tests
  emit a connection stack trace that reads like a code bug>`

**Test gate status** — `<real gate | no test suite | gate exists but empty>`. The loop's only automated
verification. Record what was **observed**, not what the command returned:

- If a real gate: `<N tests observed passing on <date>>`.
- If no test suite: say so plainly, and what the test command does when run anyway (e.g. "exits 0
  having run nothing"). `/orchestrate` reads this and substitutes the build, type-check and lint
  commands as the gate instead. Without this field the loop reports every task as verified while
  executing zero assertions.

**Test scope default** — `<full suite | changed-area only>`. Set this to changed-area only when the
full suite is slow enough that agents will be tempted to skip it; `/orchestrate` still runs the
full suite once before any commit.

---

## Runtime verification

How `verifier` exercises a task's acceptance criteria against the running application. A green suite
is evidence about the tests; this is the only stage that observes the app itself.

Set `applicable: no` and leave the rest blank for a library, a pure CLI with no process to start, or
anything with nothing to run — `/orchestrate` then skips the stage instead of inventing a way to
verify. Say *why*, so a later reader can tell a considered "no" from an unfilled field.

- **applicable**: `<yes | no>` — `<if no, why>`
- **Start**: `<command that brings the app up>`
- **Readiness**: `<how to know it is up — a health endpoint, a port, a log line. Never a fixed sleep.>`
- **Reach it at**: `<base URL, port, socket, or how to invoke the CLI>`
- **Stop**: `<command to shut it down and clean up>`
- **Fixtures / seed**: `<command, or "none">`
- **Logs**: `<where the app's output goes — a file, stdout, a container log command>`
- **Confirm it is running current code**: `<how — a build stamp, a version endpoint, or "restart it">`

### Browser observation

`verifier` has no browser of its own — it drives whatever harness **this project already has**, through
its shell. Nothing is installed for it. These two fields decide whether a UI acceptance criterion can be
observed here at all, so a blank one silently converts "we cannot check this" into "this passed".

- **Browser harness**: `<playwright | cypress | puppeteer | webdriverio | none>` — Evidence:
  `<config path>`. Run one spec headless: `<the exact verified invocation>`
- **UI-observable criteria**: `<verifier drives the harness above | none — this app has no UI | not
  verifiable here — no harness, so UI criteria are the user's to confirm>`

Record `none` as a real answer with its reason. Where there is no harness and the app *does* have a UI,
a criterion that needs a rendered page comes back `NOT VERIFIED` rather than being skipped quietly —
that is the honest outcome, and it is the signal that a harness deserves its own task.

---

## Conventions

The rules that apply to every change regardless of what a task packet says. `builder` applies
these; `code-reviewer` checks them. One list, two directions — never restate it in an agent file.

Write each as a rule plus how it is enforced, because an unenforced rule is a comment (a guard that
cannot fail a build is not a guard):

- **<rule>** — `<how it is enforced: a test, a lint rule, a schema validation, or "convention only,
  reviewer must catch it">`. Evidence: `<path:line where this pattern is visible>`.

### Existing convention docs

Reference these; do not copy their content here. A rule stated in two places drifts.

- `<path>` — `<what it governs>`

### Domain language

- Source of truth: `<path, or "none — see Terms below">`
- Terms this project uses, and the synonyms it deliberately avoids: `<list, or "not established">`

---

## Architecture

- Layering / module boundaries: `<description, or "none established">`
- Where new code of each kind goes: `<paths>`
- Patterns to match rather than invent: `<path examples worth reading before writing>`
- Decision records: `<directory, or "none">` — `<format note: one decision per file, H1 states the
  decision as a sentence, etc.>`

---

## Work items

How the loop learns what to build. `/loop-plan` reads `source` and ignores the other two blocks.

**source**: `<milestone-chain | ticket | prompt>`

### If `milestone-chain`

- Tracker: `<e.g. GitHub Issues via the gh CLI>`
- How to list candidates: `<command>`
- How the next one is chosen: `<e.g. the single open issue with no open blocking dependency>`
- Required body sections: `<list, e.g. ## Goal, ## Deliverables, ## Verification>`

### If `ticket`

- Tracker: `<GitHub | Jira | Linear | other>`
- How to fetch one by id: `<command>`
- Sections are **not** assumed. Goal and verification criteria get derived from the ticket body and
  confirmed with the user during grilling.

### If `prompt`

- The user's description is the work item. Nothing is fetched.
- Before decomposing, restate the goal and the verification criteria back to the user and get
  confirmation — a prompt has no Verification section to inherit, and inventing acceptance criteria
  silently is how a task ends up unfalsifiable.

### Filing follow-up work

- Create an item: `<command, or "propose to the user only — this project has no tracker">`
- Label / field conventions: `<...>`
- **Never file unilaterally.** Propose it and file only on the user's agreement.

---

## Git

- Branch policy: `<e.g. never commit to main; branch as <type>/<slug>>` — reuse the commit
  message types below, so a remediation unit gets `fix/...` rather than `feature/...`. Set this
  from **where this project's gate sits**: a blocking pre-merge gate (CI, review) makes committing
  to the default branch defensible; without one the default is never commit to it, because
  `security-auditor` reviews a unit *after* every task has already been committed and a finding
  there needs somewhere to land.
- Commit message format: `<e.g. "<type>: <summary> (T-00X, #<n>)">`, types: `<list>`
- Evidence: `<git log --oneline -20 output shape, or a hook / PR template path>`
- Commit cadence: `<per task | per milestone | never — user commits manually>`
- Push: `<never automatic | on request>`
- Pre-commit gate: `<e.g. full test suite must pass; plus any hook that runs>`

---

## Loop footprint

- Loop files committed to this repo: `<yes | no>`
- If no: excluded via `<.git/info/exclude (local-only, never committed)>`
- Rationale: `<e.g. shared work repo; teammates should see no agent config>`

---

## Loop budgets

Ceilings the `Stop` hook checks when the session tries to stop. They are project policy, not
machinery, which is why they live here rather than in `.claude/`.

The guard is **advisory**: it surfaces a warning and never prevents stopping. Every skill is a
foreground invocation you are sitting in front of, so a hook that blocked would be a foot-gun rather
than a guardrail.

- **Max spawns per task**: `<n — default 10 if this line is missing or unparseable>`. A clean task
  costs 4-5 spawns; one that fails twice and escalates costs roughly 9. A task past 10 is either
  stuck in a respin cycle or was decomposed too large, and both are worth seeing before you walk away.
- **Max tasks per `/orchestrate` run**: `<n, or "unbounded — the plan's task list is the limit">`.
  `/orchestrate` walks a finite list and stops, so this is a planning ceiling rather than an enforced
  one — the guard does not check it, because a run has no durable boundary it could read.

---

## Milestone-close gates

Steps that run once per milestone after the last task, in order. Each one either has a command or is
explicitly the user's to perform — a gate with neither is a gate that silently never runs.

**A gate is a command or a human action, never a skill.** `/orchestrate` walks this list from inside
its own run; listing `/retro` or `/loop-plan` here asks it to invoke a skill mid-skill, and the two
sets of instructions then compete. `/retro` is what the user runs *after* `/orchestrate` returns.

Replace every line below — a placeholder left here is a gate that never runs, and the security
review is the one nobody notices is missing.

1. `<e.g. the project's SAST or dependency scan — command, or "none">`
2. `<e.g. close the tracker item, on user confirmation>`
3. `<USER: manual smoke test of the flows this milestone touched>`

`/loop-init` fills this in from what the project already has. `none — the user closes milestones
manually` is a valid answer; a leftover placeholder is not.

**`security-auditor` is not listed here.** `/orchestrate` spawns it at every unit close as a built-in
step, so it cannot be lost by an unfilled profile — which is what happened to this gate before it
was built in. A scanner recorded above runs *as well*: it knows published vulnerabilities and
pattern signatures, the auditor knows what the unit was trying to do.

---

## Open questions

Things `/loop-init` could not determine, listed so they get resolved rather than assumed. Delete a
line when it is answered, and move the answer into the section above where it belongs.

- `<question>`
