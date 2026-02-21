@echo off
setlocal

if "%~1" == "branches" goto :branches
if "%~1" == "eachref" goto :eachref
if "%~1" == "edit_file" goto :edit_file
if "%~1" == "edit_git_show" goto :edit_git_show
if "%~1" == "edit_tree_file" goto :edit_tree_file
if "%~1" == "extract_file_name" goto :extract_file_name
if "%~1" == "files" goto :files
if "%~1" == "hashes" goto :hashes
if "%~1" == "hashes_preview" goto :hashes_preview
if "%~1" == "list_file" goto :list_file
if "%~1" == "load_hashes" goto :load_hashes
if "%~1" == "load_all_hashes" goto :load_all_hashes
if "%~1" == "remotes" goto :remotes
if "%~1" == "tree_files" goto :tree_files
if "%~1" == "worktree" goto :worktree
echo Unrecognized command '%~1'.
goto :eof



:branches
set ARG=%~2
for /f "tokens=1 delims= " %%a in ("%ARG:~2%") do set ARG=%%a
git log --oneline --graph --date=short --color=%__fzf_git_color_% --pretty="format:%%C(auto)%%cd %%h%%d %%s" %ARG% --
goto :eof

:eachref
set ARG=%~2
git log --oneline --graph --date=short --color=%__fzf_git_color_% --pretty="format:%%C(auto)%%cd %%h%%d %%s" %ARG% --
goto :eof

:edit_file
set ARG=%~2
set ARG=%ARG:"=%
call :__extract_file_name "%~0" "%ARG%"
goto :common_edit_file

:edit_git_show
set ARG_COMMIT=%~2
set ARG_COMMIT=%ARG_COMMIT:"=%
set ARG=%TEMP%\fzf_rg_git_show.tmp
git show %ARG_COMMIT% > "%ARG%"
goto :common_edit_file

:edit_tree_file
set ARG=%~2
:common_edit_file
rem -- Using start works around several problems with fzf on Windows:
rem    Otherwise the next character of input gets eaten, terminal based
rem    editors don't work because fzf still has input redirected, fzf
rem    freezes while waiting for GUI programs to exit, etc.
start "Editor" %__fzf_git_editor% "%ARG%"
goto :eof

:extract_file_name
echo "%~2"|cut -c5- | sed "s/.* -> //;s/^\x22//;s/\x22$//;s/\x5c\x22/\x22/g"
goto :eof

:files
set ARG=%~2
set ARG=%ARG:"=%
call :__extract_file_name "%~0" "%ARG%"
rem -- First print the diff, if any.
    rem -- TODO: why would the following be piped into `$(__fzf_git_pager)`?
git -c core.quotePath=false diff --no-ext-diff --color=%__fzf_git_color_% --exit-code -- "%ARG%"
rem -- If a diff was printed, also print a separator line.
if errorlevel 1 echo --------------------------------------------------------------------------------
rem -- Print the whole file.
%__fzf_git_cat% "%ARG:/=\%"
goto :eof

:hashes
set ARG=%~2
for /f "tokens=1 delims= " %%a in ("%ARG:~2%") do set ARG=%%a
endlocal & set LIST_OPTS=%ARG%
goto :eof

:hashes_preview
if "%~2" == "-" goto :eof
git show --color=%__fzf_git_color_% "%~2" --
goto :eof

:list_file
set ARG=%~2
set ARG=%ARG:"=%
call :__extract_file_name "%~0" "%ARG%"
bash "%__fzf_git_sh%" --list file "%ARG%"
goto :eof

:load_hashes
echo CTRL-O (open in browser) ╱ CTRL-D (diff) ╱ CTRL-S (toggle sort)
echo ALT-R (toggle raw mode) ╱ ALT-F (list files) ╱ ALT-A (show all hashes)
git log --date=short --format="%%C(green)%%C(bold)%%cd !%%C(auto)%%h!%%C(auto)%%d %%s (%%an)" --graph --color=%__fzf_git_color% %~2 | sed "s/\(.*\) !\([^!]\{7,\}\)!\(.*\)/\2 \1\3/" | sed "/[0-9][0-9][0-9][0-9]/!s/^/%__fzf_git_indent%/"
goto :eof

:load_all_hashes
echo CTRL-O (open in browser) ╱ CTRL-D (diff)
echo CTRL-S (toggle sort) ╱ ALT-F (list files)
git log --date=short --format="%%C(green)%%C(bold)%%cd !%%C(auto)%%h!%%C(auto)%%d %%s (%%an)" --graph --color=%__fzf_git_color% --all | sed "s/\(.*\) !\([^!]\{7,\}\)!\(.*\)/\2 \1\3/" | sed "/[0-9][0-9][0-9][0-9]/!s/^/%__fzf_git_indent%/"
goto :eof

:remotes
set ARG=%~2
for /f %%a in ('git rev-parse --abbrev-ref HEAD') do set REVPARSED=%%a
git log --oneline --graph --date=short --color=%__fzf_git_color_% --pretty="format:%%C(auto)%%cd %%h%%d %%s" "%ARG%/%REVPARSED%" --
goto :eof

:tree_files
set ARG=%~2
%__fzf_git_cat% "%ARG:/=\%"
goto :eof

:worktree
git -c color.status=%__fzf_git_color_% -C "%~2" status --short --branch
echo.
git log --oneline --graph --date=short --color=%__fzf_git_color_% --pretty="format:%%C(auto)%%cd %%h%%d %%s" "%~3" --
goto :eof



:__extract_file_name
for /f "tokens=1 delims= " %%a in ('call "%~1" extract_file_name "%~2"') do set ARG=%%a
goto :eof
