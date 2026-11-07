[CmdletBinding()]
param(
    [string]$Godot = 'godot_console.exe',
    [string]$OutputDirectory = '',
    [ValidatePattern('^\d+(\.\d+)?$')][string]$PreviewVersion = '9.1'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$gamePath = Join-Path $projectRoot 'game'
$releaseDirectory = if ($OutputDirectory) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory) } else { Join-Path $projectRoot 'build/story-preview' }
$previewExe = Join-Path $releaseDirectory "GodotIsland-village-preview$PreviewVersion.exe"
$decoder = Join-Path $gamePath 'bin/bw_audio_decode.exe'

if (-not (Get-Command $Godot -ErrorAction SilentlyContinue)) {
    throw 'Godot console executable not found. Set -Godot to your Godot 4.7.2 executable.'
}
if (-not (Test-Path -LiteralPath $decoder)) {
    throw 'Missing game/bin/bw_audio_decode.exe. See HANDOFF_RU.md for decoder build instructions.'
}
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
& $Godot --headless --path $gamePath --export-release 'Windows Desktop' $previewExe
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed ($LASTEXITCODE). Install matching export templates and inspect its errors."
}
Copy-Item -LiteralPath $decoder -Destination (Join-Path $releaseDirectory 'bw_audio_decode.exe')
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'preview') -File | Copy-Item -Destination $releaseDirectory
foreach ($template in @('Launch-Story-Preview.cmd', 'TESTING_RU.txt')) {
    $destination = Join-Path $releaseDirectory $template
    $content = (Get-Content -LiteralPath $destination -Raw).Replace('preview9.1', "preview$PreviewVersion")
    [IO.File]::WriteAllText($destination, $content, [Text.UTF8Encoding]::new($false))
}

# Shortcuts contain machine-specific absolute paths, so generate them locally.
if ($env:OS -eq 'Windows_NT') {
    $shortcutApi = New-Object -ComObject WScript.Shell
    $shortcut = $shortcutApi.CreateShortcut((Join-Path $releaseDirectory 'Black and White Preview.lnk'))
    $shortcut.TargetPath = Join-Path $releaseDirectory 'Launch-Story-Preview.cmd'
    $shortcut.WorkingDirectory = $releaseDirectory
    $shortcut.IconLocation = "$previewExe,0"
    $shortcut.Save()
}

$record = [ordered]@{
    preview = $PreviewVersion
    executable = Split-Path -Leaf $previewExe
    sha256 = (Get-FileHash -LiteralPath $previewExe -Algorithm SHA256).Hash
    built_utc = [DateTime]::UtcNow.ToString('o')
    status = 'locally-built-not-yet-verified'
    complete_campaign = $false
    requires_original_install = $true
}
$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $releaseDirectory 'build-info.json') -Encoding utf8
Write-Output "Built $previewExe"
Write-Output 'This is a fresh build. Run the checks in HANDOFF_RU.md before calling it verified.'
