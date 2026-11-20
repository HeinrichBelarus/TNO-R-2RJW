param(
    [string]$RequiemPath = 'D:\SteamLibrary\steamapps\workshop\content\394360\2980739000',
    [string]$InstallPath = 'C:\hoi4-mods\tnor_2rjw_test1'
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$package = Join-Path $PSScriptRoot 'tnor_2rjw_test1'

function Read-RequiemFile {
    param([string]$RelativePath)
    $path = Join-Path $RequiemPath $RelativePath
    return [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}

function Replace-One {
    param([string]$Text, [string]$Pattern, [string]$Replacement)

    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one match in Requiem 1.8.0d, found $($matches.Count): $Pattern"
    }
    $match = $matches[0]
    return $Text.Substring(0, $match.Index) + $Replacement + $Text.Substring($match.Index + $match.Length)
}

function Edit-SharedFocus {
    param([string]$Id, [scriptblock]$Edit)

    $pattern = '(?m)^shared_focus\s*=\s*\{\n[ \t]+id\s*=\s*' + [regex]::Escape($Id) + '\b[^\n]*\n[\s\S]*?^\}'
    $focus = [regex]::Match($shared, $pattern)
    if (!$focus.Success) {
        throw "Shared focus missing from Requiem: $Id"
    }
    $replacement = & $Edit $focus.Value
    return Replace-One $shared $pattern $replacement
}

$descriptor = Read-RequiemFile 'descriptor.mod'
if ($descriptor -notmatch '(?m)^name="TNO: Requiem"[ \t]*$' -or
    $descriptor -notmatch '(?m)^version="1\.8\.0d"[ \t]*$') {
    throw "Expected TNO: Requiem 1.8.0d at $RequiemPath"
}
if (!(Test-Path -LiteralPath (Join-Path $package 'events/tnor_2rjw_story_events.txt') -PathType Leaf)) {
    throw "Extract the entire TEST1 archive before running this script."
}

$sharedPath = 'common/national_focus/2WRW_Shukshin_shared.txt'
$shared = Read-RequiemFile $sharedPath

# Keep the three original non-diplomatic requirements and refresh the new branch as they complete.
foreach ($id in @('NOV_shukshin_the_russian_dream', 'NOV_shukshin_sunshine_in_central_asia', 'NOV_develop_the_murmansk_railway')) {
    $shared = Edit-SharedFocus $id {
        param($focus)
        Replace-One $focus '(?m)^[ \t]*completion_reward\s*=\s*\{[ \t]*\n' (
            "`tcompletion_reward = {`n`t`tmark_focus_tree_layout_dirty = yes`n")
    }
}

# The replacement West focus is defined in our own file with the same ID.
$shared = Edit-SharedFocus 'NOV_look_to_the_west' { '' }

$shared = Edit-SharedFocus 'NOV_the_issue_of_vladivostok' {
    param($focus)
    Replace-One $focus '(?m)^[ \t]*prerequisite\s*=\s*\{[ \t]*\n' (
        "`tallow_branch = { has_country_flag = tnor_2rjw_west_diplomacy }`n" +
        "`tavailable = { has_country_flag = tnor_2rjw_west_diplomacy }`n`tprerequisite = {`n")
}
$shared = Edit-SharedFocus 'NOV_approach_the_sphere' {
    param($focus)
    $focus = Replace-One $focus '(?m)^[ \t]*prerequisite\s*=\s*\{[ \t]*\n' (
        "`tavailable = { has_country_flag = tnor_2rjw_west_diplomacy }`n`tprerequisite = {`n")
    Replace-One $focus '\n\t\}\n\}\z' (
        "`n`t`tload_focus_tree = NOV_novosibirsk_war_preparation_shukshin`n`t}`n}")
}

# Hide the West China War branch; keep its sibling Mongolia and other proxy conflicts intact.
$shared = Edit-SharedFocus 'NOV_an_alliance_with_the_clique' {
    param($focus)
    Replace-One $focus '(?m)^\tallow_branch = \{\n[\s\S]*?^\t\}' (
        "`tallow_branch = { always = no }")
}
$shared = Edit-SharedFocus 'NOV_establish_the_west_chinese_republic' {
    param($focus)
    $focus = Replace-One $focus '(?m)^\tavailable = \{\n[\s\S]*?^\t\}' (
        "`tavailable = { always = no }")
    Replace-One $focus '(?m)^\t\t\tSWRW_start_west_china_war = yes[ \t]*\n' ''
}

$treePath = 'common/national_focus/2WRW_Shukshin.txt'
$trees = Replace-One (Read-RequiemFile $treePath) '(?m)^\tshared_focus = NOV_our_next_challenge[ \t]*$' (
    "`tshared_focus = NOV_our_next_challenge`n`tshared_focus = TNOR_2RJW_return_to_eastern_question")

$debugPath = 'common/decisions/Requiem_Debug_decisions.txt'
$debug = Replace-One (Read-RequiemFile $debugPath) '(?m)^\tNOV_WCW_debug\s*=\s*\{[^\n]*\n[\s\S]*?^\t\}\n' ''

# Validate every original anchor before writing anything to the installed submod.
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
if ([IO.Path]::GetFullPath($package) -ne [IO.Path]::GetFullPath($InstallPath)) {
    Get-ChildItem -LiteralPath $package | Copy-Item -Destination $InstallPath -Recurse -Force
}
$overrides = @{
    $sharedPath = $shared
    $treePath = $trees
    $debugPath = $debug
}
foreach ($relativePath in $overrides.Keys) {
    $destination = Join-Path $InstallPath $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    [IO.File]::WriteAllText($destination, $overrides[$relativePath], $utf8)
}

Write-Host "TEST1 installed: $InstallPath"
