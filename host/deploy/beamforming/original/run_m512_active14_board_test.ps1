[CmdletBinding()]
param(
    [ValidateSet('Inspect','Run')][string]$Mode='Inspect',
    [string]$PlanDirectory='',
    [string]$ResultsRoot='.\result',
    [string]$ResumeDirectory='',
    [ValidateRange(0,1000000)][int]$FrameLimit=0,
    [string]$Python='.\.venv-cos\Scripts\python.exe'
)
$ErrorActionPreference='Stop'
$batchRoot=$PSScriptRoot
$batchMode=$Mode
. (Join-Path $batchRoot 'run_single_nic_board_test.ps1') -Mode $batchMode -Python $Python
$batchClient='m512_active14_scan.py'
if(!$PlanDirectory){$PlanDirectory=Join-Path $batchRoot 'validation\m_hf512_14ch_20261028\actual11_plan14_v2'}

function Invoke-MBatchTransaction($State,[string]$BackupDirectory,[string]$Destination) {
    try {
        Set-BoardTestEndpoint $State $BackupDirectory
        $runArgs=@('run','--plan',$PlanDirectory,'--output',$Destination,'--host',$script:BoardIP)
        if($ResumeDirectory){$runArgs+='--resume'}
        if($FrameLimit -gt 0){$runArgs+=@('--limit',[string]$FrameLimit)}
        & $Python (Join-Path $batchRoot ('python\'+$batchClient)) @runArgs 2>&1 |
            Tee-Object -FilePath (Join-Path $BackupDirectory 'batch_console.log') | Out-Host
        if($LASTEXITCODE -ne 0){throw 'M512_BATCH_FAILED: verified frames are saved; inspect the result and network logs before explicit resume'}
    } finally {
        Restore-BoardState $State $BackupDirectory
    }
}

function Invoke-MBatchMain {
    if($batchMode -eq 'Run') {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Open Windows PowerShell as Administrator, then run this command again.'
        }
    }
    $tag=(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
    $backup=Join-Path $batchRoot ('validation\board_20261023\host_smoke512_active14_'+$tag)
    if($ResumeDirectory){$destination=[IO.Path]::GetFullPath($ResumeDirectory)}
    else{
        $resultPrefix='M_MVDR512_ACTIVE14_hardware_'
        $destination=Join-Path ([IO.Path]::GetFullPath($ResultsRoot)) ($resultPrefix+$tag)
    }
    New-Item -ItemType Directory -Path $backup | Out-Null
    Start-Transcript -LiteralPath (Join-Path $backup 'console.log') | Out-Null
    $state=$null
    try {
        Write-Host ('NETWORK_BACKUP_DIRECTORY: '+$backup)
        Write-Host ('SCAN_RESULT_DIRECTORY: '+$destination)
        $checkArgs=@('check','--plan',$PlanDirectory,'--report',(Join-Path $backup 'plan_preflight.json'))
        if($ResumeDirectory){$checkArgs+=@('--resume-output',$destination)}
        & $Python (Join-Path $batchRoot ('python\'+$batchClient)) @checkArgs 2>&1 |
            Tee-Object -FilePath (Join-Path $backup 'preflight_console.log') | Out-Host
        if($LASTEXITCODE -ne 0){throw 'Scan preflight failed; no network changes'}
        $state=New-BoardBackup $backup
        if($batchMode -eq 'Inspect') {
            Write-Host 'PASS BATCH_PREPARE_ONLY: plan and backup checked; no network changes or packets'
            return
        }
        Write-Host 'Keep the ACTIVE14 mask7f7f512 image running; legacy16 and32 images cannot use this plan. Disconnect the wall cable at the PC.'
        Write-Host 'Connect the known-good cable directly from this PC to FPGA. Wait for LED1/2/3 on.'
        Write-Host 'Bulk scan saves every verified frame. A timeout stops the scan; there is no automatic retry.'
        Read-Host 'Press ENTER when the direct connection is ready' | Out-Null
        Invoke-MBatchTransaction $state $backup $destination
    } finally {
        Write-Host ('SCAN_RESULT_DIRECTORY: '+$destination)
        Write-Host ('NETWORK_LOG_DIRECTORY: '+$backup)
        if($state -and $state.MutationStarted) {
            Write-Host 'Reconnect the original wall-network cable after the restore message.'
            Write-Host ('Manual recovery if needed: & '''+$backup+'\restore_network.ps1''')
        } else {Write-Host 'NO_NETWORK_CHANGES_MADE'}
        Stop-Transcript | Out-Null
        if(Test-Path -LiteralPath $destination) {
            foreach($name in @('network_state.json','console.log','plan_preflight.json')) {
                $item=Join-Path $backup $name
                if(Test-Path -LiteralPath $item) {
                    Copy-Item -LiteralPath $item -Destination (Join-Path $destination ($tag+'_'+$name))
                }
            }
            $backup | Set-Content -LiteralPath (Join-Path $destination ($tag+'_network_backup_directory.txt')) -Encoding UTF8
        }
    }
}

if($MyInvocation.InvocationName -ne '.') {Invoke-MBatchMain}

