$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$files=@(Get-ChildItem -LiteralPath (Join-Path $root 'host/deploy') -Filter '*.ps1' -File)
$files+=@(Get-ChildItem -LiteralPath (Join-Path $root 'host/deploy/beamforming') -Filter '*.ps1' -File)
$files+=@(Get-ChildItem -LiteralPath (Join-Path $root 'host/app/beamforming/com') -Filter '*.ps1' -File)
foreach($file in $files){
    $tokens=$null;$problems=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$problems) | Out-Null
    if($problems.Count){throw ($file.FullName+': '+($problems -join '; '))}
}
$desktop=Join-Path $root 'host/app/beamforming/com'
. (Join-Path $desktop 'workspace_paths.ps1')
$workspaceRoot=Find-BeamformingWorkspace $desktop
$assembly=[Reflection.Assembly]::LoadFile((Join-Path $desktop 'FPGAHost.exe'))
$flags=[Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
$method=$assembly.GetType('Launcher').GetMethod('FindWorkspace',$flags)
$parameters=New-Object object[] 1;$parameters[0]=$desktop.ToString()
$fromExe=$method.Invoke($null,$parameters)
if($fromExe -ne $workspaceRoot){throw 'Moved beamforming launcher and script workspace roots differ.'}
$output=Join-Path $root 'metrics/logs/integration'
New-Item -ItemType Directory -Path $output -Force | Out-Null
@{passed=$true;powershell_scripts_parsed=$files.Count;beamforming_workspace=$workspaceRoot;
    launcher_paths_match=$true;application_started=$false;hardware_accessed=$false} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $output 'launchers.json') -Encoding UTF8
Write-Host ('PASS MOVED LAUNCHERS: '+$files.Count+' scripts; original workspace='+$workspaceRoot+'; no app/hardware launch.')
