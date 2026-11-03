$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$desktop=Join-Path $root 'host/app/beamforming/com'
. (Join-Path $desktop 'workspace_paths.ps1')
$workspaceRoot=Find-BeamformingWorkspace $desktop
$parsed=0
foreach($folder in @((Join-Path $root 'host/deploy'),$desktop)) {
    foreach($file in (Get-ChildItem -LiteralPath $folder -Filter '*.ps1' -File)) {
        $tokens=$null;$parseErrors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if($parseErrors.Count -gt 0){throw ($file.FullName+': '+($parseErrors -join '; '))}
        $parsed++
    }
}
$assembly=[Reflection.Assembly]::LoadFile((Join-Path $desktop 'FPGAHost.exe'))
$flags=[Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic
$method=$assembly.GetType('Launcher').GetMethod('FindWorkspace',$flags)
$invokeArgs=New-Object object[] 1
$invokeArgs[0]=$desktop.ToString()
$fromExe=$method.Invoke($null,$invokeArgs)
if($fromExe -ne $workspaceRoot){throw 'Launcher and PowerShell workspace resolution differ.'}
$output=Join-Path $root 'metrics/logs/beamforming/desktop_supplement'
New-Item -ItemType Directory -Path $output -Force | Out-Null
@{passed=$true;powershell_scripts_parsed=$parsed;workspace=$workspaceRoot;launcher_matches_powershell=$true;
    main_launcher_executed=$false;real_adapter_changes=$false} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $output 'launcher_paths.json') -Encoding UTF8
Write-Host ('PASS DESKTOP PATHS: '+$workspaceRoot+'; scripts parsed='+$parsed+'; no GUI elevation or network actions.')
