# Build BizHub POS for Windows (production settings) and make the installer.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1
#     -> build\installer\BizHub-POS-Setup-<version>.exe   (when Inno Setup 6 is installed)
#     -> build\installer\BizHub-POS-<version>-windows.zip (always: the app folder, for a quick copy)
#
# Needs, on a Windows PC: Flutter, Visual Studio 2022 with "Desktop development with C++", env.prod.json
# (production API), and for the installer Inno Setup 6 (winget install JRSoftware.InnoSetup).
# Only the windows\ desktop app is built here; the Android / iPhone apps are not touched.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path windows)) { throw 'The windows\ folder is missing.' }
if (-not (Test-Path env.prod.json)) { throw 'env.prod.json is missing (production settings).' }
if (-not (Select-String -Path env.prod.json -Pattern '"API_HOST":\s*"https://bizhub-api-eight-production.vercel.app"' -Quiet)) {
  throw 'env.prod.json does not point at the production API.'
}

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value).Trim()
$name = $version.Split('+')[0]
Write-Host "* building BizHub POS $version for Windows (production)..."
flutter build windows --release --dart-define-from-file=env.prod.json
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }

$release = 'build\windows\x64\runner\Release'
if (-not (Test-Path "$release\BizHubPOS.exe")) { throw "build finished but $release\BizHubPOS.exe is missing" }

# The Visual C++ runtime goes next to the app, so it also opens on PCs that never installed it
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $env:WINDIR "System32\$dll"
  if (Test-Path $src) { Copy-Item $src $release -Force } else { Write-Warning "$dll not found in System32 (install the VC++ 2015-2022 x64 redistributable)" }
}

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
  Write-Host ''
  Write-Host "OK  $out\BizHub-POS-Setup-$name.exe  (version $version)"
} else {
  Write-Host ''
  Write-Host "OK  $zip  (version $version)"
  Write-Host '    For the "Next > Install" setup file, install Inno Setup 6 (winget install JRSoftware.InnoSetup) and run this again.'
}
Write-Host '    Not signed yet: Windows SmartScreen shows "More info > Run anyway" the first time. A code-signing certificate removes that.'
