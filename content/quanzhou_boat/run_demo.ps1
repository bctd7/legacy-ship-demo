param([string]$GodotExecutable = '')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $GodotExecutable) {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe')
    )
    $GodotExecutable = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $GodotExecutable) { throw 'Pass -GodotExecutable with the installed Godot 4.7.2 executable path.' }
& $GodotExecutable --path $projectRoot --rendering-method gl_compatibility --scene 'res://content/quanzhou_boat/demo.tscn' --log-file (Join-Path $PSScriptRoot 'evidence\manual_run.log')
