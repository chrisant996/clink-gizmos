@echo off

rem     Depends on:
rem     - https://hpjansson.org/chafa
rem     - https://github.com/sharkdp/bat


rem     IMPORTANT NOTE:
rem
rem     If you want to customize this script, first copy it to another file
rem     name, so that your changes don't get overwritten when updating the
rem     clink-fzf or clink-gizmos scripts.


rem -- Try to preview as an image.
2>nul chafa "%~1"

rem -- Try to preview as a text file.
if errorlevel 1 (
bat --force-colorization --style=numbers,changes --line-range=:500 "%~1"
)
