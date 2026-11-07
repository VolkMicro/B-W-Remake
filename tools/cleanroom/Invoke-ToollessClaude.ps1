[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PacketPath,
    [Parameter(Mandatory)][string]$SystemPromptPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedPacketSHA256
)

$ErrorActionPreference = 'Stop'
$brokerRoot = Join-Path $env:LOCALAPPDATA 'BW-Restoration/ImplementerBroker'
$version = (& claude --version | Out-String).Trim()
if ($version -notmatch '^2\.1\.311\b') { throw 'Claude version changed; repeat the isolation probes before using this broker.' }
$packet = (Resolve-Path -LiteralPath $PacketPath).Path
$system = (Resolve-Path -LiteralPath $SystemPromptPath).Path
$packetHash = (Get-FileHash -LiteralPath $packet -Algorithm SHA256).Hash
if ($packetHash -ne $ExpectedPacketSHA256) { throw 'Packet hash differs from the reviewed input.' }
$runRoot = Join-Path $brokerRoot ('runs/' + [guid]::NewGuid().ToString('N'))
$workerDir = Join-Path $runRoot 'worker'
if ($env:CLAUDE_CONFIG_DIR) { throw 'Run with the normal CLI auth owner; do not duplicate an OAuth refresh store.' }
New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
Copy-Item -LiteralPath $packet -Destination (Join-Path $runRoot 'packet.txt')
Copy-Item -LiteralPath $system -Destination (Join-Path $runRoot 'system.txt')
$authSource = Join-Path $env:USERPROFILE '.claude/.credentials.json'
if (-not (Test-Path -LiteralPath $authSource)) { throw 'The expected existing CLI auth file is unavailable; no other credential source was searched.' }
[IO.File]::WriteAllText((Join-Path $runRoot 'empty-mcp.json'), '{"mcpServers":{}}')
[IO.File]::WriteAllText((Join-Path $runRoot 'settings.json'), '{"autoMemoryEnabled":false,"disableAllHooks":true,"enabledPlugins":{},"permissions":{"defaultMode":"dontAsk"}}')
$oldMode = $PSNativeCommandArgumentPassing
$oldLocation = Get-Location
try {
    $PSNativeCommandArgumentPassing = 'Standard'
    Set-Location -LiteralPath $workerDir
    Get-Content -LiteralPath (Join-Path $runRoot 'packet.txt') -Raw |
        claude --safe-mode --restricted --tools '' --disallowed-tools '*' `
        --disable-slash-commands --strict-mcp-config `
        --mcp-config (Join-Path $runRoot 'empty-mcp.json') `
        --settings (Join-Path $runRoot 'settings.json') `
        --no-session-persistence --max-turns 1 `
        --system-prompt (Get-Content -LiteralPath (Join-Path $runRoot 'system.txt') -Raw) `
        --output-format stream-json --verbose `
        1> (Join-Path $runRoot 'response.jsonl') 2> (Join-Path $runRoot 'stderr.txt')
    $processExit = $LASTEXITCODE
} finally {
    Set-Location -LiteralPath $oldLocation.Path
    $PSNativeCommandArgumentPassing = $oldMode
}
$events = @(Get-Content -LiteralPath (Join-Path $runRoot 'response.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
$init = @($events | Where-Object { $_.type -eq 'system' -and $_.subtype -eq 'init' }) | Select-Object -First 1
$result = @($events | Where-Object { $_.type -eq 'result' }) | Select-Object -Last 1
$toolUses = @($events | Where-Object { $_.type -eq 'assistant' } | ForEach-Object { $_.message.content } | Where-Object { $_.type -eq 'tool_use' })
$unexpectedPlugins = @($init.plugins | Where-Object { $_.path -ne 'builtin' })
$accepted = $processExit -eq 0 -and $null -ne $init -and @($init.tools).Count -eq 0 -and
    @($init.mcp_servers).Count -eq 0 -and $unexpectedPlugins.Count -eq 0 -and
    $toolUses.Count -eq 0 -and $null -ne $result -and -not $result.is_error -and $result.subtype -eq 'success'
$manifest = [ordered]@{
    timestampUtc = [DateTime]::UtcNow.ToString('o')
    role = 'fixed tool-less remote model request; not an OS sandbox certification'
    cliVersion = $version
    model = $init.model
    packetSHA256 = $packetHash
    systemSHA256 = (Get-FileHash -LiteralPath (Join-Path $runRoot 'system.txt') -Algorithm SHA256).Hash
    auth = 'normal single-owner CLI OAuth transport; no credential copying and no credential data in packet/model tools'
    safeMode = $true
    restrictedMode = $true
    tools = @($init.tools)
    mcpServers = @($init.mcp_servers)
    builtinPluginNames = @($init.plugins | ForEach-Object { $_.name })
    builtinAgentNames = @($init.agents)
    agentInvocationToolAvailable = $false
    observedToolUses = $toolUses.Count
    permittedEnvelopeFieldNames = @('userEmail','environment')
    noSessionPersistence = $true
    processExit = $processExit
    resultSubtype = $result.subtype
    acceptedCapabilityBoundary = $accepted
    resultSHA256 = if ($null -ne $result) { $null } else { 'no result' }
    evidence = 'probe-20261107: negative safe-mode canaries absent; positive Read-only normal mode detects exact user/project canaries'
}
if ($null -ne $result) {
    [IO.File]::WriteAllText((Join-Path $runRoot 'answer.txt'), [string]$result.result)
    $manifest.resultSHA256 = (Get-FileHash -LiteralPath (Join-Path $runRoot 'answer.txt') -Algorithm SHA256).Hash
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'manifest.json') -Encoding utf8
if (-not $accepted) { throw "Tool-less boundary/result validation failed. Inspect private run $runRoot" }
[pscustomobject]@{RunDirectory=$runRoot;Manifest=(Join-Path $runRoot 'manifest.json');Answer=(Join-Path $runRoot 'answer.txt');Accepted=$accepted} | ConvertTo-Json
