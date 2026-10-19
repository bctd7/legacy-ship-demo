param([Parameter(Mandatory=$true)][string]$GodotConsole)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotConsole -PathType Leaf)) { throw 'Godot console executable not found.' }
$evidenceRoot = Join-Path $projectRoot 'docs\validation'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$checks = @('verify_drag_identity', 'verify_pose_preview', 'verify_inventory_slots', 'verify_surface_targets', 'verify_centre_beams', 'verify_deck_family')
foreach ($checkName in $checks) {
    $logPath = Join-Path $evidenceRoot ($checkName + '.log')
    & $GodotConsole --path $projectRoot --script ('res://tests/' + $checkName + '.gd') --log-file $logPath -- $evidenceRoot
    if ($LASTEXITCODE -ne 0) { throw ('Check failed: ' + $checkName + '. See ' + $logPath) }
}
Write-Output 'CURRENT_CHECKS_ALL_PASSED'
