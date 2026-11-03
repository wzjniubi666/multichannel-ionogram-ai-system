$ErrorActionPreference='Stop'
$app=Split-Path -Parent $PSScriptRoot
$root=Join-Path $app 'validation\network_mocks'
New-Item -ItemType Directory -Path $root -Force | Out-Null
. (Join-Path $app 'network_session.ps1') -RequestFile (Join-Path $root 'unused.json')
# Every network/child-worker operation is replaced in this test process only.
# Original adapter functions are never executed.
$project=Join-Path $root 'mock_project'
function Invoke-GuiPreflight($Request,[string]$Path){$script:calls.Add('preflight');if($script:case -eq 'preflight_failure'){throw 'MOCK_PREFLIGHT_FAILURE'}}
function New-BoardBackup([string]$Directory){$script:calls.Add('backup');return [pscustomobject]@{MutationStarted=$false;Restored=$false}}
function Set-BoardTestEndpoint($State,[string]$Directory){$script:calls.Add('setup');$State.MutationStarted=$true;if($script:case -eq 'setup_failure'){throw 'MOCK_SETUP_FAILURE'}}
function Invoke-GuiPacketWorker($Request,[string]$Path){$script:calls.Add('worker');if($script:case -eq 'packet_failure'){throw 'MOCK_PACKET_FAILURE'}}
function Restore-BoardState($State,[string]$Directory){$script:calls.Add('restore');if($script:case -eq 'restore_failure'){throw 'MOCK_RESTORE_FAILURE'};$State.Restored=$true}
$results=@()
foreach($caseName in @('success','preflight_failure','setup_failure','packet_failure','restore_failure')){
    $script:case=$caseName
    $script:calls=New-Object 'System.Collections.Generic.List[string]'
    $folder=Join-Path $root ($caseName+'_'+[guid]::NewGuid().ToString('N').Substring(0,6));New-Item -ItemType Directory -Path $folder | Out-Null
    $path=Join-Path $folder 'request.json'
    $request=[pscustomobject]@{mode='hardware';direct_connection_confirmed=$true;stop_file=(Join-Path $folder 'cancel.request')}
    $failed=$false
    try{Invoke-GuiNetworkSession $request $path}catch{$failed=$true}
    $record=Get-Content -LiteralPath (Join-Path $folder 'network_result.json') -Raw | ConvertFrom-Json
    if(($caseName -eq 'success') -eq $failed){throw ('Unexpected success/failure '+$caseName)}
    if($caseName -eq 'preflight_failure'){
        if(($script:calls -join ',') -ne 'preflight' -or !$record.restored -or $record.mutated){throw 'Preflight changed network'}
    }else{
        if($script:calls[-1] -ne 'restore'){throw ('Missing finally restoration '+$caseName)}
        if(($caseName -eq 'restore_failure') -eq [bool]$record.restored){throw ('Bad restore status '+$caseName)}
    }
    $results+=@{case=$caseName;passed=$true;calls=@($script:calls);restored=[bool]$record.restored}
}
@{passed=$true;test_only=$true;actual_network_functions_called=$false;cases=$results} | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $root 'verification.json') -Encoding utf8
Write-Host 'PASS NETWORK_SESSION_MOCKS: five failure/success paths, no adapter changes'
