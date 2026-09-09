param(
    [string]$Version = '0.3.4'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
[array]$compilerCandidates = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if ($compilerCandidates.Count -eq 0) {
    throw 'Inno Setup 6 is required to build the optional installer. The portable ZIP does not require it.'
}

$source = Join-Path $project 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $source 'niraN.exe'))) {
    throw 'Windows Release bundle is missing. Run flutter build windows --release first.'
}

$compiler = $compilerCandidates[0]
& $compiler "/DAppVersion=$Version" "/DSourceDir=$source" (Join-Path $project 'installer\niraN.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
