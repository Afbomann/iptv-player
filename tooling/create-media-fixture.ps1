param([string]$Ffmpeg)
$ErrorActionPreference = 'Stop'
if (-not $Ffmpeg) {
  $Ffmpeg = (Get-ChildItem -LiteralPath '.tools/ffmpeg' -Filter ffmpeg.exe -Recurse | Select-Object -First 1).FullName
}
if (-not $Ffmpeg) { throw 'Supply the path to a full FFmpeg build.' }
$fixtureDirectory = Join-Path (Get-Location) '.tools/media-fixture'
New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
& $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=640x360:rate=24' -t 90 -an -c:v libx264 -preset ultrafast -profile:v baseline -level 3.0 -pix_fmt yuv420p -g 48 -sc_threshold 0 -b:v 500k -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$fixtureDirectory/video-%03d.ts" "$fixtureDirectory/video.m3u8"
if ($LASTEXITCODE -ne 0) { throw 'Video fixture generation failed.' }
foreach ($tone in @(@('english',440), @('norwegian',880))) {
  $trackName = $tone[0]
  & $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=$($tone[1]):sample_rate=48000" -t 90 -c:a aac -b:a 64k -f hls -hls_time 2 -hls_playlist_type vod -hls_segment_filename "$fixtureDirectory/$trackName-%03d.ts" "$fixtureDirectory/$trackName.m3u8"
  if ($LASTEXITCODE -ne 0) { throw 'Audio fixture generation failed.' }
}
Write-Output 'Generated synthetic 90-second HLS video and two distinguishable audio tones.'
