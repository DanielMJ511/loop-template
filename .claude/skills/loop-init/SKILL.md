---
name: loop-init
description: Detect this project's stack, conventions, tracker and git policy, and write loop/PROFILE.md so the loop can run here without any hand-editing. Use once per project when adopting the loop, or when the user says "/loop-init". Also use to re-detect after a project's build or conventions change materially.
model: opus
---

Run in the main session. Detect, propose, write the profile, stop. **Never plan a milestone, write a task packet, or touch application code** — `/loop-plan` does the first two and `builder` does the third.

Your entire job is to make every later stage able to work here without reading a single machinery file. If you leave a field guessed where it could have been detected, every downstream agent inherits that guess and acts on it with full confidence.

## 1. Decide the mode

```
git -C . log --oneline -1 2>/dev/null | head -1
```

- Output, and source files present → **brownfield**. Conventions already exist in the code, whether or not anyone wrote them down. Detect them.
- No commits, or no source files → **greenfield**. Nothing to detect. Go to step 6.

If the repo has history but only scaffolding (a generated starter with no real code yet), treat it as greenfield and say so — detecting "conventions" from a framework's `init` output produces confident nonsense.

## 2. Detect commands and prerequisites

Read the build manifest and the CI config together. They are authoritative for **different things**, and conflating them produces a profile that's wrong in a way nobody notices:

- **The manifest is authoritative for the local invocation** — the command an agent should actually run. Record this one.
- **CI is authoritative for which commands must pass, and for what the environment needs.** Its `services:`, `env:` and setup steps are the best available list of prerequisites, usually better than the README's.
- **CI-only flags are not part of the command.** `--coverage`, a verbose or JUnit-XML reporter, `--batch-mode`, `--ci`, `--no-watch`, a fail-fast threshold: these exist for a build server. Do not fold them into the recorded command. Note them in the Evidence column if they matter, and be aware that a reporter flag changes the output shape `test-runner` parses — which is a reason to *avoid* it locally, not to adopt it.
- **A README that disagrees with the manifest is stale.** That's the drift worth reporting.

If CI runs a command the manifest doesn't expose at all, that's a real finding: record the CI form and note that there is no local equivalent.

Look for the build manifest for the stack (`package.json`, `pom.xml`, `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Gemfile`, `*.csproj`, `mix.exs`), then `.github/workflows/`, `.gitlab-ci.yml`, `Makefile`, `justfile`, `Taskfile.yml`, then the README's build section.

**Find all of them, not the first one.** A repo with a `package.json` for tooling and a `pom.xml` for the application is not a JavaScript project, and picking whichever manifest you found first is a mistake you won't notice until a builder runs the wrong test command. When more than one manifest exists, work out which one builds the code the loop will be changing — CI usually settles it, and if it doesn't, ask. If the project genuinely has two live stacks, record commands for both and say which is the default.

Determine: build, full test suite, **single test file**, **single test case**, lint, type check, run-locally. The two single-test forms matter more than they look — without them, every `test-runner` spawn runs the entire suite, and on a slow suite that is where the loop's time goes.

**Most manifests do not expose a single-test script.** Outside a few build tools, you will find a `test` script and nothing narrower. Do not leave those rows blank, and never fill them with the full-suite command — a profile whose "single test" command runs everything is worse than an empty row, because it looks answered.

Derive them from the **test runner** instead, which you identify from the manifest's dev dependencies or the test files' imports. Then **verify by running** — an unverified single-test invocation is the single most likely thing in this profile to be wrong, because the syntax varies by runner and by version:

- Identify the runner (from `devDependencies`, a test config file, or what the test files import).
- Find its file-selection and name-filter flags. Most runners have both: one to run a path, one to match a test name.
- Run each form once against a real test file from this repo and confirm it executes fewer tests than the full suite. Record the exact invocation that worked, not the one the docs suggest.
- If a package-manager script wrapper needs an argument separator (`npm test -- <args>`), include it in the recorded command — omitting it silently passes the flags to the wrong process.
- **If the project has no tests, these forms cannot be verified.** Record the runner's documented syntax, mark both rows `(assumed)`, and note that they stay unverified until a suite exists. Do not present an unrun command as a detected fact.

**Prerequisites are as important as the commands.** Find what must be true for the suite to pass: a container runtime, a running service, an env file, a seeded database, a compiled native dependency, a specific runtime version. For each, record the check command *and the symptom when it's missing* — a missing prerequisite produces a failure that reads like a code bug, and `test-runner` needs to distinguish them without guessing.

**Find the install step before verifying anything.** On a fresh clone nothing is installed, so every command you try fails with a "command not found" for a tool that is in fact configured correctly. Look for the dependency-install command (from CI's setup steps, which always have one) and record it as a prerequisite. Run it, or ask the user to, before attempting verification. Recording "lint is broken" when the truth is "dependencies aren't installed" writes a confidently wrong profile, and every later agent inherits it.

Then verify by running: the build command, the lint command, and each single-test invocation. Do not run the full suite — it can be slow, and the single-test run already proves the invocation shape.

**When a command fails, classify it before recording it.** These are three different facts and only the last is a project defect:

- **Not installed** — a "command not found" / "not recognized" for a tool the manifest declares. Not a finding. Install and retry.
- **Environment missing** — it ran but couldn't reach a database, port, or credential. Not a finding about the code: this is a **prerequisite**, and it belongs in the Prerequisites list with its symptom.
- **Genuinely broken** — it ran, had what it needed, and failed anyway. This one is a real finding. Record it in Open questions with the actual error, because a project whose documented build doesn't work is exactly what the loop needs to know before a builder blames itself.

Never report a failure without saying which of the three it is. Guessing here is how a prerequisite ends up recorded as a broken build.

### Prove the test gate is real

**The test command is the loop's only automated gate. Establish that it can actually fail before recording it.** A command that always succeeds is worse than no command, because `/orchestrate` treats its exit code as proof and every task sails through.

Run the test command and read what it reports, not just its exit code:

- **How many tests ran?** If the answer is zero, this is not a gate. Several toolchains exit 0 on an empty run with no warning at all — `dotnet test` in a repo with no test project restores, prints nothing about tests, and returns success.
- **Does a test project or test directory exist?** Search for it directly. Do not infer its existence from the test command succeeding.

Record the outcome in the profile as a first-class fact, never as a blank:

- **Real gate** — tests exist and ran. Record the count you observed, as the baseline. **Measure it from a clean state**, and record the command sequence that produced it. Incremental and cached runs under-report: on a real project an incremental build showed 0 warnings where a clean build showed 1, which would have let a "count unchanged" gate pass a regression. A baseline measured off a cache is not a baseline. If a clean run is prohibitively slow, record that the figure is incremental and say so in the same sentence.
- **No test suite** — the project has none. Say so explicitly, in those words, plus what the test command does when run anyway (typically: exits 0 having done nothing). `/orchestrate` reads this and substitutes a different gate; without it, the loop silently verifies nothing.
- **Gate exists but is empty or trivial** — a test project with no meaningful assertions. Treat as "no test suite" and say why.

When there is no test suite, tell the user plainly at step 7 that the loop's verification stage will not be load-bearing until one exists, and recommend making a test harness the first task. That is their call, not yours — but they must make it knowingly, because the failure mode is invisible.

## 2b. Detect how to run and observe the app

The profile's Runtime verification section. `verifier` reads it to exercise a task's acceptance criteria against the running application — the loop's only check that isn't a claim about the tests.

**Decide `applicable` first, and be willing to say no.** A library, a pure CLI with no process to start, or anything with nothing to run gets `applicable: no` plus the reason. A recorded "no" is a real answer; a blank section is a stage that quietly never runs.

If it does apply, find and record: the start command; the **readiness signal** (a health endpoint, a port opening, a log line — never a fixed sleep, which is how a verifier reports a false failure on a slow morning); where to reach it; the stop command; any seed or fixture step; where the app's logs go; and how to confirm a running process is actually current code.

Look in this order — `docker-compose.yml` and `Procfile`, the manifest's run/serve/start script, CI's end-to-end or smoke job if there is one, then the README's "getting started" section. A compose file is usually the best source, because it names the ports, the dependencies and the health checks in one place.

**Verify by starting it once.** Bring the app up, confirm the readiness signal actually fires, reach it, then stop it. An unverified start command is close to useless: `verifier` will report `BLOCKED` on every task and the stage will look broken rather than unconfigured. If it can't be started here — a credential you don't have, a service that isn't reachable — record the commands, mark them `(assumed)`, and list it in Open questions.

## 3. Detect conventions

This is the section that decides whether the loop produces code that looks native or code that looks bolted on. Read real files — pick the two or three most recently-changed non-trivial source files plus their tests.

Determine: layering and module boundaries; where each kind of new code goes; how data crosses the boundary to callers; dependency wiring style; error and failure handling; how schema or data-shape changes are made; test placement and naming; what "done" looks like for a change (does a change normally arrive with tests, docs, a changelog entry).

Two rules on how you write these down:

**Cite evidence, never assert.** Each convention gets a `path:line` where the pattern is visible. A reviewer flagging a violation needs to point at the precedent, and a wrong detection needs to be visibly wrong.

**Record how each rule is enforced** — a test, a lint rule, a compiler or schema check, or "convention only, reviewer must catch it". This distinction is the difference between a rule the loop can rely on and a rule the loop must actively police. Mark the unenforced ones: they are where review attention goes.

### Reference existing docs, do not absorb them

If the project already has `CONTRIBUTING.md`, `CLAUDE.md`, `AGENTS.md`, a style guide, or a decision-record directory, **link to it and summarize what it governs in one line.** Do not copy its rules into the profile. Two copies of a rule drift apart, and then agents follow whichever they read first — the exact failure the loop's own lessons file warns about. If such a doc already covers conventions thoroughly, the profile's conventions section should be mostly pointers.

## 4. Detect work-item source and tracker

Establish where work comes from, in this order:

1. Ask what the user actually wants to loop on. Their answer outranks detection — a repo can have GitHub Issues enabled and still receive its real work as Jira tickets or as verbal requests.
2. Check what exists: `gh issue list --limit 3` for GitHub Issues; issue references in recent commit subjects (`ABC-123`, `#123`) to spot an external tracker; a `.github/ISSUE_TEMPLATE/` directory.

Set `source` to exactly one of:

- **`milestone-chain`** — an ordered set of tracked milestones with a consistent body shape. Record how to list them, how the next is chosen, and the required sections.
- **`ticket`** — work arrives as individual tracked items with no guaranteed structure. Record the fetch command. Do not record required sections; there are none.
- **`prompt`** — no tracker item. The user describes the work. Correct for a personal project, a greenfield start, and most single work tasks.

When in doubt choose `prompt`. It is the only source that cannot be wrong, and `/loop-plan` handles the others by fetching *into* the same shape anyway.

## 5. Detect git policy and footprint

```
git log --oneline -20
git symbolic-ref --short HEAD
ls .github/pull_request_template.md .husky .pre-commit-config.yaml 2>/dev/null
```

Infer the commit message format from what's actually there — if 20 commits show `type: summary`, that's the format; if they show `[ABC-123] summary`, that's the format. Record it as a pattern with a real example.

Then determine branch policy, whether the loop may commit at all, and the pre-commit gate.

**Ask about footprint explicitly, in a shared repo:** should loop files be committed, or stay local? Default to local for any repo with other contributors — teammates seeing unexplained agent config in a PR is a real cost. Local means adding the loop paths to `.git/info/exclude`, which is per-clone and never committed, so the shared `.gitignore` is untouched.

## 5b. Establish the milestone-close gates

`/orchestrate` walks the profile's Milestone-close gates after the last task of a unit. **If you leave that section as template placeholders, it walks a list of placeholders and every gate silently never runs** — and the one people notice missing last is the security review, because nothing fails when it is skipped.

Propose a concrete list. Start from what the project already has, then fill the gaps:

- **Security review.** Look for an existing one first: a SAST step in CI (`codeql`, `semgrep`, `snyk`, `trivy`, `bandit`, `npm audit`, `dependency-check`), a scheduled workflow, or a documented process. If one exists, record that command. If none does, propose `claude -p /security-review` as the gate rather than leaving it blank — a read-only pass at the milestone boundary is the loop's only holistic look at the change set, since `code-reviewer` only ever sees one task's diff.
- **Closing the work item.** From the tracker detected in step 4, if any. Mark it as requiring user confirmation.
- **Anything the project's own process already requires** at a release or merge boundary — a changelog entry, a version bump, a migration check, a manual smoke test. Read `CONTRIBUTING.md` and the PR template for these rather than inventing them.

Two rules on how you write them, both from the template:

- **A gate is a command or a human action, never a skill.** `/orchestrate` runs these from inside its own invocation; listing `/retro` or `/loop-plan` there asks it to invoke a skill mid-skill. `/retro` is what the user runs after `/orchestrate` returns.
- **A gate with neither a command nor a named owner is a gate that never runs.** Prefix the user's ones with `USER:` so the distinction survives.

If the user wants no gates at all, record that explicitly — `none — the user closes milestones manually` — rather than leaving placeholders. An empty section and a deliberately empty section look identical six weeks later.

## 6. Greenfield: write a provisional profile instead

Nothing to detect, so ask for the minimum and mark everything provisional.

Ask only what blocks the first task: what is being built and in what language/stack; whether a project skeleton exists yet or the loop's first task creates it; how they want to be told what to build (almost always `prompt`); and whether this repo will have other contributors.

Then write the profile with:

- Commands filled in from the stack's conventional defaults, each marked `(assumed)`.
- Conventions **left open** — one line saying they get filled in as decisions are made. Do not invent a layering rule for code that doesn't exist. An invented convention becomes a constraint that fights the project's real shape a week later.
- `source: prompt`.
- Git policy: no commits until the user asks, since there is no history to infer a format from.
- Open questions listing every assumed field.

Say plainly which fields are assumed and that the first `/retro` should revisit them. A greenfield profile is a starting position, not a specification.

## 7. Propose, then write

Show the user the profile you're about to write — the detected facts with their evidence, the assumptions clearly separated, and the open questions. Get confirmation before writing anything.

Lead with the things most likely to be wrong: any command you couldn't verify, any convention detected from a single example, and the work-item source.

Then write:

1. `loop/PROFILE.md` — filled in from `.claude/loop-templates/PROFILE.template.md`.
2. `loop/LESSONS.md` — copy `.claude/loop-templates/LESSONS.seed.md` verbatim. Do not edit the seeded lessons to match this stack; they are stack-independent by construction, and `/retro` retires any that prove inapplicable.
3. `loop/PLAN.md` — a stub saying no work item is loaded and to run `/loop-plan`.
4. `loop/STATE.md` — a header line and an adoption entry (date, mode, detected stack, work-item source).
5. `loop/tasks/README.md` — copy `.claude/loop-templates/tasks-README.md`.
6. If footprint is local: append `loop/` and `.claude/` to `.git/info/exclude`, then confirm with `git status --short` that the repo reads clean. Verify with `git check-ignore -v loop/PLAN.md` that the exclusion resolves to `.git/info/exclude` and not to a committed `.gitignore`.

   If footprint is **committed**, exclude `loop/AUDIT.log` specifically. It is machine-local run telemetry that changes on every spawn; committing it produces conflict-prone churn in every PR and tells a teammate nothing.

## 7b. Check the audit hook can run

Nothing to install. Each loop agent declares the hook in its own frontmatter as a `Stop` hook, which Claude Code converts to `SubagentStop` and unregisters when the agent finishes. It appends one line to `loop/AUDIT.log` per spawn, giving `/retro` a record no agent can shape.

Two things to confirm here, because both fail silently:

- **`jq` or `python3` must be on PATH** — `command -v jq python3`. The script reads the hook payload with one of them and exits quietly with neither, producing an empty log that looks exactly like "nothing has run yet". If neither is present, say so now and tell the user the loop still works, just without the audit trail.
- **`sh` must resolve.** On macOS and Linux this is free. On Windows it means Git Bash. If it isn't there, point the hook at the PowerShell twin instead — edit the `command` line in each of the five agent files to `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PROJECT_DIR}/.claude/hooks/audit-subagent.ps1" -AgentName <agent>`. This is the one sanctioned edit to a machinery file, because it is platform-specific rather than project-specific.

Then tell the user to check `loop/AUDIT.log` has content after their first `/orchestrate` run. A wrong interpreter path fails silently and looks identical to an empty log.

## 8. Stop

Report: the mode, the stack, the work-item source, anything you could not determine, and any command that failed verification.

Tell the user to skim `loop/PROFILE.md` — particularly the conventions section, since that is what shapes every line of code the loop writes — and then run `/loop-plan` when ready.

Do not continue into planning, even if the user's original request was to start building. The profile is a checkpoint worth a human glance precisely because everything downstream depends on it.
