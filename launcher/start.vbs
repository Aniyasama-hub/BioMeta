Option Explicit
Dim shell, fso, root, command, arg
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & root & "\launcher\tray.ps1"""
For Each arg In WScript.Arguments
  If InStr(arg, Chr(34)) > 0 Then WScript.Quit 2
  command = command & " """ & arg & """"
Next
shell.Run command, 0, False
