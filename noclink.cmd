@echo off

if "%~1" == "/?" goto help
if "%~1" == "-?" goto help
if /i "%~1" == "/h" goto help
if /i "%~1" == "-h" goto help
if /i "%~1" == "/help" goto help
if /i "%~1" == "-help" goto help
if /i "%~1" == "--help" goto help

if /i "%~1" == "prompt" (set NOCLINK_DISABLE_PROMPT_FILTERS=&goto end)
if /i "%~1" == "noprompt" (set NOCLINK_DISABLE_PROMPT_FILTERS=1&goto end)

@setlocal
set CLINK_NOAUTORUN=1
echo.
echo Starting a nested CMD.exe without Clink.
echo Use "exit" when finished.
echo.
cmd.exe /k
goto end

:help
echo Usage:
echo.
echo   noclink               Start a nested CMD.exe without Clink
echo   noclink noprompt      Disable Clink prompt filtering
echo   noclink prompt        Re-enable Clink prompt filtering
echo   noclink -?            Show this help
echo.
echo The 'noprompt' and 'prompt' options require that noclink.lua is loaded.
goto end

:end
