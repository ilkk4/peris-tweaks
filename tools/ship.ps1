<#
.SYNOPSIS
    Ships the mod to the live instance in one gated step: backup check, build, jar swap,
    commit, push. Stops at the first failure, so nothing is installed unless every gate passes.

.DESCRIPTION
    Run from the project root:
        powershell -File tools/ship.ps1 -Version 0.2.0 -Message "Short summary of the change"
    -Version sets mod_version first (omit it to ship the version already set).
    Prints only the lines that matter: gate results, the installed jar, the commit.
#>
param(
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$mods = 'D:\CurseForge\Instances\Create Long Con\mods'
if ($Version) {
    # Written without a byte-order mark, which Windows PowerShell's Set-Content would add.
    $props = (Get-Content 'gradle.properties' -Raw) -replace '(?m)^mod_version=.*$', "mod_version=$Version"
    [IO.File]::WriteAllText((Resolve-Path 'gradle.properties'), $props, (New-Object Text.UTF8Encoding $false))
}
$version = (Select-String -Path 'gradle.properties' -Pattern '^mod_version=(.+)$').Matches[0].Groups[1].Value
$jar = "peris_tweaks-$version.jar"

function Fail($why) {
    Write-Host "SHIP STOPPED: $why"
    exit 1
}

& powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-backup.ps1 | Select-String -Pattern 'FAIL|WARN|Result:' | ForEach-Object { Write-Host $_.Line }
if ($LASTEXITCODE -ne 0) { Fail 'backup check did not pass cleanly; let a session backup run first' }

& .\gradlew.bat build --console=plain -q
if ($LASTEXITCODE -ne 0) { Fail 'build failed' }
if (-not (Test-Path "build\libs\$jar")) { Fail "build\libs\$jar not found" }

Get-ChildItem $mods -Filter 'peris_tweaks-*.jar' | Remove-Item
Copy-Item "build\libs\$jar" $mods
Write-Host "Installed $jar"

git add -A
git commit -q -m "$Message"
if ($LASTEXITCODE -ne 0) { Fail 'commit failed (jar is installed)' }
Write-Host ("Committed " + (git log --oneline -1))
if (git remote) {
    git push -q origin HEAD:main
    if ($LASTEXITCODE -ne 0) { Fail 'push failed (installed and committed; push by hand)' }
    Write-Host 'Pushed to origin/main'
}
