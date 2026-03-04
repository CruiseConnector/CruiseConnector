@echo off
set "CONFIG_FILE=%USERPROFILE%\.config\configstore\firebase-tools.json"
echo Delete config file: %CONFIG_FILE%
if exist "%CONFIG_FILE%" del /F /Q "%CONFIG_FILE%"
echo Done.
