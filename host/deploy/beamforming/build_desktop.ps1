$ErrorActionPreference='Stop'
$desktop=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../app/beamforming/com'))
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if(!(Test-Path -LiteralPath $compiler)){$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'}
if(!(Test-Path -LiteralPath $compiler)){throw '.NET Framework C# compiler not found.'}
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll (('/out:')+(Join-Path $desktop 'FPGAHost.exe')) (Join-Path $desktop 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Desktop launcher compilation failed.'}
Write-Host 'FPGAHost.exe rebuilt from Launcher.cs. No GUI or hardware action was launched.'
