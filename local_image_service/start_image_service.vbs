Option Explicit
Dim fso, shell, folder, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
command = "pythonw.exe " & Chr(34) & folder & "\desktop_launcher.py" & Chr(34)
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
    MsgBox "The existing pythonw.exe could not be started. No service or generation was started.", 48, "Local image service"
End If
