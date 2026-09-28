@echo off
setlocal
title Studium SI - Gerar APK
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 goto :sem_flutter
if not defined MRA_KEYSTORE_FILE goto :sem_assinatura
if not exist "%MRA_KEYSTORE_FILE%" goto :sem_assinatura
if not defined MRA_KEYSTORE_PASSWORD goto :sem_assinatura
if not defined MRA_KEY_ALIAS goto :sem_assinatura
if not defined MRA_KEY_PASSWORD goto :sem_assinatura
flutter pub get
if errorlevel 1 goto :erro
flutter build apk --release
if errorlevel 1 goto :erro

if not exist "ENTREGAS" mkdir "ENTREGAS"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "ENTREGAS\Studium-SI.apk" >nul
echo.
echo APK criado em:
echo %CD%\ENTREGAS\Studium-SI.apk
explorer "%CD%\ENTREGAS"
pause
exit /b 0

:sem_flutter
echo ERRO: Flutter nao foi encontrado. Execute 01_PREPARAR_PROJETO.bat.
pause
exit /b 1

:sem_assinatura
echo ERRO: configure MRA_KEYSTORE_FILE e os tres dados da chave Android
echo com a MESMA assinatura do APK ja instalado. Sem isso, use o GitHub
echo Actions depois de configurar os quatro Secrets MRA_*.
echo Nao desinstale o aplicativo para trocar a assinatura.
pause
exit /b 1

:erro
echo.
echo Nao foi possivel gerar o APK. Confira a mensagem acima.
pause
exit /b 1
