[CmdletBinding()]
param(
    [ValidateSet('Inspect','Run','Restore')][string]$Mode='Inspect',
    [string]$SessionDirectory='',
    [string]$Python='.\.venv-cos\Scripts\python.exe',
    [string]$Vectors=''
)
$ErrorActionPreference='Stop'
$script:BoardRoot=$PSScriptRoot
$script:OriginalMac=($env:BEAMFORMING_ORIGINAL_MAC -replace '[:-]','')
$script:TestMac='020000000002'
$script:TestIP='192.0.2.2'
$script:BoardIP='192.0.2.1'

function Get-BoardAdapter([string]$Guid='') {
    $all=@(Get-NetAdapter -Physical)
    if($Guid){$found=@($all | Where-Object {[string]$_.InterfaceGuid -eq $Guid})}
    else{$found=@($all | Where-Object {($_.MacAddress -replace '[:-]','') -eq $script:OriginalMac})}
    if($found.Count -ne 1 -or $found[0].InterfaceDescription -notmatch 'Intel.*I219-V'){
        throw 'Expected exactly one known Intel I219-V. Use the saved Restore command if a previous test was interrupted.'
    }
    return $found[0]
}
function Get-BoardRegistry([string]$Guid) {
    $base='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    # The class also contains protected, unrelated subkeys. Only numbered
    # adapter entries can contain NetCfgInstanceId.
    $matches=@(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue |
        Where-Object {$_.PSChildName -match '^\d{4}$'} | Where-Object {
        $_.GetValue('NetCfgInstanceId','') -eq ('{'+$Guid.Trim('{}')+'}')
    })
    if($matches.Count -ne 1){throw 'Cannot identify the exact adapter registry key'}
    $key=$matches[0]
    $exists=@($key.GetValueNames()) -contains 'NetworkAddress'
    if($exists -and [string]$key.GetValueKind('NetworkAddress') -ne 'String'){throw 'Unexpected NetworkAddress value type'}
    return [pscustomobject]@{Path=$key.PSPath;Exists=$exists;Value=[string]$key.GetValue('NetworkAddress','')}
}
function Save-BoardJournal($State,[string]$Directory) {
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'network_state.json') -Encoding UTF8
}
function New-BoardBackup([string]$Directory) {
    $a=Get-BoardAdapter
    $prop=Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword NetworkAddress -AllProperties
    if(!$prop){throw 'Driver does not expose NetworkAddress'}
    $reg=Get-BoardRegistry ([string]$a.InterfaceGuid)
    if(@(Get-NetIPAddress -IPAddress $script:TestIP -ErrorAction SilentlyContinue).Count){throw 'Test IPv4 address already exists; no changes made'}
    if(@(Get-NetRoute -DestinationPrefix ($script:BoardIP+'/32') -AddressFamily IPv4 -ErrorAction SilentlyContinue).Count){throw 'An existing route to the board needs review; no changes made'}
    $iface=Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4
    $state=[pscustomobject]@{
        Schema=1;AdapterGuid=[string]$a.InterfaceGuid;AdapterName=[string]$a.Name
        Description=[string]$a.InterfaceDescription;OriginalMac=([string]$a.MacAddress -replace '[:-]','')
        OriginalDhcp=[string]$iface.Dhcp;OverrideExists=[bool]$reg.Exists;OverrideValue=[string]$reg.Value
        OriginalIPv4=@(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Select-Object IPAddress,PrefixLength,PrefixOrigin)
        OriginalRoutes=@(Get-NetRoute -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Select-Object DestinationPrefix,NextHop,RouteMetric,Protocol)
        OriginalDNS=@(Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses)
        OriginalReceiveLinkSpeed=[uint64]$a.ReceiveLinkSpeed;OriginalTransmitLinkSpeed=[uint64]$a.TransmitLinkSpeed
        MutationStarted=$false;OwnIP=$false;OwnRoute=$false;Restored=$false
    }
    if($state.OriginalDhcp -notin @('Enabled','Disabled')){throw 'Unknown original DHCP mode'}
    Save-BoardJournal $state $Directory
    $rootQuoted=$script:BoardRoot.Replace("'","''")
    $dirQuoted=$Directory.Replace("'","''")
    "& '$rootQuoted\run_single_nic_board_test.ps1' -Mode Restore -SessionDirectory '$dirQuoted'" |
        Set-Content -LiteralPath (Join-Path $Directory 'restore_network.ps1') -Encoding UTF8
    return $state
}
function Restore-BoardMac($State,$Adapter) {
    $reg=Get-BoardRegistry $State.AdapterGuid
    if($State.OverrideExists){
        New-ItemProperty -LiteralPath $reg.Path -Name NetworkAddress -Value $State.OverrideValue -PropertyType String -Force | Out-Null
    }elseif($reg.Exists){
        Remove-ItemProperty -LiteralPath $reg.Path -Name NetworkAddress
    }
    Restart-NetAdapter -Name $Adapter.Name -Confirm:$false
}
function Restore-BoardState($State,[string]$Directory) {
    if($State.Schema -ne 1 -or $State.OriginalMac -ne $script:OriginalMac){throw 'Invalid backup identity'}
    if(!$State.MutationStarted){Write-Host 'NO_NETWORK_CHANGES_TO_RESTORE';return}
    $a=Get-BoardAdapter $State.AdapterGuid
    if($State.Restored){
        if(($a.MacAddress -replace '[:-]','') -ne $State.OriginalMac){throw 'Backup was already restored; current MAC differs and needs review'}
        Write-Host 'NETWORK_CONFIGURATION_ALREADY_RESTORED';return
    }
    $failures=New-Object 'System.Collections.Generic.List[string]'
    if($State.OwnRoute){
        try{
            Get-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix ($script:BoardIP+'/32') -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                Where-Object {$_.NextHop -eq '0.0.0.0'} | Remove-NetRoute -Confirm:$false -ErrorAction Stop
        }catch{$failures.Add('route: '+$_.Exception.Message)}
    }
    if($State.OwnIP){
        try{
            Get-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $script:TestIP -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction Stop
        }catch{$failures.Add('IPv4: '+$_.Exception.Message)}
    }
    try{Restore-BoardMac $State $a}catch{$failures.Add('MAC: '+$_.Exception.Message)}
    try{
        $a=Get-BoardAdapter $State.AdapterGuid
        Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp $State.OriginalDhcp
        for($i=0;$i -lt 20;$i++){
            $after=Get-BoardAdapter $State.AdapterGuid
            if(($after.MacAddress -replace '[:-]','') -eq $State.OriginalMac){break}
            Start-Sleep -Seconds 1
        }
        if(($after.MacAddress -replace '[:-]','') -ne $State.OriginalMac){throw 'Restored MAC did not match backup'}
        $now=Get-NetIPInterface -InterfaceIndex $after.ifIndex -AddressFamily IPv4
        if([string]$now.Dhcp -ne $State.OriginalDhcp){throw 'DHCP mode did not match backup'}
        $reg=Get-BoardRegistry $State.AdapterGuid
        if($reg.Exists -ne $State.OverrideExists -or ($reg.Exists -and $reg.Value -cne $State.OverrideValue)){
            throw 'NetworkAddress override did not match backup'
        }
    }catch{$failures.Add('verification: '+$_.Exception.Message)}
    $State.Restored=($failures.Count -eq 0)
    Save-BoardJournal $State $Directory
    if($failures.Count){throw ('RESTORE_REQUIRED: '+($failures -join '; '))}
    Write-Host 'PASS NETWORK_CONFIGURATION_RESTORED: original MAC/override and IPv4 address mode verified'
}
function Wait-BoardLink([string]$Guid) {
    for($i=0;$i -lt 45;$i++){
        $a=Get-BoardAdapter $Guid
        if(($a.MacAddress -replace '[:-]','') -eq $script:TestMac -and $a.Status -eq 'Up' -and
            [uint64]$a.ReceiveLinkSpeed -eq 1000000000 -and [uint64]$a.TransmitLinkSpeed -eq 1000000000){return $a}
        Start-Sleep -Seconds 1
    }
    throw 'Expected test MAC and 1Gbps direct link did not appear'
}
function Set-BoardTestEndpoint($State,[string]$Directory) {
    $a=Get-BoardAdapter $State.AdapterGuid
    $State.MutationStarted=$true;Save-BoardJournal $State $Directory
    Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword NetworkAddress -RegistryValue $script:TestMac -NoRestart
    Restart-NetAdapter -Name $a.Name -Confirm:$false
    $a=Wait-BoardLink $State.AdapterGuid
    # Add only the temporary address and /32 route. Existing static addresses,
    # DNS servers, default routes, metrics and firewall settings are untouched.
    Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -Dhcp Disabled
    $State.OwnIP=$true;Save-BoardJournal $State $Directory
    New-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $script:TestIP -PrefixLength 24 -AddressFamily IPv4 -PolicyStore ActiveStore | Out-Null
    $State.OwnRoute=$true;Save-BoardJournal $State $Directory
    New-NetRoute -InterfaceIndex $a.ifIndex -DestinationPrefix ($script:BoardIP+'/32') -NextHop '0.0.0.0' -RouteMetric 1 -PolicyStore ActiveStore | Out-Null
    $preferred=$false
    for($i=0;$i -lt 15;$i++){
        $ip=Get-NetIPAddress -InterfaceIndex $a.ifIndex -IPAddress $script:TestIP -AddressFamily IPv4
        if($ip.AddressState -eq 'Duplicate'){throw 'Duplicate test IPv4 address'}
        if($ip.AddressState -eq 'Preferred'){$preferred=$true;break}
        Start-Sleep -Seconds 1
    }
    if(!$preferred){throw 'Test IPv4 address did not become usable'}
    $routes=@(Find-NetRoute -RemoteIPAddress $script:BoardIP -LocalIPAddress $script:TestIP)
    if(!$routes.Count -or @($routes | Where-Object {$_.InterfaceIndex -ne $a.ifIndex}).Count){throw 'Board route selected a different adapter'}
    $a | Select-Object Name,Status,MacAddress,LinkSpeed | Format-Table | Out-Host
}
function Invoke-BoardPacketTest([string]$Directory,[string]$PythonPath) {
    $packetArgs=@('--output',(Join-Path $Directory 'udp'),'--host',$script:BoardIP)
    if($Vectors){$packetArgs+=@('--vectors',$Vectors)}
    & $PythonPath (Join-Path $script:BoardRoot 'python\board_udp_smoke.py') @packetArgs 2>&1 |
        Tee-Object -FilePath (Join-Path $Directory 'udp_console.log') | Out-Host
    if($LASTEXITCODE -ne 0){throw 'BOARD_UDP_TEST_FAILED: see udp_console.log and udp/failure.json'}
}
function Invoke-BoardTestTransaction($State,[string]$Directory,[string]$PythonPath) {
    try{
        Set-BoardTestEndpoint $State $Directory
        Invoke-BoardPacketTest $Directory $PythonPath
    }finally{
        Restore-BoardState $State $Directory
    }
}
function Invoke-BoardMain {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    if($Mode -ne 'Inspect' -and !$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
        throw 'Open Windows PowerShell as Administrator, then run this command again.'
    }
    $base=Join-Path $script:BoardRoot 'validation\board_20261023'
    if($Mode -eq 'Restore'){
        $resolved=[IO.Path]::GetFullPath($SessionDirectory)
        if(!$resolved.StartsWith(([IO.Path]::GetFullPath($base)+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'Restore directory must be inside this project validation/board_20261023'
        }
        $state=Get-Content -LiteralPath (Join-Path $resolved 'network_state.json') -Raw | ConvertFrom-Json
        Restore-BoardState $state $resolved
        Write-Host 'Reconnect the original wall-network cable at the PC to resume Internet access.'
        return
    }
    if(!(Test-Path -LiteralPath $Python)){throw 'Bundled project Python not found'}
    $dir=Join-Path $base ('host_smoke_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $dir | Out-Null
    Start-Transcript -LiteralPath (Join-Path $dir 'console.log') | Out-Null
    $state=$null
    try{
        Write-Host ('SESSION_DIRECTORY: '+$dir)
        $state=New-BoardBackup $dir
        $offlineArgs=@('--output',(Join-Path $dir 'offline'))
        if($Vectors){$offlineArgs+=@('--vectors',$Vectors)}
        & $Python (Join-Path $script:BoardRoot 'python\board_udp_smoke.py') @offlineArgs
        if($LASTEXITCODE -ne 0){throw 'Offline reference/input preflight failed'}
        if($Mode -eq 'Inspect'){Write-Host 'PASS PREPARE_ONLY: backup and offline check; no network changes or packets';return}
        Write-Host 'Keep the full network image running. Disconnect the wall-network cable at the PC.'
        Write-Host 'Connect the known-good cable directly between this PC and the FPGA. Wait for LED1/2/3 on.'
        Read-Host 'Press ENTER when the direct connection is ready' | Out-Null
        Invoke-BoardTestTransaction $state $dir $Python
    }finally{
        Write-Host ('LOG_DIRECTORY: '+$dir)
        if($state -and $state.MutationStarted){
            Write-Host 'Reconnect the original wall-network cable at the PC after the restore message.'
            Write-Host ('Manual recovery command if needed: & '''+$dir+'\restore_network.ps1''')
        }else{Write-Host 'NO_NETWORK_CHANGES_MADE'}
        Stop-Transcript | Out-Null
    }
}
if($MyInvocation.InvocationName -ne '.') {Invoke-BoardMain}
