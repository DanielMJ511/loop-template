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

## Runtime surface

How to run this project and watch it behave. `qa` reads this and nothing else — it does not
improvise a start command or guess a port. `n/a` is a correct and common answer: a library, a
parser or a pure-function package has no runtime surface, and `qa` stops rather than inventing one.

- Start it: `<cmd, or "n/a — no runtime surface">`
- How to tell it is up: `<the observable signal — a log line, a health endpoint, a prompt, a window>`
- How to reach it: `<URL and port, CLI invocation, socket — whatever a check goes through>`
- Shut it down: `<cmd or signal, if anything beyond killing the process is needed>`
- End-to-end / UI harness: `<cmd, or "none">`
- Where errors surface: `<browser console, stderr, a log file path, a status endpoint>`
- Errors already present before any loop work: `<list, or "none observed on <date>">` — so a
  pre-existing error is not reported as a regression this task caused.

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

- Branch policy: `<e.g. never commit to main; branch as feature/<slug>>`
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

## Milestone-close gates

Steps that run once per milestone after the last task, in order. Each one either has a command or is
explicitly the user's to perform — a gate with neither is a gate that silently never runs.

1. `<e.g. security review — run the security-review skill>`
2. `<e.g. /retro>`
3. `<e.g. close the tracker item, on user confirmation>`

---

## Open questions

Things `/loop-init` could not determine, listed so they get resolved rather than assumed. Delete a
line when it is answered, and move the answer into the section above where it belongs.

- `<question>`
