[CmdletBinding()]
param([string]$InstallDirectory, [switch]$CheckBridge, [switch]$PrepareGitHub)

$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskVersion = '1.0.0'
$taskArchiveName = "advanced_rpc_$taskVersion.zip"
$taskOutput = Join-Path $taskRoot 'dist'
$taskArchivePath = Join-Path $taskOutput $taskArchiveName
$taskIconSource = Join-Path $taskRoot 'mod_info/ADVANCEDRPC/icon.png'
$taskIconPath = Join-Path $taskRoot 'bridge/icon.ico'
Add-Type -AssemblyName System.Drawing
$taskImage = [Drawing.Image]::FromFile($taskIconSource)
try {
  $taskIconImages = foreach ($taskSize in @(16, 32, 48, 64, 128, 256)) {
    $taskBitmap = [Drawing.Bitmap]::new($taskSize, $taskSize)
    $taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
    $taskMemory = [IO.MemoryStream]::new()
    try {
      $taskGraphics.Clear([Drawing.Color]::Black)
      $taskGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $taskScale = [Math]::Min($taskSize / $taskImage.Width, $taskSize / $taskImage.Height)
      $taskWidth = [int][Math]::Round($taskImage.Width * $taskScale)
      $taskHeight = [int][Math]::Round($taskImage.Height * $taskScale)
      $taskGraphics.DrawImage($taskImage, [int](($taskSize - $taskWidth) / 2), [int](($taskSize - $taskHeight) / 2), $taskWidth, $taskHeight)
      $taskBitmap.Save($taskMemory, [Drawing.Imaging.ImageFormat]::Png)
      if ($taskSize -eq 256) { $taskBitmap.Save((Join-Path $taskRoot 'mod_info/ADVANCEDRPC/icon.jpg'), [Drawing.Imaging.ImageFormat]::Jpeg) }
      [pscustomobject]@{ Size = $taskSize; Bytes = $taskMemory.ToArray() }
    } finally { $taskGraphics.Dispose(); $taskBitmap.Dispose(); $taskMemory.Dispose() }
  }
  $taskIconWriter = [IO.BinaryWriter]::new([IO.File]::Create($taskIconPath))
  try {
    $taskIconWriter.Write([uint16]0)
    $taskIconWriter.Write([uint16]1)
    $taskIconWriter.Write([uint16]$taskIconImages.Count)
    $taskOffset = 6 + 16 * $taskIconImages.Count
    foreach ($taskIconImage in $taskIconImages) {
      $taskDimension = if ($taskIconImage.Size -eq 256) { 0 } else { $taskIconImage.Size }
      $taskIconWriter.Write([byte]$taskDimension)
      $taskIconWriter.Write([byte]$taskDimension)
      $taskIconWriter.Write([uint16]0)
      $taskIconWriter.Write([uint16]1)
      $taskIconWriter.Write([uint16]32)
      $taskIconWriter.Write([uint32]$taskIconImage.Bytes.Length)
      $taskIconWriter.Write([uint32]$taskOffset)
      $taskOffset += $taskIconImage.Bytes.Length
    }
    foreach ($taskIconImage in $taskIconImages) { $taskIconWriter.Write([byte[]]$taskIconImage.Bytes) }
  } finally { $taskIconWriter.Dispose() }
} finally { $taskImage.Dispose() }
$taskPaths = @(
  'lua/common/advancedRPC/model.lua',
  'lua/common/advancedRPC/context.lua',
  'lua/common/advancedRPC/ipc.lua',
  'lua/common/advancedRPC/bridge.lua',
  'lua/ge/extensions/advancedRPC.lua',
  'lua/vehicle/extensions/advancedRPCTelemetry.lua',
  'scripts/advancedRPC/modScript.lua',
  'ui/ui-vue/mods/AdvancedRPC/index.js',
  'ui/ui-vue/mods/AdvancedRPC/settingsModel.js',
  'ui/ui-vue/mods/AdvancedRPC/Field.vue',
  'ui/ui-vue/mods/AdvancedRPC/Settings.vue',
  'mod_info.json',
  'mod_info/ADVANCEDRPC/info.json',
  'mod_info/ADVANCEDRPC/icon.png',
  'mod_info/ADVANCEDRPC/icon.jpg'
)
foreach ($taskRelative in $taskPaths) {
  $taskFile = Join-Path $taskRoot $taskRelative
  if (-not (Test-Path -LiteralPath $taskFile -PathType Leaf)) { throw "Missing package file: $taskRelative" }
  if ($taskRelative -match '\.(png|jpg)$') { continue }
  $taskSource = [IO.File]::ReadAllText($taskFile)
  if ($taskRelative -match '\.(lua|js|vue)$' -and $taskSource -match '(?m)^\s*(--|//|/\*|<!--)') { throw "Code comments are not allowed: $taskRelative" }
  if ($taskRelative -match '\.json$') { $null = $taskSource | ConvertFrom-Json }
}
$taskMetadata = Get-Content -LiteralPath (Join-Path $taskRoot 'mod_info.json') -Raw | ConvertFrom-Json
$taskManagerMetadata = Get-Content -LiteralPath (Join-Path $taskRoot 'mod_info/ADVANCEDRPC/info.json') -Raw | ConvertFrom-Json
if ($taskMetadata.version -ne $taskVersion -or $taskManagerMetadata.version_string -ne $taskVersion -or $taskManagerMetadata.filename -ne $taskArchiveName) { throw 'Version mismatch.' }
$taskHashes = foreach ($taskRelative in $taskPaths | Where-Object { $_ -like 'ui/*' }) { (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $taskRoot $taskRelative)).Hash }
$taskHasher = [Security.Cryptography.SHA256]::Create()
try { $taskHash = [BitConverter]::ToString($taskHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes(($taskHashes -join '')))).Replace('-', '').Substring(0, 12).ToLowerInvariant() }
finally { $taskHasher.Dispose() }
$taskMenuFolder = "AdvancedRPC_$taskHash"
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskCompiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$taskBridgeSource = Join-Path $taskRoot 'bridge/Bridge.cs'
$taskBridge = Join-Path $taskOutput 'AdvancedRPC Bridge.exe'
if ([IO.File]::ReadAllText($taskBridgeSource) -match '(?m)^\s*(//|/\*)') { throw 'Code comments are not allowed in the bridge.' }
& $taskCompiler /nologo /target:winexe /platform:x64 /optimize+ /utf8output /warn:4 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/win32icon:$taskIconPath" "/out:$taskBridge" $taskBridgeSource
if ($LASTEXITCODE -ne 0) { throw 'Bridge build failed.' }
if ([Diagnostics.FileVersionInfo]::GetVersionInfo($taskBridge).FileVersion -ne "$taskVersion.0") { throw 'Bridge version mismatch.' }
if ($CheckBridge) {
  $taskTestExe = Join-Path $taskOutput 'advanced_rpc_bridge_check.exe'
  try {
    & $taskCompiler /nologo /target:exe /platform:x64 /optimize+ /utf8output /main:AdvancedRPC.BridgeTests /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/out:$taskTestExe" $taskBridgeSource (Join-Path $taskRoot 'tests/BridgeTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Bridge test build failed.' }
    & $taskTestExe
    if ($LASTEXITCODE -ne 0) { throw 'Bridge checks failed.' }
  } finally { if (Test-Path -LiteralPath $taskTestExe) { Remove-Item -LiteralPath $taskTestExe -Force } }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskStream = [IO.File]::Open($taskArchivePath, [IO.FileMode]::Create)
$taskArchive = [IO.Compression.ZipArchive]::new($taskStream, [IO.Compression.ZipArchiveMode]::Create, $false)
try {
  foreach ($taskRelative in $taskPaths) {
    $taskEntryName = $taskRelative.Replace('ui/ui-vue/mods/AdvancedRPC/', "ui/ui-vue/mods/$taskMenuFolder/")
    $taskBytes = [IO.File]::ReadAllBytes((Join-Path $taskRoot $taskRelative))
    if ($taskRelative -eq 'ui/ui-vue/mods/AdvancedRPC/index.js') { $taskBytes = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($taskBytes).Replace('/ui/ui-vue/mods/AdvancedRPC/', "/ui/ui-vue/mods/$taskMenuFolder/")) }
    $taskEntry = $taskArchive.CreateEntry($taskEntryName, [IO.Compression.CompressionLevel]::Optimal)
    $taskWriter = $taskEntry.Open()
    try { $taskWriter.Write($taskBytes, 0, $taskBytes.Length) } finally { $taskWriter.Dispose() }
  }
} finally { $taskArchive.Dispose(); $taskStream.Dispose() }
$taskCheck = [IO.Compression.ZipFile]::OpenRead($taskArchivePath)
try {
  if ($taskCheck.Entries.Count -ne $taskPaths.Count) { throw 'Unexpected archive entry count.' }
  foreach ($taskEntry in $taskCheck.Entries) {
    if ($taskEntry.FullName -match '(^|/)(README|tests|tools|dist|validation)' -or $taskEntry.FullName.Contains('..')) { throw "Unexpected entry: $($taskEntry.FullName)" }
    $taskReader = $taskEntry.Open()
    $taskMemory = [IO.MemoryStream]::new()
    try { $taskReader.CopyTo($taskMemory); $taskBytes = $taskMemory.ToArray() } finally { $taskReader.Dispose(); $taskMemory.Dispose() }
    $taskSourceRelative = $taskEntry.FullName.Replace("ui/ui-vue/mods/$taskMenuFolder/", 'ui/ui-vue/mods/AdvancedRPC/')
    $taskExpected = [IO.File]::ReadAllBytes((Join-Path $taskRoot $taskSourceRelative))
    if ($taskSourceRelative -eq 'ui/ui-vue/mods/AdvancedRPC/index.js') { $taskExpected = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($taskExpected).Replace('/ui/ui-vue/mods/AdvancedRPC/', "/ui/ui-vue/mods/$taskMenuFolder/")) }
    if ([Convert]::ToBase64String($taskBytes) -cne [Convert]::ToBase64String($taskExpected)) { throw "Package content mismatch: $taskSourceRelative" }
  }
} finally { $taskCheck.Dispose() }
$taskSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $taskArchivePath).Hash
if ($InstallDirectory) {
  $taskInstallPath = Join-Path ([IO.Path]::GetFullPath($InstallDirectory)) $taskArchiveName
  if (-not (Test-Path -LiteralPath $InstallDirectory -PathType Container)) { throw 'The BeamNG mods directory does not exist.' }
  Copy-Item -LiteralPath $taskArchivePath -Destination $taskInstallPath -Force
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $taskInstallPath).Hash -ne $taskSha) { throw 'Installed archive checksum mismatch.' }
  $taskLegacyInstall = Join-Path ([IO.Path]::GetFullPath($InstallDirectory)) "custom_rpc_$taskVersion.zip"
  if (Test-Path -LiteralPath $taskLegacyInstall -PathType Leaf) { Remove-Item -LiteralPath $taskLegacyInstall -Force }
  Write-Output "Installed: $taskInstallPath"
}
Write-Output "Verified $($taskPaths.Count) files: $taskArchivePath"
Write-Output "Bridge: $taskBridge"
Write-Output "SHA256: $taskSha"
if ($PrepareGitHub) {
  $taskGitHub = Join-Path $taskRoot 'github'
  $taskPublishPaths = @($taskPaths) + @('build.ps1', '.gitignore', 'bridge/Bridge.cs', 'bridge/icon.ico', 'tests/unit.lua', 'tests/BridgeTests.cs', 'tools/check.mjs', 'tools/live.mjs', "dist/$taskArchiveName", 'dist/AdvancedRPC Bridge.exe')
  foreach ($taskRelative in $taskPublishPaths) {
    $taskDestination = Join-Path $taskGitHub $taskRelative
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskDestination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $taskRoot $taskRelative) -Destination $taskDestination -Force
    if ((Get-FileHash -LiteralPath $taskDestination).Hash -ne (Get-FileHash -LiteralPath (Join-Path $taskRoot $taskRelative)).Hash) { throw "GitHub content mismatch: $taskRelative" }
  }
  Write-Output "GitHub upload folder: $taskGitHub ($($taskPublishPaths.Count) files)"
}
