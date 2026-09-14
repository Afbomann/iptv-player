$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$fontDirectory = Join-Path $projectRoot 'assets/fonts'
New-Item -ItemType Directory -Path $fontDirectory -Force | Out-Null
$assets = @(
  @{ Url = 'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm'; Path = 'web/sqlite3.wasm' },
  @{ Url = 'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf'; Path = 'assets/fonts/Manrope.ttf' },
  @{ Url = 'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/OFL.txt'; Path = 'assets/fonts/Manrope-LICENSE.txt' },
  @{ Url = 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/Newsreader%5Bopsz%2Cwght%5D.ttf'; Path = 'assets/fonts/Newsreader.ttf' },
  @{ Url = 'https://raw.githubusercontent.com/google/fonts/main/ofl/newsreader/OFL.txt'; Path = 'assets/fonts/Newsreader-LICENSE.txt' }
)
foreach ($asset in $assets) {
  $destination = Join-Path $projectRoot $asset.Path
  if (-not (Test-Path -LiteralPath $destination)) {
    Invoke-WebRequest -Uri $asset.Url -OutFile $destination
  }
  Get-FileHash -LiteralPath $destination -Algorithm SHA256 | Select-Object Hash, Path
}
