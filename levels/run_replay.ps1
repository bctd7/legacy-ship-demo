param(
    [string] $ImagePath = 'res://tests/image_generation/fourth_real_bridge/seedream_pro_bridge_result.png',
    [string] $GodotExecutable = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$levelReplayRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) { throw 'Existing Godot executable not found.' }
# Starts UI only. The replay adapter never constructs a network service.
& $GodotExecutable --path $levelReplayRoot --scene 'res://levels/integrated_demo.tscn' -- "--replay-image=$ImagePath"
exit $LASTEXITCODE
