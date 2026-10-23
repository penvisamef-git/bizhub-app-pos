# Build BizHub POS for Windows (production settings) and make the installer.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1
#     -> build\installer\BizHub-POS-Setup-<version>.exe   (when Inno Setup 6 is installed)
#     -> build\installer\BizHub-POS-<version>-windows.zip (always: the app folder, for a quick copy)
#
# Needs, on a Windows PC: Flutter, Visual Studio 2022 with "Desktop development with C++", env.prod.json
# (production API), and for the installer Inno Setup 6 (winget install JRSoftware.InnoSetup).
# Only the windows\ desktop app is built here; the Android / iPhone apps are not touched.
#
#   -Step app        only build the app (GitHub signs BizHubPOS.exe after this)
#   -Step installer  only make the .zip + setup from the app already built
#   (default: both)
#
# Signing on your own PC (optional): set SIGN_PFX (a .pfx file) and SIGN_PFX_PASSWORD, or SIGN_THUMBPRINT
# (a certificate in Windows' store / on a USB token) — then BizHubPOS.exe and the setup file are signed with signtool.
param([ValidateSet('all', 'app', 'installer')][string]$Step = 'all')
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path windows)) { throw 'The windows\ folder is missing.' }
if (-not (Test-Path env.prod.json)) { throw 'env.prod.json is missing (production settings).' }
if (-not (Select-String -Path env.prod.json -Pattern '"API_HOST":\s*"https://bizhub-api-eight-production.vercel.app"' -Quiet)) {
  throw 'env.prod.json does not point at the production API.'
}

function Find-SignTool {
  $kits = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
  if (-not (Test-Path $kits)) { return $null }
  Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}

# signs one file when a local certificate is set up (otherwise does nothing)
function Invoke-Sign([string]$file) {
  if (-not $env:SIGN_PFX -and -not $env:SIGN_THUMBPRINT) { return $false }
  $tool = Find-SignTool
  if (-not $tool) { throw 'signtool.exe not found (install the Windows 10/11 SDK).' }
  $sargs = @('sign', '/fd', 'SHA256', '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256', '/d', 'BizHub POS')
  if ($env:SIGN_PFX) { $sargs += @('/f', $env:SIGN_PFX); if ($env:SIGN_PFX_PASSWORD) { $sargs += @('/p', $env:SIGN_PFX_PASSWORD) } }
  else { $sargs += @('/sha1', $env:SIGN_THUMBPRINT) }
  & $tool @sargs $file
  if ($LASTEXITCODE -ne 0) { throw "signing $file failed" }
  return $true
}

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value).Trim()
$name = $version.Split('+')[0]
$release = 'build\windows\x64\runner\Release'
$signed = $false

if ($Step -ne 'installer') {
  Write-Host "* building BizHub POS $version for Windows (production)..."
  flutter build windows --release --dart-define-from-file=env.prod.json
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
  if (-not (Test-Path "$release\BizHubPOS.exe")) { throw "build finished but $release\BizHubPOS.exe is missing" }

  # The Visual C++ runtime goes next to the app, so it also opens on PCs that never installed it
  foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $src = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $src) { Copy-Item $src $release -Force } else { Write-Warning "$dll not found in System32 (install the VC++ 2015-2022 x64 redistributable)" }
  }
  $signed = Invoke-Sign "$release\BizHubPOS.exe"
  if ($Step -eq 'app') { Write-Host "OK  $release\BizHubPOS.exe"; exit 0 }
}

if (-not (Test-Path "$release\BizHubPOS.exe")) { throw "$release\BizHubPOS.exe is missing (run with -Step app first)" }

$out = 'build\installer'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$zip = "$out\BizHub-POS-$name-windows.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$release\*" -DestinationPath $zip
Write-Host "* $zip"

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) {
  & $iscc "/DAppVersion=$name" 'windows\installer.iss'
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }
  $signed = (Invoke-Sign "$out\BizHub-POS-Setup-$name.exe") -or $signed
  Write-Host ''
  Write-Host "OK  $out\BizHub-POS-Setup-$name.exe  (version $version)"
} else {
  Write-Host ''
  Write-Host "OK  $zip  (version $version)"
  Write-Host '    For the "Next > Install" setup file, install Inno Setup 6 (winget install JRSoftware.InnoSetup) and run this again.'
}
if (-not $signed -and -not $env:SIGNED_IN_CI) {
  Write-Host '    Not signed: Windows SmartScreen shows "More info > Run anyway" the first time. A code-signing certificate removes that.'
}
