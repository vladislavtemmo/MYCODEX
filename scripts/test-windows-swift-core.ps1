$ErrorActionPreference="Stop"
$sdk=(Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$root=Split-Path -Parent $sdk
$core=Join-Path $root "openvpn3"
$vcpkg=Join-Path $root "vcpkg"
$probe=Join-Path $sdk "tools\windows-swift-core-probe"
$build=Join-Path $root "build-mycode-swift-core-probe"
$moduleDir=Join-Path $probe "COpenVPNBridge"
$swiftc=Join-Path $env:LOCALAPPDATA "Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin\swiftc.exe"
$vs="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
if(!(Test-Path $swiftc) -or !(Test-Path "$core\client\ovpncli.cpp") -or !(Test-Path "$vcpkg\vcpkg.exe")){throw "Отсутствуют Swift, OpenVPN 3 Core или vcpkg"}
$actual=(git -C $core rev-parse HEAD).Trim()
$locked=((Get-Content (Join-Path $sdk "Dependencies\openvpn3.lock") | Where-Object {$_ -match "^revision="} | Select-Object -First 1) -replace "^revision=","").Trim()
if($LASTEXITCODE -ne 0 -or $actual -ne $locked){throw "Ревизия OpenVPN 3 Core не соответствует lock-файлу"}
if(!(Get-Command link.exe -ErrorAction SilentlyContinue)){if(!(Test-Path $vs)){throw "Visual Studio 2022 не найдена"}; $settings=& $env:ComSpec /d /c ("call `"$vs`" -arch=amd64 -host_arch=amd64 >nul && set"); if($LASTEXITCODE -ne 0){throw "Ошибка окружения MSVC"}; foreach($line in $settings){if($line -match "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$"){[Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],"Process")}}}
if(!(Get-Command link.exe -ErrorAction SilentlyContinue)){throw "Компоновщик MSVC не найден"}
if(!$env:SDKROOT -or !(Test-Path $env:SDKROOT)){$env:SDKROOT=Join-Path $env:LOCALAPPDATA "Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk"}
if(!(Test-Path $env:SDKROOT)){throw "Swift Windows.sdk не найден"}
$env:VCPKG_ROOT=$vcpkg
$env:PATH=(Split-Path $swiftc -Parent)+";"+$env:PATH
$header=Join-Path $sdk "Sources\COpenVPNBridge\include\MYCODEXBridge.h"
$snapshot=Join-Path $moduleDir "MYCODEXBridge.h"
if(!(Test-Path $snapshot) -or (Get-FileHash $header).Hash -ne (Get-FileHash $snapshot).Hash){throw "Заголовок теста отличается от основного C ABI; требуется синхронизация"}
Write-Host "=== CONFIGURE REAL OPENVPN 3 CORE ===" -ForegroundColor Cyan
cmake -S $probe -B $build -G "Visual Studio 17 2022" -A x64 "-DOPENVPN3_ROOT=$core" "-DMYCODEX_SDK_ROOT=$sdk" "-DCMAKE_TOOLCHAIN_FILE=$vcpkg/scripts/buildsystems/vcpkg.cmake" "-DVCPKG_MANIFEST_DIR=$core/deps/vcpkg_manifests/windows" "-DVCPKG_OVERLAY_TRIPLETS=$core/deps/vcpkg-triplets" "-DVCPKG_OVERLAY_PORTS=$core/deps/vcpkg-ports" -DVCPKG_HOST_TRIPLET=x64-windows
if($LASTEXITCODE -ne 0){throw "CMake configure failed"}
Write-Host "=== BUILD REAL OPENVPN 3 DLL ===" -ForegroundColor Cyan
cmake --build $build --config Release --target mycodex_core --parallel 2
if($LASTEXITCODE -ne 0){throw "C++ build failed"}
$release=Join-Path $build "Release"
if(!(Test-Path (Join-Path $release "mycodex_core.dll")) -or !(Test-Path (Join-Path $release "mycodex_core.lib"))){throw "Нативная DLL или import library отсутствует"}
Write-Host "=== COMPILE SWIFT INTEGRATION TEST ===" -ForegroundColor Cyan
$exe=Join-Path $release "mycodex_swift_probe.exe"
& $swiftc -I $moduleDir -L $release -lmycodex_core -o $exe (Join-Path $sdk "Sources\MYCODEX\OpenVPNProfile.swift") (Join-Path $sdk "Sources\MYCODEX\OpenVPNNativeBridge.swift") (Join-Path $sdk "Sources\MYCODEX\OpenVPNProfileValidation.swift") (Join-Path $probe "main.swift")
if($LASTEXITCODE -ne 0){throw "Swift integration build failed"}
$env:PATH=$release+";"+(Join-Path $build "vcpkg_installed\x64-windows\bin")+";"+$env:PATH
Write-Host "=== RUN SWIFT TO REAL OPENVPN 3 ===" -ForegroundColor Cyan
& $exe
if($LASTEXITCODE -ne 0){throw "Интеграционный тест не пройден"}
Write-Host "=== MYCODEX WINDOWS INTEGRATION PASSED ===" -ForegroundColor Green
