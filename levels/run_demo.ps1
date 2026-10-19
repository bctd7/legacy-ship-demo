param(
    [string] $GodotExecutable = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GodotArguments
)
$ErrorActionPreference = 'Stop'
$levelProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $GodotExecutable -PathType Leaf)) {
    throw 'Existing Godot executable not found. Pass -GodotExecutable with its full path; nothing will be installed.'
}
& $GodotExecutable --path $levelProjectRoot --scene 'res://levels/integrated_demo.tscn' @GodotArguments
exit $LASTEXITCODE
