#!/bin/sh
set -e
SCRATCH=${TMPDIR:-/tmp}/loop-template-dryrun
TPL=$(cd "$(dirname "$0")/.." && pwd)
SH="/c/Program Files/Git/bin/sh.exe"
mkdir -p "$SCRATCH"; R=$SCRATCH/repo
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

rm -rf "$R"; mkdir -p "$R/.claude" "$R/src"; cd "$R"
git init -q .; git config user.email t@t; git config user.name t

# A project that already uses Claude Code: tracked .claude/ WITH a settings.json
cat > .claude/settings.json <<'J'
{
  "permissions": { "allow": ["Bash(npm test:*)"] },
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "echo project-own-hook" } ] } ] }
}
J
echo 'console.log("app");' > src/app.js
printf '{"name":"scratch","scripts":{"test":"echo no tests"}}\n' > package.json
git add -A; git commit -qm "existing project with tracked .claude/"

echo "=== A. adoption into a repo with a tracked .claude/ ==="
cp -r "$TPL/.claude/." .claude/
TRACKED=$(git ls-files .claude loop | head -3)
[ -n "$TRACKED" ] && ok "precheck sees tracked .claude/ (loop-init must refuse to exclude)" || no "precheck missed tracked files"
printf 'loop/\n.claude/\n' >> .git/info/exclude
git check-ignore -q loop/PLAN.md 2>/dev/null && OLDCHECK=pass || OLDCHECK=fail
git status --short | grep -q '.claude/settings.json' && ok "old verify would have LIED: .claude still dirty in status" || echo "  (n/a)"

echo "=== B. settings.json merge preserves what was there ==="
python - <<'PY'
import json,io
frag=json.load(io.open('.claude/loop-templates/settings.hooks.json',encoding='utf-8'))
cur=json.load(io.open('.claude/settings.json',encoding='utf-8'))
SH="C:/Program Files/Git/bin/sh.exe"
def sub(o):
    if isinstance(o,str): return o.replace('<SH>','"%s"'%SH)
    if isinstance(o,list): return [sub(x) for x in o]
    if isinstance(o,dict): return {k:sub(v) for k,v in o.items()}
    return o
for evt,entries in frag['hooks'].items():
    cur.setdefault('hooks',{}).setdefault(evt,[]).extend(sub(entries))
io.open('.claude/settings.json','w',encoding='utf-8').write(json.dumps(cur,indent=2))
PY
python -c "
import json,io;d=json.load(io.open('.claude/settings.json',encoding='utf-8'))
assert d['permissions']['allow']==['Bash(npm test:*)'], 'permissions lost'
assert any('project-own-hook' in json.dumps(h) for h in d['hooks']['Stop']), 'existing Stop hook lost'
assert len(d['hooks']['Stop'])==2, 'loop Stop hook not added'
assert 'SubagentStop' in d['hooks'] and 'PreCompact' in d['hooks'], 'missing hooks'
print('  PASS  merge kept permissions + existing Stop hook, added all 3 loop hooks')
"

echo "=== C. per-task diff isolation, cadence=never ==="
mkdir -p loop/tasks
printf '## Tasks\n- [ ] T-001 — first (loop/tasks/T-001.md)\n- [ ] T-002 — second (loop/tasks/T-002.md)\n\n## Verification\n- [ ] app prints greeting\n' > loop/PLAN.md
B1=$(git rev-parse HEAD)                      # T-001 base: clean tree
sed -i 's/console.log("app");/console.log("app v1");/' src/app.js
echo 'export const one=1;' > src/one.js         # T-001 adds a file
[ -z "$(git status --porcelain)" ] && B2=$(git rev-parse HEAD) || B2=$(git stash create -u)
UNTRACKED_AT_T2=$(git ls-files --others --exclude-standard)
sed -i 's/console.log("app v1");/console.log("app v2");/' src/app.js
echo 'export const two=2;' > src/two.js         # T-002 adds a file
NEW=$(git ls-files --others --exclude-standard); git add -N -- $NEW >/dev/null 2>&1
T2FILES=$(git diff --name-only $B2)
git reset -q -- $NEW
echo "$T2FILES" | grep -q 'src/two.js' && ok "T-002 diff contains the file it created" || no "new file missing from diff"
git diff $B2 -- src/app.js | grep -q 'app v2' && ok "T-002 diff shows its own change" || no "own change missing"
git diff $B2 -- src/app.js | grep -q '+.*app v1' && no "T-002 diff leaked T-001's change" || ok "T-002 diff excludes T-001's change to the same file"
echo "$UNTRACKED_AT_T2" | grep -q 'src/one.js' && ok "carry-over list names T-001's file (reviewer told to ignore)" || no "carry-over list wrong"

echo "=== D. failure ladder, blocked marker, Stop guard ==="
sed -i 's|- \[ \] T-002 — second (loop/tasks/T-002.md)|- [ ] T-002 — second (loop/tasks/T-002.md) @base='"$B2"' attempt=2/2 last=test-fail|' loop/PLAN.md
CLAUDE_PROJECT_DIR=$(pwd) "$SH" .claude/loop-templates/hooks/loop-guard.sh > guard1.txt 2>&1 || true
grep -q 'escalation ceiling' guard1.txt && ok "Stop guard surfaces a task at the ceiling" || no "guard silent at ceiling"
sed -i 's|^- \[ \] T-002|- [!] T-002|; s|attempt=2/2 last=test-fail|@blocked BLOCKED after 3 — see STATE 2026-08-18|' loop/PLAN.md
sed -i 's|^- \[ \] T-001|- [x] T-001|' loop/PLAN.md
echo "  plan now:"; sed -n '/^- \[/p' loop/PLAN.md | sed 's/^/    /'
NEXT=$(grep -m1 '^- \[ \] T-' loop/PLAN.md || true)
[ -z "$NEXT" ] && ok "no unchecked non-blocked task remains — orchestrator stops instead of retrying T-002" || no "blocked task would be re-picked (or a Verification item mistaken for a task)"
CLAUDE_PROJECT_DIR=$(pwd) "$SH" .claude/loop-templates/hooks/loop-guard.sh > guard2.txt 2>&1 || true
grep -q 'blocked' guard2.txt && ok "Stop guard reports the blocked task" || no "guard missed blocked task"

echo "=== E. compaction mid-task, then resume ==="
sed -i 's|- \[!\] T-002.*|- [ ] T-002 — second (loop/tasks/T-002.md) @base='"$B2"' attempt=2/2 last=test-fail|' loop/PLAN.md
rm -f loop/HANDOFF.md
CLAUDE_PROJECT_DIR=$(pwd) "$SH" .claude/loop-templates/hooks/journal-marker.sh
grep -q '^Status: active' loop/HANDOFF.md && ok "PreCompact wrote an active checkpoint" || no "no checkpoint written"
grep -q '2/2' loop/HANDOFF.md && ok "checkpoint preserved the attempt counter (2/2, not 0)" || no "counter lost"
grep -q 'T-002' loop/HANDOFF.md && ok "checkpoint names the in-flight task" || no "task missing"
sed -i 's/^Status: active/Status: consumed (resumed 2026-08-18T09:00:00Z)/' loop/HANDOFF.md
grep -q '^Status: consumed' loop/HANDOFF.md && ok "resume marks it consumed (not replayable)" || no "consume failed"

echo "=== F. audit log ==="
for a in builder test-runner builder test-runner implementer; do
  echo "{\"subagent_type\":\"$a\"}" | CLAUDE_PROJECT_DIR=$(pwd) "$SH" .claude/loop-templates/hooks/audit-log.sh
done
N=$(grep -c 'T-002' loop/AUDIT.md || echo 0)
[ "$N" -eq 5 ] && ok "audit log recorded all 5 spawns for a task with no journal entry" || no "audit log has $N/5"

echo
echo "=================  $PASS passed, $FAIL failed  ================="
[ "$FAIL" -eq 0 ] || exit 1
