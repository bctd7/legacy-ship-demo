$ErrorActionPreference = 'Stop'
$pythonWindow = Get-Command pythonw.exe -ErrorAction SilentlyContinue
if ($null -eq $pythonWindow) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show('pythonw.exe was not found. Use the existing Python installation; no software was installed.', 'Local image service') | Out-Null
    exit 1
}
$launcherPath = Join-Path $PSScriptRoot 'desktop_launcher.py'
Start-Process -FilePath $pythonWindow.Source -ArgumentList @(('"' + $launcherPath + '"')) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
