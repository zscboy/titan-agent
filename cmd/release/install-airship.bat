@echo off
setlocal EnableDelayedExpansion

REM Define the SUPPLIER ID
set AIRSHIP_SUPPLIER_ID=106266

REM Define the URL for the Airship installation script
set AIRSHIP_RUNNER_URL=https://infra-iaas-1312767721.cos.ap-shanghai.myqcloud.com/box-tools/install-on-systemd.sh
set VM_NAME=ubuntu-airship
set PATH=%PATH%;C:\Program Files\Multipass\bin;C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0

call :main %*
goto :EOF

:: Function to check if Multipass is installed
:check_multipass
where multipass >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: Multipass is not installed.
    exit /b 1
)
multipass --version
exit /b 0

:: Function to create the VM
:create_vm
call :check_multipass
for /f "tokens=*" %%a in ('powershell get-date -format "yyMMddHHmmssff"') do set datetime=%%a
set AIRSHIP_SUPPLIER_DEVICE_ID=TNT%datetime%

echo Creating the virtual machine %VM_NAME%...
multipass launch --name %VM_NAME% --cpus 2 --memory 2G --disk 64G
if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to create VM %VM_NAME%.
    exit /b 1
)

echo Fetching the installation script...
multipass exec %VM_NAME% -- wget -q %AIRSHIP_RUNNER_URL% -O /tmp/install-on-systemd.sh

echo Setting execute permission on the script...
multipass exec %VM_NAME% -- sudo chmod +x /tmp/install-on-systemd.sh

echo Running Airship inside the VM...
multipass exec %VM_NAME% -- sudo DEVICE_CLASS=box DEVICE_SUPPLIER=%AIRSHIP_SUPPLIER_ID% DEVICE_SUPPLIER_DEVICE_ID=%AIRSHIP_SUPPLIER_DEVICE_ID% /tmp/install-on-systemd.sh install
if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to execute script inside the VM.
    exit /b 1
) else (
    echo The script has been executed successfully inside the VM.
)
exit /b 0

:info
for /f "tokens=*" %%i in ('multipass exec "%VM_NAME%" -- cat /opt/.airship/id') do set "BOX_ID=%%i"
if "!BOX_ID!"=="" (
    echo Error: BOX_ID is not found.
    exit /b 1
)
echo BOX_ID: !BOX_ID!
exit /b 0

:reinstall
multipass list | findstr "%VM_NAME%" >nul
if %ERRORLEVEL% equ 0 (
    echo Deleting existing %VM_NAME% VM...
    multipass delete "%VM_NAME%"
    multipass purge
)
echo Creating new VM...
call :create_vm
exit /b 0

:restart
echo Restarting service...
multipass restart "%VM_NAME%"
exit /b 0

:delete
echo Deleting service...
multipass delete "%VM_NAME%"
multipass purge
exit /b 0

:main
if "%1"=="" goto usage
if "%1"=="install" (
    call :create_vm
) else if "%1"=="info" (
    call :info
) else if "%1"=="reinstall" (
    call :reinstall
) else if "%1"=="restart" (
    call :restart
) else if "%1"=="delete" (
    call :delete
) else (
    goto usage
)
exit /b 0

:usage
echo Usage: %0 {install^|reinstall^|restart^|delete^|info}
exit /b 1