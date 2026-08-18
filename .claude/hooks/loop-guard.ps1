# Loop guard - Stop hook (Windows / PowerShell). Counterpart of loop-guard.sh;
# see that file's header for the design and why it never blocks.
#
# ADVISORY, NEVER BLOCKING. Always exits 0, and surfaces a warning only through
# `{"systemMessage": "..."}` on stdout - on exit 0, plain stdout and stderr reach
# the debug log and nothing else, so an echoed warning is an invisible one.
#
# Reads only durable state: loop/PROFILE.md, the task packets, loop/AUDIT.log.
# Silent when nothing is over budget.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $p = $raw | ConvertFrom-Json
    $root = $p.cwd
    if ([string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $loopDir = Join-Path $root 'loop'
    if (-not (Test-Path -LiteralPath $loopDir -PathType Container)) { exit 0 }

    $profile = Join-Path $loopDir 'PROFILE.md'
    $audit   = Join-Path $loopDir 'AUDIT.log'
    $tasks   = Join-Path $loopDir 'tasks'

    # Budget from the profile, defaulting when absent or unparseable. A missing
    # ceiling must not silence the guard - that is when a runaway is most likely.
    $maxSpawns = 10
    if (Test-Path -LiteralPath $profile) {
        $m = [regex]::Match((Get-Content -LiteralPath $profile -Raw), 'Max spawns per task[^0-9]*([0-9]+)', 'IgnoreCase')
        if ($m.Success) { $maxSpawns = [int]$m.Groups[1].Value }
    }

    $warnings = New-Object System.Collections.Generic.List[string]

    # 1. Tasks that burned more spawns than the budget allows.
    if (Test-Path -LiteralPath $audit) {
        $counts = @{}
        foreach ($line in Get-Content -LiteralPath $audit) {
            $parts = $line -split '\s*\|\s*'
            if ($parts.Count -ge 3 -and $parts[2] -match '^T-\d+$') {
                $counts[$parts[2]] = 1 + $(if ($counts.ContainsKey($parts[2])) { $counts[$parts[2]] } else { 0 })
            }
        }
        $over = @($counts.GetEnumerator() | Where-Object { $_.Value -gt $maxSpawns } |
                  ForEach-Object { "$($_.Key) used $($_.Value) spawns" })
        if ($over.Count) { $warnings.Add("Over the $maxSpawns-spawn budget: $($over -join ', ').") }
    }

    if (Test-Path -LiteralPath $tasks) {
        # Read as UTF-8 explicitly. PowerShell 5.1's Get-Content defaults to the
        # system ANSI codepage, which mangles the em-dash these Status lines use
        # into several bytes - enough to break any pattern that tries to match it.
        # Neither pattern below depends on the dash, for the same reason.
        $packets = @(Get-ChildItem -LiteralPath $tasks -Filter 'T-*.md' | ForEach-Object {
            [pscustomobject]@{
                Name  = $_.BaseName
                Lines = Get-Content -LiteralPath $_.FullName -Encoding utf8
            }
        })

        # 2. Tasks the escalation ladder gave up on.
        $blocked = @($packets | Where-Object { $_.Lines -match '^Status: blocked' } |
            ForEach-Object { $_.Name })
        if ($blocked.Count) { $warnings.Add("Blocked, awaiting a human: $($blocked -join ', ').") }

        # 3. Tasks sitting at the last rung of the ladder.
        $atMax = @($packets | Where-Object { $_.Lines -match '^Status:.*attempt 3 of 3' } |
            ForEach-Object { $_.Name })
        if ($atMax.Count) { $warnings.Add("At the final attempt: $($atMax -join ', ').") }
    }

    if ($warnings.Count -eq 0) { exit 0 }

    $msg = 'Loop guard: ' + ($warnings -join ' ')
    $out = @{ systemMessage = $msg } | ConvertTo-Json -Compress
    Write-Output $out
}
catch { }

exit 0
