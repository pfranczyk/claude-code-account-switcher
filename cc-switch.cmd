<# : cc-switch - single file: cmd runs this header, PowerShell runs the rest of the file
@echo off
set "CCS_SELF=%~f0"
where pwsh >nul 2>nul && (set "CCS_PS=pwsh") || (set "CCS_PS=powershell")
%CCS_PS% -NoProfile -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:CCS_SELF, [Text.Encoding]::UTF8)))" %*
exit /b %errorlevel%
#>
<#
  cc-switch.cmd - switch between Claude Code accounts without /login

  Accounts are stored in ~/.claude.json as:
    oauthAccount_<name>   - account info (copy of oauthAccount)
    claudeAiOauth_<name>  - tokens (copy of claudeAiOauth from ~/.claude/.credentials.json)
  <name> = the part of the e-mail address before '@'.

  Usage:
    cc-switch                - interactive picker (arrows, Enter, Esc); the active account is preselected
    cc-switch <name>         - save the active account and switch to <name>
    cc-switch list           - list saved accounts (* = active)
    cc-switch save           - save the active account (e.g. after /login to a new one)
    cc-switch remove <name>  - remove a saved account
  -Force skips the check whether Claude Code is running.

  Single file: put it in a folder on PATH (e.g. ~/.local/bin). Works with Windows PowerShell 5.1 and pwsh 7.
#>
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(Position = 1)][string]$Name,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'

$configPath = Join-Path $env:USERPROFILE '.claude.json'
$credPath   = Join-Path $env:USERPROFILE '.claude\.credentials.json'

# .NET instead of Get/Set-Content -Encoding: behaves the same in Windows PowerShell 5.1 and pwsh 7
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Json($path) { [IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json }
function Write-Json($obj, $path) {
    # write to a temp file first so an interruption never leaves truncated JSON behind
    $tmp = "$path.cc-switch.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 100), $utf8)
    Move-Item $tmp $path -Force
}
function Set-Prop($obj, $key, $value) { $obj | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force }
function Get-AccountName($oauthAccount) { ($oauthAccount.emailAddress -split '@')[0] }
function Get-SavedNames {
    @($config.PSObject.Properties.Name | Where-Object { $_ -like 'oauthAccount_*' } | ForEach-Object { $_.Substring(13) })
}
# Name of the saved account whose e-mail matches the active oauthAccount
function Get-ActiveName {
    $email = $config.oauthAccount.emailAddress
    Get-SavedNames | Where-Object { $config."oauthAccount_$_".emailAddress -eq $email } | Select-Object -First 1
}

# Saves the active account into the <name> slots; returns the name
function Save-Active {
    if (-not $config.oauthAccount -or -not $cred.claudeAiOauth) { throw 'No logged-in account (oauthAccount / claudeAiOauth missing).' }
    $n = Get-AccountName $config.oauthAccount
    Set-Prop $config "oauthAccount_$n"  $config.oauthAccount
    Set-Prop $config "claudeAiOauth_$n" $cred.claudeAiOauth
    $n
}

function Assert-ClaudeClosed {
    if ($Force) { return }
    $running = @(Get-Process -Name claude -ErrorAction SilentlyContinue)
    if ($running) {
        throw "Claude Code is running ($($running.Count) process(es)). Close it or use -Force (then restart your sessions)."
    }
}

function Switch-To($target) {
    if (-not $config."oauthAccount_$target" -or -not $config."claudeAiOauth_$target") {
        throw "No saved account '$target'. Saved: $((Get-SavedNames) -join ', ')"
    }
    Assert-ClaudeClosed
    # 1. active -> slot (so the freshly rotated refreshToken is not lost)
    $saved = Save-Active
    if ($saved -eq $target) { Write-Json $config $configPath; "Account '$target' is already active."; return }
    # 2. target slot -> active
    $config.oauthAccount = $config."oauthAccount_$target"
    $cred.claudeAiOauth  = $config."claudeAiOauth_$target"
    Write-Json $cred $credPath
    Write-Json $config $configPath
    "Switched: $saved -> $target ($($config.oauthAccount.emailAddress)). Restart Claude Code."
}

function Format-Account($n) {
    $acc = $config."oauthAccount_$n"
    $line = "{0,-16} {1,-32} {2}" -f $n, $acc.emailAddress, $acc.organizationName
    if ($n -eq $activeName) { $line += '  (active)' }
    $line
}

# Interactive picker: arrows / Enter / Esc; returns a name or $null
function Select-Account($names) {
    $i = [Math]::Max(0, [array]::IndexOf($names, $activeName))
    $width = [Math]::Max(20, [Console]::WindowWidth - 1)
    Write-Host 'Select account (Up/Down, Enter = switch, Esc = cancel):'
    1..$names.Count | ForEach-Object { Write-Host '' }   # reserve lines so scrolling does not break the cursor position
    $top = [Console]::CursorTop - $names.Count
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            for ($j = 0; $j -lt $names.Count; $j++) {
                $text = ((' ', '>')[$j -eq $i] + ' ' + (Format-Account $names[$j]))
                $text = $text.Substring(0, [Math]::Min($text.Length, $width)).PadRight($width)
                if ($j -eq $i) { Write-Host $text -ForegroundColor Black -BackgroundColor Cyan }
                else { Write-Host $text }
            }
            switch ([Console]::ReadKey($true).Key) {
                'UpArrow'   { $i = ($i - 1 + $names.Count) % $names.Count }
                'DownArrow' { $i = ($i + 1) % $names.Count }
                'Enter'     { return $names[$i] }
                'Escape'    { return $null }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

$config = Read-Json $configPath
$cred   = Read-Json $credPath
$activeName = Get-ActiveName

switch ($Command) {
    '' {
        $names = Get-SavedNames
        if (-not $names) { "No saved accounts. Use: cc-switch save"; break }
        if (-not $activeName) { Write-Host "! the active account ($($config.oauthAccount.emailAddress)) is not saved - use: cc-switch save" -ForegroundColor Yellow }
        if ([Console]::IsInputRedirected) { $names | ForEach-Object { Format-Account $_ }; "(no console - use: cc-switch <name>)"; break }
        $choice = Select-Account $names
        if (-not $choice) { 'Cancelled.'; break }
        if ($choice -eq $activeName) { "Account '$choice' is already active."; break }
        Switch-To $choice
    }
    'list' {
        $names = Get-SavedNames
        if (-not $names) { "No saved accounts. Use: cc-switch save"; break }
        foreach ($n in $names) { ((' ', '*')[$n -eq $activeName]) + ' ' + (Format-Account $n) }
        if (-not $activeName) { "! the active account ($($config.oauthAccount.emailAddress)) is not saved - use: cc-switch save" }
    }
    'save' {
        $n = Save-Active
        Write-Json $config $configPath
        "Saved active account: $n ($($config.oauthAccount.emailAddress))"
    }
    'remove' {
        if (-not $Name) { throw 'Specify a name: cc-switch remove <name>' }
        if (-not $config."oauthAccount_$Name") { throw "No saved account '$Name'." }
        $config.PSObject.Properties.Remove("oauthAccount_$Name")
        $config.PSObject.Properties.Remove("claudeAiOauth_$Name")
        Write-Json $config $configPath
        "Removed saved account: $Name"
    }
    default { Switch-To $Command }
}
