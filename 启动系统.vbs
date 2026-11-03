Option Explicit
Dim fso, root, shell, script
Set fso=CreateObject("Scripting.FileSystemObject")
root=fso.GetParentFolderName(WScript.ScriptFullName)
script=fso.BuildPath(root,"host\deploy\start_system.ps1")
Set shell=CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """", 0, False
