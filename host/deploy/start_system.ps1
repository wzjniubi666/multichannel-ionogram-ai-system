param([string]$Python='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(!$Python){
    $config=Get-Content -LiteralPath (Join-Path $root 'host/deploy/system_settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $Python=$config.hub_python
    if($Python -and ![IO.Path]::IsPathRooted($Python)){$Python=Join-Path $root $Python}
}
if(!$Python -or !(Test-Path -LiteralPath $Python)){throw 'Set hub_python in host/deploy/system_settings.json to a Python 3.12 runtime.'}
$pythonw=Join-Path (Split-Path -Parent $Python) 'pythonw.exe'
if(!(Test-Path -LiteralPath $pythonw)){$pythonw=$Python}
$arguments='-E -X utf8 "'+(Join-Path $root 'host/app/system_launcher.py')+'"'
Start-Process -FilePath $pythonw -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden
