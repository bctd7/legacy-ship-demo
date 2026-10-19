param(
    [ValidateRange(1,65535)][int]$Port = 8769,
    [ValidateRange(0,1000)][int]$PriorReservedFen = 0,
    [ValidateSet('flash', 'pro')][string]$ModelProfile = 'flash'
)
$ErrorActionPreference = 'Stop'
$priceFen = if ($ModelProfile -eq 'flash') { 12 } else { 60 }
$priceText = if ($ModelProfile -eq 'flash') { '0.12' } else { '0.60' }
$modelId = if ($ModelProfile -eq 'flash') { 'doubao-seedream-5-0-flash-260915' } else { 'doubao-seedream-5-0-pro-260628' }
$confirmation = Read-Host ("Type YES after enabling {0}, confirming CNY {1} per image, and approving one drawing request. Starting sends nothing" -f $modelId, $priceText)
if ($confirmation -cne 'YES') { Write-Output 'Not started; no credential requested.'; exit 1 }
& python (Join-Path $PSScriptRoot 'server.py') --mode official --port $Port --model-profile $ModelProfile --confirmed-price-fen $priceFen --prior-reserved-fen $PriorReservedFen --confirm-account-and-upload
exit $LASTEXITCODE
