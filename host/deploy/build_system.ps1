$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$source=Join-Path $root 'host/deploy/SystemLauncher.cs'
$destination=Join-Path $root '电离图智能识别系统.exe'
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll (('/out:')+$destination) $source
if($LASTEXITCODE -ne 0){throw 'System launcher compilation failed'}
Write-Host 'Unified system launcher compiled; no application or hardware was started.'
