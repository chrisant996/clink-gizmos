# Clink Gizmos

This is a collection of Lua scripts for use with [Clink](https://github.com/chrisant996/clink).

## How To Install

The easiest way to install it for use with your Clink is:

1. Make sure you have [git](https://www.git-scm.com/downloads) installed.
2. Clone this repo into a local directory via `git clone https://github.com/chrisant996/clink-gizmos local_directory`.
3. Tell Clink to load scripts from the repo via `clink installscripts local_directory`.
4. Start a new session of Clink.

## Repo's root directory

The repo's root directory contains various useful scripts.

> Note: For information about each script, refer to the comments at the top of each script file.

- auto_argmatcher.lua _(TBD)_
- divider.lua _(TBD)_
- fzf.lua _(TBD)_
- i.lua _(TBD)_
- luaexec.lua _(TBD)_
- msbuild.lua _(TBD)_
- z_dir_popup.lua _(TBD)_

## Completions

The completions subdirectory contains completion scripts for various commands:

- `attrib`
- `curl`
- `doskey`
- `findstr`
- [`less`](http://www.greenwoodsoftware.com/less/)
- [`premake5`](https://premake.github.io/)
- `robocopy`
- `xcopy`

## Modules

The modules subdirectory contains helper scripts that are used by the scripts in the other directories.

## Rough

The rough subdirectory contains rough prototype scripts that can be useful, but are known to be incomplete and/or have potentially significant or dangerous limitations.

Read the comments at the top of each script carefully before even considering whether to use them.
