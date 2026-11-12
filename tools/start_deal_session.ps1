<#
  start_deal_session.ps1 : opens a Claude Code session on THIS computer to finish THE DEAL
  (WAR & HAYTHORN's Yes / No vote), on the branch the cloud session pushed.

  Run it from your ac8survivalmod folder (the main checkout, the one with .env), after `git pull`:
      powershell -ExecutionPolicy Bypass -File .\tools\start_deal_session.ps1
  Or name the folder:
      powershell -ExecutionPolicy Bypass -File .\tools\start_deal_session.ps1 -Repo "D:\path\to\ac8survivalmod"
  -Remote  starts it as `claude remote-control` instead, so you can follow it from the Claude app too.
#>
param(
    [string]$Repo = (Get-Location).Path,
    [switch]$Remote
)
$ErrorActionPreference = "Stop"
$Branch = "claude/coop-yes-no-voting-gg7umu"

function Need($cmd, $what) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "Not found: $cmd ($what). Install it, open a new PowerShell, and run this again." -ForegroundColor Red
        exit 1
    }
}
Need git "Git for Windows"
Need claude "Claude Code: npm install -g @anthropic-ai/claude-code"

if (-not (Test-Path (Join-Path $Repo "AGENTS.md")) -or -not (Test-Path (Join-Path $Repo ".git"))) {
    Write-Host "$Repo isn't the ac8survivalmod checkout (no AGENTS.md / .git). Run this from that folder, or pass -Repo." -ForegroundColor Red
    exit 1
}
Set-Location $Repo
Write-Host "Repo: $Repo"

# your own uncommitted work is never touched: stop if there is any
$dirty = git status --porcelain --untracked-files=no
if ($dirty) {
    Write-Host "You have uncommitted changes here:" -ForegroundColor Yellow
    Write-Host $dirty
    Write-Host "Commit or stash them first (git stash), then run this again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Fetching $Branch ..."
git fetch origin $Branch
if ($LASTEXITCODE -ne 0) { Write-Host "git fetch failed." -ForegroundColor Red; exit 1 }
git show-ref --verify --quiet "refs/heads/$Branch"
if ($LASTEXITCODE -eq 0) {
    git switch $Branch
    git merge --ff-only "origin/$Branch"
} else {
    git switch -c $Branch --track "origin/$Branch"
}
if ($LASTEXITCODE -ne 0) { Write-Host "Couldn't switch to $Branch." -ForegroundColor Red; exit 1 }
Write-Host "On $Branch at $(git log --oneline -1)" -ForegroundColor Green

$Prompt = @"
Read AGENTS.md first. Then finish THE DEAL (WAR & HAYTHORN's Yes / No vote) on branch $Branch: the Lua is done
(Scripts/sv_deal.lua, a DEV ONLY part) and docs/re/DEAL.md section 3 lists what needs this machine's game files:
1. Step R: read Mission 8's event package for LiveActivateYesNoExecution (tools/checks/ep_dump.py) and
   ULiveYesNoRadioWorldSubsystem: its args, how the Yes / No answer comes back (a flag, a remote event, a field Lua can
   read), its buttons (pad too), whether it can open more than once a level and in co-op. Write the findings into
   docs/re/DEAL.md and tell me whether it can replace the Ctrl+A / Ctrl+X keys. Don't change the vote's code yet.
2. Build WAR & HAYTHORN's allied F/A-18F: unit SV_Unit_DealHornet, name key SV_DealHornet (Lua sets the text
   WAR & HAYTHORN), the campaign's f18f, flying MOONCHILD's set (hard rule 22), ALLY-marked with a target box (hard
   rule 32), made the way VOID WATCHER 1 is (tools/survival_events.py AWACS_*, build_survival_units.py,
   build_survival_rows.py). Its world data and rows are in every build; only sv_deal.lua spawns it.
3. python -I tools/bump_version.py, then sh tools/build_all.sh, then a dev build with tools/package_dev.sh, and the
   checks (sh tools/checks/run_all.sh; fleet_test's TESTER-line failure is older, not this work's).
Show me the plan before step 2's code. Commit with [claude] messages and push to $Branch.
"@

if ($Remote) {
    Write-Host "Starting claude remote-control here (open it from the Claude app). Paste this as your first message:" -ForegroundColor Cyan
    Write-Host $Prompt
    claude remote-control
} else {
    Write-Host "Starting Claude Code here with the task ..." -ForegroundColor Cyan
    claude $Prompt
}
