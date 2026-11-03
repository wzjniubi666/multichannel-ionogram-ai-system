$ErrorActionPreference='Stop'
$guiRoot=$PSScriptRoot
. (Join-Path $guiRoot 'workspace_paths.ps1')
$workspaceRoot=Find-BeamformingWorkspace $guiRoot
$pythonw=Join-Path $workspaceRoot '.venv-cos/Scripts/pythonw.exe'
$app=Join-Path $guiRoot 'app.py'
$arguments='-E -X utf8 "'+$app+'"'
Start-Process -FilePath $pythonw -ArgumentList $arguments -WorkingDirectory $guiRoot -Verb RunAs -WindowStyle Hidden
