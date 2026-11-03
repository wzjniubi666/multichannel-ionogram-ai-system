function Test-BeamformingWorkspace([string]$Path) {
    foreach($relative in @('XCK325Tboshuhecheng/python/m512_active14_release.py','.venv-cos/Scripts/python.exe','HFceshi/m255a.mat')) {
        if(!(Test-Path -LiteralPath (Join-Path $Path $relative))){return $false}
    }
    return $true
}
function Find-BeamformingWorkspace([string]$AppDirectory) {
    $config=Join-Path $AppDirectory 'workspace.path'
    if(Test-Path -LiteralPath $config) {
        $candidate=(Get-Content -LiteralPath $config -Raw -Encoding UTF8).Trim()
        if(![IO.Path]::IsPathRooted($candidate)){$candidate=Join-Path $AppDirectory $candidate}
        $candidate=[IO.Path]::GetFullPath($candidate)
        if(Test-BeamformingWorkspace $candidate){return $candidate}
        throw ('workspace.path points to an incomplete workspace: '+$candidate)
    }
    $candidate=Split-Path -Parent $AppDirectory
    while($candidate) {
        if(Test-BeamformingWorkspace $candidate){return $candidate}
        $parent=Split-Path -Parent $candidate
        if($parent -eq $candidate){break}
        $candidate=$parent
    }
    throw 'Original workspace not found. Run host/deploy/configure_desktop.ps1 -WorkspaceRoot <path>.'
}
