[CmdletBinding()]
param([string]$RuntimeArchive, [string]$Output)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $arguments = @((Join-Path $PSScriptRoot 'build-windows-standalone.py'))
    if ($RuntimeArchive) { $arguments += @('--runtime-archive', $RuntimeArchive) }
    if ($Output) { $arguments += @('--output', $Output) }
    & python @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows candidate build failed.' }
} finally { Pop-Location }
