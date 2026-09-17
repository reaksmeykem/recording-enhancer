# Builds Recording Enhancer.exe from enhance-gui.ps1 using PS2EXE (downloaded on demand).
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$src = Join-Path $base 'enhance-gui.ps1'

# ps2exe requires UTF8/UTF16 input; normalize to UTF-8 BOM
$raw = Get-Content -LiteralPath $src -Raw
$utf8 = Join-Path $env:TEMP 'enhance-gui-build.ps1'
[IO.File]::WriteAllText($utf8, $raw, (New-Object System.Text.UTF8Encoding($true)))

$modDir = Join-Path $env:TEMP 'PS2EXE-master'
if (-not (Test-Path (Join-Path $modDir 'Module\ps2exe.psd1'))) {
    $zip = Join-Path $env:TEMP 'PS2EXE-master.zip'
    if (-not (Test-Path $zip)) {
        Write-Output 'Downloading PS2EXE...'
        Invoke-WebRequest -Uri 'https://github.com/MScholtes/PS2EXE/archive/refs/heads/master.zip' -OutFile $zip -UseBasicParsing
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $env:TEMP -Force
}
Import-Module (Join-Path $modDir 'Module\ps2exe.psd1') -Force

$out = Join-Path $base 'Recording Enhancer.exe'
Invoke-ps2exe -inputFile $utf8 -outputFile $out -iconFile (Join-Path $base 'enhancer.ico') `
    -noConsole -x64 -STA -title 'Recording Enhancer' `
    -description 'Voice cleanup for screen recordings (Natural/Classic)' `
    -product 'Recording Enhancer' -copyright 'MIT License' | Out-Null

if (Test-Path $out) { Write-Output "OK: $out ($((Get-Item $out).Length) bytes)" }
else { throw 'Build failed: EXE was not created' }
