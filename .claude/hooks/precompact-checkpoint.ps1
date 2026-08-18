# PreCompact checkpoint (Windows / PowerShell). Counterpart of
# precompact-checkpoint.sh; see that file's header for the design.
#
# Writes the same loop/HANDOFF.md shape /loop-handoff writes, including
# `Status: active`, derived entirely from durable state - never the transcript.
# Always exits 0: exit code 2 on PreCompact blocks compaction and would hang the
# session rather than lose a checkpoint.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $p = $raw | ConvertFrom-Json
    $root = $p.cwd
    if ([string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $loopDir = Join-Path $root 'loop'
    if (-not (Test-Path -LiteralPath $loopDir -PathType Container)) { exit 0 }

    $plan = Join-Path $loopDir 'PLAN.md'
    if (-not (Test-Path -LiteralPath $plan)) { exit 0 }

    # The in-flight task: first unchecked task line whose packet is not blocked.
    $task = $null
    foreach ($line in Get-Content -LiteralPath $plan) {
        $m = [regex]::Match($line, '^- \[ \] (T-\d{3})')
        if ($m.Success) {
            $candidate = $m.Groups[1].Value
            $packetPath = Join-Path $loopDir "tasks\$candidate.md"
            $isBlocked = $false
            if (Test-Path -LiteralPath $packetPath) {
                $isBlocked = (Get-Content -LiteralPath $packetPath -Encoding utf8) -match '^Status: blocked'
            }
            if (-not $isBlocked) { $task = $candidate; break }
        }
    }
    if (-not $task) { exit 0 }

    $packet = Join-Path $loopDir "tasks\$task.md"
    # Read as UTF-8: PowerShell 5.1 defaults to the ANSI codepage, which mangles
    # the em-dash in a Status line and would corrupt the counter we copy out.
    $lines  = if (Test-Path -LiteralPath $packet) { Get-Content -LiteralPath $packet -Encoding utf8 } else { @() }

    $status = ($lines | Where-Object { $_ -match '^Status: *(.+)' } |
               ForEach-Object { $matches[1] } | Select-Object -First 1)
    if (-not $status) { $status = 'unknown - no Status line in the packet' }

    $title = ($lines | Where-Object { $_ -match '^# *(T-\d{3}.*)' } |
              ForEach-Object { $matches[1] } | Select-Object -First 1)
    if (-not $title) { $title = $task }

    # Stage, and the two verdicts kept apart by the agent that emitted them. A
    # test-runner verdict recorded under "Last verification result" would tell a
    # resuming session that step 4b ran when it never did - and 4b is the stage
    # that catches what the suite structurally cannot see.
    $stage = $null; $verdict = $null; $testv = $null
    $audit = Join-Path $loopDir 'AUDIT.log'
    if (Test-Path -LiteralPath $audit) {
        foreach ($line in Get-Content -LiteralPath $audit -Encoding utf8) {
            $parts = $line -split '\s*\|\s*'
            if ($parts.Count -ge 4 -and $parts[2] -eq $task) {
                $stage = $parts[1]
                if ($parts[3] -ne '-') {
                    if     ($parts[1] -eq 'test-runner') { $testv   = $parts[3] }
                    elseif ($parts[1] -eq 'verifier')    { $verdict = $parts[3] }
                }
            }
        }
    }
    $stage = if ($stage) { "after $stage (last spawn recorded in loop/AUDIT.log)" }
             else { 'unknown - no AUDIT.log entry for this task' }
    if (-not $testv)   { $testv   = 'n/a - no test-runner verdict recorded for this task' }
    if (-not $verdict) { $verdict = 'n/a - stage not reached, or not applicable to this project' }

    Push-Location $root
    $dirty = (git status --short 2>$null) -join "`n"
    Pop-Location
    if ([string]::IsNullOrWhiteSpace($dirty)) { $dirty = 'none' }

    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    $body = @"
# HANDOFF - session checkpoint
Written: $stamp
Written by: PreCompact hook (derived from durable state, not from the transcript)
Status: active

## Unit
See loop/PLAN.md - this checkpoint was written automatically at compaction.

## Current task
$title

## Stage
$stage

## Failure counter
$status

## Last test result
$testv

## Last verification result
$verdict

## Uncommitted changes
$dirty

## Tree state
Not assessed - a hook cannot judge whether a change is half-applied. Run git diff before trusting it.

## Next action
Resume $task at the stage above. Re-read the packet's Status line first: it is the record that survived.
"@

    # WriteAllText with a BOM-less UTF8Encoding. Set-Content -Encoding utf8 emits a
    # BOM on PowerShell 5.1, which would put stray bytes at the head of a file the
    # POSIX twin writes clean, and make the two checkpoints differ byte for byte.
    [System.IO.File]::WriteAllText(
        (Join-Path $loopDir 'HANDOFF.md'), $body, (New-Object System.Text.UTF8Encoding $false))
}
catch { }

exit 0
