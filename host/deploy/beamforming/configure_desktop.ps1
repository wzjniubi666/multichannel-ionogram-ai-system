param([Parameter(Mandatory=$true)][string]$WorkspaceRoot)
$ErrorActionPreference='Stop'
$desktop=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../app/beamforming/com'))
. (Join-Path $desktop 'workspace_paths.ps1')
$resolved=[IO.Path]::GetFullPath($WorkspaceRoot)
if(!(Test-BeamformingWorkspace $resolved)){throw 'Workspace needs XCK325Tboshuhecheng, .venv-cos and HFceshi.'}
[IO.File]::WriteAllText((Join-Path $desktop 'workspace.path'),$resolved,[Text.UTF8Encoding]::new($false))
Write-Host ('Desktop workspace configured: '+$resolved)
Write-Host 'No network configuration or hardware operations performed.'
