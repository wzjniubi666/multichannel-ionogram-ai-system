param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
& $Python -E (Join-Path $projectRoot 'metrics/scripts/beamforming/verify_package.py')
if ($LASTEXITCODE -ne 0) { throw 'Package verification failed; inspect metrics/logs.' }
