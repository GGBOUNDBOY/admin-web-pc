#Requires -Version 5.1
<#
.SYNOPSIS
  Copy index.html to <yyyyMMdd>.html, commit and push to the current branch.

.DESCRIPTION
  No parameters needed:
    1. Copy index.html -> <yyyyMMdd>.html  (overwrite if exists)
    2. git add / commit (uses a default message)
    3. git push origin <current branch>    (branch auto-detected)
#>

$ErrorActionPreference = "Stop"

function Write-Step { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[!]  $m" -ForegroundColor Yellow }

function Invoke-Git {
    param([string[]] $GitArgs)
    # git writes progress/warnings to stderr; keep them as plain text so that
    # $ErrorActionPreference = "Stop" does not abort the script
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git @GitArgs 2>&1 | ForEach-Object { $_.ToString() }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{ Code = $code; Output = (($out | Out-String).Trim()) }
}

try {
    Set-Location -LiteralPath $PSScriptRoot

    # ---------- 1. copy index.html and rename to yyyyMMdd ----------
    $source = Resolve-Path -LiteralPath "index.html" -ErrorAction SilentlyContinue
    if (-not $source) { throw "index.html not found in $PSScriptRoot" }

    $stamp  = Get-Date -Format "yyyyMMdd"
    $target = Join-Path $PSScriptRoot "$stamp.html"

    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Ok "Copied index.html -> $stamp.html"

    # ---------- 2. git environment ----------
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Warn "git not found in PATH. File generated, upload skipped."
        exit 0
    }

    if ((Invoke-Git @("rev-parse", "--is-inside-work-tree")).Code -ne 0) {
        Write-Step "No git repository found, initializing..."
        Invoke-Git @("init") | Out-Null
        Write-Ok "Repository initialized"
    }

    # current branch (works even for an empty repo)
    $branch = (Invoke-Git @("branch", "--show-current")).Output
    if (-not $branch) { $branch = (Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")).Output }
    if (-not $branch -or $branch -eq "HEAD") { $branch = "main" }
    Write-Step "Current branch: $branch"

    $origin = (Invoke-Git @("remote", "get-url", "origin")).Output
    if (-not $origin) { throw "No 'origin' remote configured. Add it once: git remote add origin <github-url>" }
    Write-Step "Remote origin: $origin"

    # ---------- 3. stage & commit ----------
    # stage everything under this project directory (logs/ excluded via .gitignore).
    # "-- ." keeps the scope inside this folder even when the repo root is a parent dir.
    $r = Invoke-Git @("add", "-A", "--", ".")
    if ($r.Code -ne 0) { throw "git add failed: $($r.Output)" }

    # git diff --cached --quiet: 0 = nothing staged, 1 = something staged
    $diffQ = Invoke-Git @("diff", "--cached", "--quiet")
    if ($diffQ.Code -eq 0) {
        $staged = $false
    } elseif ($diffQ.Code -eq 1) {
        $staged = $true
    } else {
        # empty repository (no HEAD yet): fall back to porcelain status,
        # first column other than space/? means the file is staged
        $staged = @((Invoke-Git @("status", "--porcelain", "--", ".")).Output -split "`n" |
            Where-Object { $_ -match '^[ADMRCU]' }).Count -gt 0
    }

    if (-not $staged) {
        Write-Warn "Nothing staged (content unchanged), commit skipped."
    } else {
        $msg = "chore: publish welcome page $stamp"
        $r = Invoke-Git @("commit", "-m", $msg)
        if ($r.Code -ne 0) { throw "git commit failed: $($r.Output)" }
        Write-Ok "Committed: $msg"
    }

    # ---------- 4. push to current branch ----------
    Write-Step "Pushing to origin/$branch ..."
    $hasRemoteBranch = [bool](Invoke-Git @("ls-remote", "--heads", "origin", $branch)).Output
    if ($hasRemoteBranch) {
        $r = Invoke-Git @("push", "origin", $branch)
    } else {
        Write-Step "Remote branch not found, creating it (first push)..."
        $r = Invoke-Git @("push", "-u", "origin", "$branch")
    }

    if ($r.Code -ne 0) {
        Write-Host $r.Output -ForegroundColor Red
        throw "Push failed. Check GitHub credential and remote URL."
    }
    Write-Ok "Pushed $stamp.html to $origin ($branch)"
}
catch {
    Write-Host "[X] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
