@echo off
rem -- This script lets you use the "web_search" command even from outside of
rem -- Clink or from batch scripts.  See the web_search.lua file for details.
call clink lua %~dp0web_search.lua %*
