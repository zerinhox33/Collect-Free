@echo off
:: Verifica se está rodando como administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permissao de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Executa o script PowerShell na mesma pasta do .bat
powershell -ExecutionPolicy Bypass -NoExit -File "%~dp0Collect_Free.ps1"
