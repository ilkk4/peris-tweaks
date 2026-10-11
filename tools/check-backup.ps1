<#
.SYNOPSIS
    Read-only health check of the Minecraft world backups, run before any significant change.

.DESCRIPTION
    Answers one question: if this change goes wrong, can the world be restored to the state
    it is in right now? It checks that:
      - the newest backup exists, pairs with its mod list, and is not suspiciously small;
      - the newest backup was taken after the live world last changed;
      - Minecraft is not holding the world open;
      - the newest backup's zip opens and contains level.dat, player data and region files;
      - which mods changed since that backup (informational only: the backups hold the mod
        jars, so earlier versions are always recoverable).

    SAFETY: read-only by construction.
      - Before doing anything, the script parses its own source and refuses to run if it finds
        a command outside a small read-only allowlist, any output redirection, a file or zip
        mode other than read, a write-type method name, or an assignment to an object member.
        This guards against a later edit slipping in a write.
      - Every path it opens is checked to sit under the backup folder or the game instance.
      - Files are opened with FileAccess.Read, zips with ZipFile.OpenRead.
      The strongest guarantee is still a read-only permission on the share itself.

    PRIVACY:
      - Prints only names of backup files and mod jars, dates, sizes and counts. Never prints
        file contents, player names, UUIDs, coordinates or inventories.
      - Writes nothing anywhere: no log, no temp files. Output goes to the console only.
      - Contacts nothing but the backup share, using your existing Windows session.

.PARAMETER Deep
    Also decompress every entry of the newest backup to confirm it reads cleanly.
    Reads the whole zip (about 1.6 GB) over the network. Windows PowerShell 5.1 does not
    verify zip checksums, so this catches truncation and damaged data, not every bit flip.

.PARAMETER HashMods
    Also compare the SHA-256 of each live mod jar with the hash stored in the backup's mod list.

.NOTES
    Exit code: 0 all passed, 1 warnings, 2 failures (including a refusal by the safety check).
#>
[CmdletBinding()]
param(
    [string]$BackupRoot   = '\\SNOWFLAKE\Main\Koti\Backup\Minecraft\world',
    [string]$InstanceRoot = 'D:\CurseForge\Instances\Create Long Con',
    [string]$WorldName    = 'world',
    [switch]$Deep,
    [switch]$HashMods
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Failures = 0
$script:Warnings = 0

function Report([string]$Level, [string]$Message) {
    if ($Level -eq 'FAIL') { $script:Failures++ }
    if ($Level -eq 'WARN') { $script:Warnings++ }
    Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Finish {
    Write-Host ''
    if ($script:Failures -gt 0) {
        Write-Host ('Result: FAILED ({0} failures, {1} warnings). Do not make risky changes yet.' -f $script:Failures, $script:Warnings)
        exit 2
    }
    if ($script:Warnings -gt 0) {
        Write-Host ('Result: passed with {0} warnings. Read them before a risky change.' -f $script:Warnings)
        exit 1
    }
    Write-Host 'Result: all checks passed. The current world state is restorable from the newest backup.'
    exit 0
}

# ---------------------------------------------------------------------------------------------
# Safety tripwire: inspect this script's own syntax tree before running anything else.
# ---------------------------------------------------------------------------------------------
function Test-SelfIsReadOnly {
    $problems = New-Object System.Collections.Generic.List[string]
    if (-not $PSCommandPath) {
        $problems.Add('cannot locate the script file to inspect it; run it as a file, not pasted')
        return $problems
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { $problems.Add('the script does not parse cleanly') }

    $allowedCommands = @(
        'Get-ChildItem', 'Get-Item', 'Test-Path', 'Join-Path', 'Write-Host', 'Select-Object',
        'Where-Object', 'Sort-Object', 'Measure-Object', 'ForEach-Object', 'ConvertFrom-Json',
        'Get-Date', 'New-Object', 'Add-Type', 'Get-FileHash', 'Set-StrictMode',
        'Report', 'Finish', 'Test-SelfIsReadOnly', 'Assert-Allowed', 'Open-ReadOnly',
        'Read-TextFile', 'Format-Size'
    )
    $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $commands) {
        $name = $c.GetCommandName()
        if (-not $name -or $allowedCommands -notcontains $name) {
            $problems.Add('command not on the read-only allowlist: ' + $c.Extent.Text)
            continue
        }
        if ($name -eq 'Add-Type') {
            $text = $c.Extent.Text
            if ($text -notmatch '-AssemblyName' -or $text -match '-(TypeDefinition|MemberDefinition|Path|LiteralPath|OutputAssembly)') {
                $problems.Add('Add-Type may only load an existing assembly: ' + $text)
            }
        }
        if ($name -eq 'New-Object') {
            if ($c.Extent.Text -notmatch '^New-Object\s+(System\.IO\.StreamReader|System\.Collections\.Generic\.List\[string\]|byte\[\])') {
                $problems.Add('New-Object of a type not on the allowlist: ' + $c.Extent.Text)
            }
        }
    }

    $redirections = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.RedirectionAst] }, $true)
    if (@($redirections).Count -gt 0) { $problems.Add('output redirection is not allowed') }

    $memberAssignments = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
    if (@($memberAssignments).Count -gt 0) { $problems.Add('assignments to object members are not allowed') }

    $restrictedModes = @{ 'FileMode' = @('Open'); 'FileAccess' = @('Read'); 'ZipArchiveMode' = @('Read') }
    $deniedMembers = @(
        'Delete', 'Move', 'MoveTo', 'Copy', 'CopyTo', 'Create', 'CreateText', 'CreateEntry',
        'CreateDirectory', 'CreateFromDirectory', 'AppendText', 'AppendAllText', 'AppendAllLines',
        'Write', 'WriteByte', 'WriteLine', 'WriteAllText', 'WriteAllBytes', 'WriteAllLines',
        'Replace', 'SetLength', 'Flush', 'Encrypt', 'Decrypt', 'SetAccessControl', 'SetAttributes',
        'SetLastWriteTime', 'SetCreationTime', 'ExtractToFile', 'ExtractToDirectory', 'Invoke'
    )
    $members = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
    foreach ($m in $members) {
        if ($m.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $problems.Add('dynamic member names are not allowed: ' + $m.Extent.Text)
            continue
        }
        $memberName = $m.Member.Value
        if ($deniedMembers -contains $memberName) {
            $problems.Add('write-type member is not allowed: ' + $m.Extent.Text)
        }
        if ($m.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
            $typeShort = @($m.Expression.TypeName.Name -split '\.')[-1]
            if ($restrictedModes.ContainsKey($typeShort) -and $restrictedModes[$typeShort] -notcontains $memberName) {
                $problems.Add('only read modes are allowed: ' + $m.Extent.Text)
            }
        }
    }
    return $problems
}

# ---------------------------------------------------------------------------------------------
# Path guard and read-only file access.
# ---------------------------------------------------------------------------------------------
$allowedRoots = @($BackupRoot, $InstanceRoot) | ForEach-Object { $_.TrimEnd('\') + '\' }

function Assert-Allowed([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $probe = $full.TrimEnd('\') + '\'
    foreach ($root in $allowedRoots) {
        if ($probe.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $full }
    }
    throw ('Refusing to touch a path outside the backup folder and the game instance: ' + $Path)
}

function Open-ReadOnly([string]$Path, [switch]$LetOthersWrite) {
    $full = Assert-Allowed $Path
    $share = [System.IO.FileShare]::Read
    if ($LetOthersWrite) { $share = [System.IO.FileShare]::ReadWrite }
    return [System.IO.File]::Open($full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
}

function Read-TextFile([string]$Path) {
    $stream = Open-ReadOnly $Path
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    } finally {
        $stream.Dispose()
    }
}

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

# ---------------------------------------------------------------------------------------------
# 1. Safety check
# ---------------------------------------------------------------------------------------------
$selfProblems = @(Test-SelfIsReadOnly)
if ($selfProblems.Count -gt 0) {
    foreach ($p in $selfProblems) { Report 'FAIL' ('Safety check: ' + $p) }
    Write-Host 'Refusing to run: this script must stay read-only.'
    Finish
}
Report 'PASS' 'Safety check: the script is read-only by construction'

# ---------------------------------------------------------------------------------------------
# 2. Backups present and paired
# ---------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Assert-Allowed $BackupRoot))) {
    Report 'FAIL' ('Backup folder not reachable: ' + $BackupRoot)
    Finish
}

$zips = @(Get-ChildItem -LiteralPath $BackupRoot -File -Filter ($WorldName + '_*.zip') | Sort-Object Name)
if ($zips.Count -eq 0) {
    Report 'FAIL' 'No world backups found'
    Finish
}

$unpaired = @($zips | Where-Object { -not (Test-Path -LiteralPath ($_.FullName -replace '\.zip$', '.mods.json')) })
if ($unpaired.Count -gt 0) {
    Report 'WARN' ('{0} backups have no mod list beside them' -f $unpaired.Count)
}

$latest = $zips[-1]
$stamp = $latest.BaseName.Substring($WorldName.Length + 1)
$created = [DateTime]::ParseExact($stamp, 'yyyy-MM-dd_HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
$age = (Get-Date) - $created
Report 'INFO' ('{0} backups, from {1} to {2}' -f $zips.Count, $zips[0].BaseName.Substring($WorldName.Length + 1), $stamp)
Report 'INFO' ('Newest backup: {0}, {1}, taken {2:N1} hours ago' -f $latest.Name, (Format-Size $latest.Length), $age.TotalHours)

if ($zips.Count -ge 2) {
    $previous = $zips[-2]
    $ratio = $latest.Length / [double]$previous.Length
    if ($ratio -lt 0.9) {
        Report 'WARN' ('Newest backup is {0:P0} the size of the one before it; it may be incomplete' -f $ratio)
    } else {
        Report 'PASS' 'Newest backup size is in line with the previous one'
    }
}

$modListPath = $latest.FullName -replace '\.zip$', '.mods.json'
$modList = $null
if (Test-Path -LiteralPath $modListPath) {
    $modList = Read-TextFile $modListPath | ConvertFrom-Json
} else {
    Report 'WARN' 'Newest backup has no mod list'
}

# ---------------------------------------------------------------------------------------------
# 3. Does the newest backup cover the live world's current state?
# ---------------------------------------------------------------------------------------------
$worldPath = Join-Path (Join-Path $InstanceRoot 'saves') $WorldName
$levelDatPath = Join-Path $worldPath 'level.dat'
if (-not (Test-Path -LiteralPath (Assert-Allowed $levelDatPath))) {
    Report 'FAIL' ('Live world not found: ' + $worldPath)
} else {
    $live = Get-Item -LiteralPath $levelDatPath
    $liveEpoch = ([DateTimeOffset]$live.LastWriteTimeUtc).ToUnixTimeSeconds()
    $backupSourceEpoch = $null
    if ($modList -and ($modList.PSObject.Properties.Name -contains 'src_mtime')) {
        $backupSourceEpoch = [long][Math]::Floor([double]$modList.src_mtime)
    } else {
        $backupSourceEpoch = ([DateTimeOffset]$created.ToUniversalTime()).ToUnixTimeSeconds()
    }
    $liveText = $live.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
    $backupText = [DateTimeOffset]::FromUnixTimeSeconds($backupSourceEpoch).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
    if ($liveEpoch -gt ($backupSourceEpoch + 5)) {
        Report 'FAIL' ('The live world changed after the newest backup (world saved {0}, backup covers {1}). Let a new session backup run first.' -f $liveText, $backupText)
    } else {
        Report 'PASS' ('The newest backup covers the live world as last saved ({0})' -f $liveText)
    }
}

$lockPath = Join-Path $worldPath 'session.lock'
if (Test-Path -LiteralPath (Assert-Allowed $lockPath)) {
    try {
        $lockStream = Open-ReadOnly $lockPath -LetOthersWrite
        try { [void]$lockStream.ReadByte() } finally { $lockStream.Dispose() }
        Report 'PASS' 'Minecraft is not holding the world open'
    } catch {
        Report 'WARN' 'The world looks open in Minecraft; close the game before a risky change'
    }
}

# ---------------------------------------------------------------------------------------------
# 4. Newest backup's contents (structure only; nothing is extracted or printed)
# ---------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Assert-Allowed $latest.FullName))
try {
    $entries = @($zip.Entries)
    $levelEntry = $entries |
        Where-Object { ($_.FullName -replace '\\', '/') -match '(^|/)level\.dat$' } |
        Sort-Object { ($_.FullName -replace '\\', '/').Length } |
        Select-Object -First 1
    if (-not $levelEntry) {
        Report 'FAIL' 'Newest backup has no level.dat'
    } else {
        $normalized = $levelEntry.FullName -replace '\\', '/'
        $prefix = [regex]::Escape($normalized.Substring(0, $normalized.Length - 'level.dat'.Length))
        $names = @($entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        $players = @($names | Where-Object { $_ -match ('^' + $prefix + 'playerdata/[^/]+\.dat$') }).Count
        $overworld = @($names | Where-Object { $_ -match ('^' + $prefix + 'region/[^/]+\.mca$') }).Count
        $nether = @($names | Where-Object { $_ -match ('^' + $prefix + 'DIM-1/region/[^/]+\.mca$') }).Count
        $end = @($names | Where-Object { $_ -match ('^' + $prefix + 'DIM1/region/[^/]+\.mca$') }).Count

        $header = $levelEntry.Open()
        try { $b1 = $header.ReadByte(); $b2 = $header.ReadByte() } finally { $header.Dispose() }
        if ($b1 -ne 0x1F -or $b2 -ne 0x8B) {
            Report 'FAIL' 'level.dat in the newest backup is not a valid compressed file'
        } elseif ($players -eq 0 -or $overworld -eq 0) {
            Report 'FAIL' ('Newest backup looks incomplete: {0} player files, {1} overworld region files' -f $players, $overworld)
        } else {
            Report 'PASS' ('Newest backup opens: {0} entries; level.dat valid; {1} player files; region files: {2} overworld, {3} nether, {4} end' -f $entries.Count, $players, $overworld, $nether, $end)
        }
    }

    if ($Deep) {
        Report 'INFO' 'Deep check: reading every entry of the newest backup...'
        $buffer = New-Object byte[] 1048576
        $bad = 0
        $index = 0
        foreach ($entry in $entries) {
            $index++
            try {
                $stream = $entry.Open()
                try {
                    $readTotal = [long]0
                    while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $readTotal += $n }
                } finally {
                    $stream.Dispose()
                }
                if ($readTotal -ne $entry.Length) { $bad++ }
            } catch {
                $bad++
            }
            if ($index % 1000 -eq 0) { Write-Host ('       {0} / {1} entries' -f $index, $entries.Count) }
        }
        if ($bad -eq 0) {
            Report 'PASS' ('Deep check: all {0} entries read cleanly' -f $entries.Count)
        } else {
            Report 'FAIL' ('Deep check: {0} entries could not be read in full' -f $bad)
        }
    }
} finally {
    $zip.Dispose()
}

# ---------------------------------------------------------------------------------------------
# 5. Live mods compared with the newest backup's mod list (informational)
# ---------------------------------------------------------------------------------------------
if ($modList) {
    $modsFolder = Join-Path $InstanceRoot $modList.mods_subfolder
    $liveJars = @(Get-ChildItem -LiteralPath (Assert-Allowed $modsFolder) -File -Filter '*.jar')
    $liveByName = @{}
    foreach ($jar in $liveJars) { $liveByName[$jar.Name] = $jar }
    $backupByName = @{}
    foreach ($mod in @($modList.mods)) { $backupByName[$mod.name] = $mod }

    $added = @($liveByName.Keys | Where-Object { -not $backupByName.ContainsKey($_) } | Sort-Object)
    $removed = @($backupByName.Keys | Where-Object { -not $liveByName.ContainsKey($_) } | Sort-Object)
    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($name in $liveByName.Keys) {
        if (-not $backupByName.ContainsKey($name)) { continue }
        $jar = $liveByName[$name]
        $recorded = $backupByName[$name]
        if ($jar.Length -ne [long]$recorded.size) {
            $changed.Add($name)
        } elseif ($HashMods) {
            $hash = (Get-FileHash -LiteralPath (Assert-Allowed $jar.FullName) -Algorithm SHA256).Hash
            if ($hash.ToLowerInvariant() -ne ([string]$recorded.sha256).ToLowerInvariant()) { $changed.Add($name) }
        }
    }

    $how = 'name and size'
    if ($HashMods) { $how = 'name, size and SHA-256' }
    if ($added.Count -eq 0 -and $removed.Count -eq 0 -and $changed.Count -eq 0) {
        Report 'PASS' ('Live mods match the newest backup''s mod list ({0} jars, by {1})' -f $liveJars.Count, $how)
    } else {
        Report 'INFO' ('Mods changed since the newest backup, which holds the earlier versions (by {0}):' -f $how)
        foreach ($name in $added) { Write-Host ('         + ' + $name) }
        foreach ($name in $removed) { Write-Host ('         - ' + $name) }
        foreach ($name in $changed) { Write-Host ('         ~ ' + $name) }
    }
}

Finish
