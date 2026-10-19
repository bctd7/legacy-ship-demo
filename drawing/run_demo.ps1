param(
    [string] $GodotExecutable = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GodotArguments
)
$ErrorActionPreference = 'Stop'
$drawingProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw 'Existing Godot executable not found. Pass -GodotExecutable with its full path; nothing will be installed.'
}
if (-not (Test-Path -LiteralPath (Join-Path $drawingProjectRoot 'project.godot') -PathType Leaf)) {
    throw 'Run this launcher inside the existing project drawing directory.'
}
# Explicit scene selection is independent from the editor's current F6 tab.
& $GodotExecutable --path $drawingProjectRoot --scene 'res://drawing/drawing_demo.tscn' @GodotArguments
exit $LASTEXITCODE
