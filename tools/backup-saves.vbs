' backup-saves.vbs -- run backup-saves.ps1 with no visible window.
' Called by Task Scheduler. Path is derived from this file, never hard-coded.
' ASCII only on purpose (wscript reads ANSI).

Dim fso, sh, here, script
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here   = fso.GetParentFolderName(WScript.ScriptFullName)
script = here & "\backup-saves.ps1"

If Not fso.FileExists(script) Then
    WScript.Quit 2
End If

' 0 = hidden window, False = do not wait
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & script & """ -Once", 0, False
