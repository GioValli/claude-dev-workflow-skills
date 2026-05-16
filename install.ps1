#requires -Version 5.1
<#
.SYNOPSIS
    Install Claude Dev Workflow Skills into ~/.claude/skills/

.DESCRIPTION
    Copies skill folders from this repo (en/ or it/) into the user's Claude Code
    skills directory. Prompts before overwriting existing skills.

.PARAMETER Lang
    Language variant to install: "en" (English) or "it" (Italian).
    If omitted, the script prompts interactively.

.PARAMETER Force
    Overwrite existing skills without prompting.

.EXAMPLE
    .\install.ps1
    Interactive mode.

.EXAMPLE
    .\install.ps1 -Lang en
    Install English skills, prompt on conflicts.

.EXAMPLE
    .\install.ps1 -Lang it -Force
    Install Italian skills, overwrite any existing skill with same name.
#>

param(
    [ValidateSet('en', 'it')]
    [string]$Lang,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$SkillsTarget = Join-Path $HOME '.claude\skills'

function Write-Info($msg)    { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[ERR]   $msg" -ForegroundColor Red }

# --- Validate repo state -----------------------------------------------------

if (-not (Test-Path (Join-Path $RepoRoot 'en')) -or -not (Test-Path (Join-Path $RepoRoot 'it'))) {
    Write-Err "Repository structure invalid: expected 'en/' and 'it/' folders next to install.ps1"
    exit 1
}

# --- Pick language -----------------------------------------------------------

if (-not $Lang) {
    Write-Host ""
    Write-Host "Claude Dev Workflow Skills installer" -ForegroundColor White
    Write-Host "===================================="
    Write-Host ""
    Write-Host "  [1] English  (en/)"
    Write-Host "  [2] Italiano (it/)"
    Write-Host ""
    $choice = Read-Host "Choose language [1/2]"
    switch ($choice) {
        '1'  { $Lang = 'en' }
        'en' { $Lang = 'en' }
        '2'  { $Lang = 'it' }
        'it' { $Lang = 'it' }
        default {
            Write-Err "Invalid choice: $choice"
            exit 1
        }
    }
}

$SourceDir = Join-Path $RepoRoot $Lang
Write-Info "Installing $Lang skills from $SourceDir"

# --- Ensure target dir exists ------------------------------------------------

if (-not (Test-Path $SkillsTarget)) {
    Write-Info "Creating $SkillsTarget"
    New-Item -ItemType Directory -Path $SkillsTarget -Force | Out-Null
}

# --- Copy each skill ---------------------------------------------------------

$Skills = Get-ChildItem -Path $SourceDir -Directory
if ($Skills.Count -eq 0) {
    Write-Err "No skills found in $SourceDir"
    exit 1
}

$installed = 0
$skipped = 0

foreach ($skill in $Skills) {
    $targetPath = Join-Path $SkillsTarget $skill.Name

    if (Test-Path $targetPath) {
        if ($Force) {
            Write-Warn "Overwriting existing $($skill.Name)"
        } else {
            Write-Host ""
            Write-Warn "$($skill.Name) already exists at $targetPath"
            $reply = Read-Host "Overwrite? [y/N]"
            if ($reply -notmatch '^[yY]') {
                Write-Info "Skipped $($skill.Name)"
                $skipped++
                continue
            }
        }
        Remove-Item -Recurse -Force $targetPath
    }

    Copy-Item -Recurse -Path $skill.FullName -Destination $targetPath
    Write-Success "Installed $($skill.Name) -> $targetPath"
    $installed++
}

# --- Summary -----------------------------------------------------------------

Write-Host ""
Write-Host "Done." -ForegroundColor White
Write-Host "  Installed: $installed"
Write-Host "  Skipped:   $skipped"
Write-Host ""
Write-Host "Restart your Claude Code session to load the new skills." -ForegroundColor White
