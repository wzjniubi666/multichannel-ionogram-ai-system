param([switch]$NoElevation)
$ErrorActionPreference='Stop'
$desktop=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../app/beamforming/com'))
. (Join-Path $desktop 'workspace_paths.ps1')
$workspaceRoot=Find-BeamformingWorkspace $desktop
if($NoElevation) {
    $pythonw=Join-Path $workspaceRoot '.venv-cos/Scripts/pythonw.exe'
    $arguments='-E -X utf8 "'+(Join-Path $desktop 'app.py')+'"'
    Start-Process -FilePath $pythonw -ArgumentList $arguments -WorkingDirectory $desktop -WindowStyle Hidden
} else {
    Start-Process -FilePath (Join-Path $desktop 'FPGAHost.exe') -WorkingDirectory $desktop -WindowStyle Hidden
}
