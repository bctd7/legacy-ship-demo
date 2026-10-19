param(
    [ValidateSet('stub', 'official')][string] $Mode = 'stub',
    [ValidateRange(1, 65535)][int] $Port = 8769,
    [string] $GodotExecutable = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$levelProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw 'Existing Godot executable not found. Pass -GodotExecutable with its full path.'
}
# Starts only the UI. The separate local service owns user credential setup.
# Opening the stage never submits an image; the user must click its send button.
$canonicalMode = $Mode.ToLowerInvariant()
& $GodotExecutable --path $levelProjectRoot --scene 'res://levels/integrated_demo.tscn' -- "--local-mode=$canonicalMode" "--local-port=$Port"
exit $LASTEXITCODE
