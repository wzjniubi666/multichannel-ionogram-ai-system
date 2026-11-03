param([string]$RequestFile='',[string]$RestoreDirectory='')
$ErrorActionPreference='Stop'
$OutputEncoding=New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding=$OutputEncoding
$guiRoot=$PSScriptRoot
. (Join-Path $guiRoot 'workspace_paths.ps1')
$workspaceRoot=Find-BeamformingWorkspace $guiRoot
$project=Join-Path $workspaceRoot 'XCK325Tboshuhecheng'
$guiPython=Join-Path $workspaceRoot '.venv-cos\Scripts\python.exe'
. (Join-Path $project 'run_single_nic_board_test.ps1') -Mode Inspect -Python $guiPython

function Write-GuiLine([string]$Line) {
    [Console]::Out.WriteLine($Line)
    [Console]::Out.Flush()
}

function Invoke-GuiPreflight($Request,[string]$Path) {
    & $guiPython -E -X utf8 -u (Join-Path $guiRoot 'worker.py') preflight --request $Path |
        ForEach-Object {Write-GuiLine ([string]$_)}
    if($LASTEXITCODE -ne 0){throw 'Image/plan preflight or cancellation gate failed; no network changes'}
}
function Invoke-GuiPacketWorker($Request,[string]$Path) {
    & $guiPython -E -X utf8 -u (Join-Path $guiRoot 'worker.py') scan --request $Path |
        ForEach-Object {Write-GuiLine ([string]$_)}
    if($LASTEXITCODE -ne 0){throw 'Packet worker failed; partial verified results have been retained'}
}
function Write-GuiStage([string]$Name) {
    Write-GuiLine ('GUI_EVENT '+(@{kind='stage';name=$Name;detail=''} | ConvertTo-Json -Compress))
}
function Invoke-GuiNetworkSession($Request,[string]$Path) {
    if($Request.mode -ne 'hardware' -or !$Request.direct_connection_confirmed){throw 'Explicit hardware/direct-connection selection required'}
    $backup=Join-Path $project ('validation\board_20261023\gui_active14_'+(Get-Date -Format yyyyMMdd_HHmmss)+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $backup | Out-Null
    $state=$null;$failure='';$restoreFailure='';$restored=$false
    Start-Transcript -LiteralPath (Join-Path $backup 'console.log') | Out-Null
    try {
        Invoke-GuiPreflight $Request $Path
        if(Test-Path -LiteralPath $Request.stop_file){throw 'Cancelled before network configuration'}
        $state=New-BoardBackup $backup
        Write-GuiLine ('GUI_EVENT '+(@{kind='backup';path=$backup} | ConvertTo-Json -Compress))
        if(Test-Path -LiteralPath $Request.stop_file){throw 'Cancelled before network configuration'}
        Set-BoardTestEndpoint $state $backup
        Write-GuiStage '网口已连接，开始传输'
        Invoke-GuiPacketWorker $Request $Path
    } catch {
        $failure=$_.Exception.Message
        Write-Host ('SESSION_ERROR: '+$failure)
    } finally {
        Write-GuiStage '恢复原网卡配置，请稍候'
        if($state){
            try {
                Restore-BoardState $state $backup
                $restored=(!$state.MutationStarted -or $state.Restored)
            } catch {$restoreFailure=$_.Exception.Message}
        } else {$restored=$true}
        $record=@{restored=[bool]$restored;mutated=[bool]($state -and $state.MutationStarted);
            backup_directory=$backup;error=$failure;restore_error=$restoreFailure}
        $out=Join-Path (Split-Path -Parent $Path) 'network_result.json'
        $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $out -Encoding utf8
        Stop-Transcript | Out-Null
    }
    if(!$restored){throw ('RESTORE_REQUIRED: '+$backup+' '+$restoreFailure)}
    if($failure){throw $failure}
}

if($MyInvocation.InvocationName -ne '.') {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required'}
    $mutex=New-Object System.Threading.Mutex($false,'Local\BeamformingActive14Host_NetworkSession')
    $owns=$false
    try {
        try{$owns=$mutex.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$owns=$true}
        if(!$owns){throw 'Another desktop host is using/restoring the adapter; wait for it to finish'}
        if($RestoreDirectory){
            & (Join-Path $project 'run_single_nic_board_test.ps1') -Mode Restore -SessionDirectory $RestoreDirectory -Python $guiPython
        } else {
            if(!$RequestFile){throw 'RequestFile is required for transmission'}
            $request=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
            Invoke-GuiNetworkSession $request ([IO.Path]::GetFullPath($RequestFile))
        }
    } finally {
        if($owns){$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}
