Option Explicit

Dim shell, fso, folder, scriptPath, command, argument
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(folder, "FocusGuard.ps1")
argument = ""
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "/minimized" Then argument = " -StartMinimized"
End If
command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & scriptPath & """" & argument
shell.Run command, 0, False
