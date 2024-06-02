# Clink Gizmos

This is a collection of Lua scripts for use with [Clink](https://github.com/chrisant996/clink).

> [!NOTE]
> This includes [clink-fzf](https://github.com/chrisant996/clink-fzf), so you don't need both -- clink-gizmos contains a collection of scripts, and clink-fzf contains a single script.

## How To Install

The easiest way to install it for use with your Clink is:

1. Make sure you have [git](https://www.git-scm.com/downloads) installed.
2. Clone this repo into a local directory via <code>git clone https://github.com/chrisant996/clink-gizmos <em>local_directory</em></code>.
3. Tell Clink to load scripts from the repo via <code>clink installscripts <em>local_directory</em></code>.
4. Start a new session of Clink.

Get updates using `git pull` and normal git workflow.

## Files and Directories

The repo's root directory contains various useful scripts which are loaded when Clink is started.  They are discussed in the next section.

The "modules" subdirectory contains helper scripts that are used by the scripts in the other directories.

> [!NOTE]
> All completion scripts have moved to the [clink-completions](https://github.com/vladimir-kotikov/clink-completions) repo.

# Features

Each script file contains usage information in comments at the top of the script file.

Script Name | Description
-|-
[auto_argmatcher.lua](auto_argmatcher.lua) | Reads a config file and automatically creates argmatchers (completion generators) for specified programs by parsing their help text output.  Refer to the usage information in the script file for details.
[autopull.lua](autopull.lua) | Periodically runs `git pull` in a configurable list of directories.  Refer to the usage information in the script file for details.
[cwdhistory.lua](cwdhistory.lua) | Adds cwd history that is saved between sessions.  Use Alt-Ctrl-PgUp to show the cwd history popup list.  Refer to the usage information in the script file for details.
[divider.lua](divider.lua) | Automatically prints a divider line before and after running certain commands.  The list of commands is configurable.  Refer to the usage information in the script file for details.
[fuzzy_history.lua](fuzzy_history.lua) | Adds an autosuggest strategy `fuzzy_history` which can ignore path or file extension when providing suggestions from the command history list.  Refer to the usage information in the script file for details.
[fzf.lua](fzf.lua) | Adds support for using [fzf](https://github.com/junegunn/fzf) with Clink.  Refer to the usage information in the script file for how to activate key bindings.  (This is the script from the [clink-fzf](https://github.com/chrisant996/clink-fzf) repo.)
[history_labels.lua](history_labels.lua) | Can automatically switch to a different history file based on the current directory.  Refer to the usage information in the script file for how to configure directories and history files.
[i.lua](i.lua) | Adds an `i {dir} {command}` command that changes to _{dir}_, runs _{command}_, and changes back to the original directory.  Refer to the usage information in the script file for details and other features.
[luaexec.lua](luaexec.lua) | Some handy debugging aids to use with Clink Lua scripts.  Refer to the usage information in the script file for details.
[matchicons.lua](matchicons.lua) | Can show nerd font icons in file and directory completions.  Run `clink set matchicons.enable true` to enable it.  Refer to the usage information in the script file for details.
[noclink.lua](noclink.lua) | This and the [noclink.cmd](noclink.cmd) script let you temporarily disable/reenable Clink (or Clink's prompt filtering).  Run `noclink -?` for help.
[show_tips.lua](show_tips.lua) | Shows a tip about Clink each time Clink is injected.
[tilde_autoexpand.lua](tilde_autoexpand.lua) | Automatically expands tildes into the user's home directory (disabled by default; see usage information in the script file for how to enable it).
[toggle_short.lua](toggle_short.lua) | Adds a command to toggle the word under the cursor between long and short path names.  The default key binding is Ctrl-Alt-A.
[vscode_shell_integration.lua](vscode_shell_integration.lua) | Automatically enables shell integration for VSCode embedded terminal windows.
[z_dir_popup.lua](z_dir_popup.lua) | If you use [z.lua](https://github.com/skywind3000/z.lua) then this provides a popup listing of directories from z.  See usage information in the script file for details.

# Setting up FZF

Clink-gizmos includes clink-fzf, which provides optional integration with the [FZF](https://github.com/junegunn/fzf) fuzzy finder tool for filtering completions, directories, history, etc.

To set up FZF integration, refer to the README at [clink-fzf](https://github.com/chrisant996/clink-fzf).

You can also include file icons in fzf completion lists, if you use Clink v1.6.5 or newer and [DirX](https://github.com/chrisant996/dirx) v0.9 or newer and configure a few FZF environment variables.  See [Icons in FZF](https://github.com/chrisant996/clink-fzf/#icons-in-fzf) for details.

<a name="matchicons"></a>

# Setting up Icons in File Completions

If you're using a [Nerd Font](https://nerdfonts.com), then you can run `clink set matchicons.enable true` to enable showing file icons for file and directory completions.  And some other kinds of completions may also add icons (for example the git completions in [clink-completions](https://github.com/vladimir-kotikov/clink-completions) can show icons for git branches and git tags, etc).

If you're not using a Nerd Font yet, consider checking out some of the available fonts.  Here are a few recommended ones for shell windows or file editors:
- [Meslo Nerd Font patched by romkatv](https://github.com/romkatv/powerlevel10k/blob/master/font.md):  this is a patched version of Meslo Nerd Font.
- [Caskaydia Cove Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/):  this is a patched version of Cascadia Code that adds many icon characters.
- [FiraCode Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/):  this is a patched version of Fira Code that adds Powerline symbols and many icon characters.
- [RobotoMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/):  this is a patched version of Roboto Mono that adds Powerline symbols and many icon characters.
- And there are many other fonts to have fun with -- enjoy!

> [!TIP]
> If some of the icons look wrong, you might be using an older "v2" nerd font.  In that case, you can set the environment variable `DIRX_NERD_FONTS_VERSION=2` to tell matchicons.lua to use icons compatible with "v2" nerd fonts.
>
> For example by adding `set DIRX_NERD_FONTS_VERSION=2` into a startup .bat or .cmd script, or using Windows Settings to set the environment variable.

# Rough Prototype Features

Some of the included scripts are rough prototypes that can be useful, but are not fully functional and/or have potentially significant or dangerous limitations.  These prototype scripts are **disabled by default**, for safety and to avoid interference.  See below for information about each, and for how to enable each script if you wish.

## [fishcomplete.lua](fishcomplete.lua)

_Disabled by default.  To enable it, run `clink set fishcomplete.enable true`._

When a command is typed and it does not have an argmatcher, then fishcomplete automatically checks if there is a .fish file by the same name in the same
directory as the command program or in an "autocomplete" or "complete" directory below that.  If yes, then it attempts to parse the .fish file and create a Clink argmatcher from it.

You can configure an additional directory containing *.fish completion files by running `clink set fishcomplete.completions_dir` with a directory name.
This directory is searched last, if a .fish script isn't found by the default search strategy.

The following Clink settings control how this script functions:

Setting | Default | Description
-|-|-
`fishcomplete.enable` | `false` | This script is disabled by default.  Run `clink set fishcomplete.enable true` to enable this script.
`fishcomplete.banner` | `true` | By default fishcomplete shows feedback at the top of screen when loading *.fish completion files.  Run `clink set fishcomplete.banner false` to disable the feedback.
`fishcomplete.completions_dir` | none | An additional directory to search for *.fish completion files.  Run `clink set fishcomplete.completions_dir` to configure it.

> [!NOTE]
> The fishcomplete script does not yet handle the `-e` or `-w` flags for the fish `complete` command.  It attempts to handle simple fish completion scripts, but it will likely malfunction with more sophisticated fish completion scripts.
> It cannot handle the fish scripting language, apart from the "complete" command itself.

## [command_substitution.lua](command_substitution.lua)

_Disabled by default.  To enable it, set the global variable `clink_gizmos_command_substitution = true` in one of your Lua scripts that gets loaded before the clink-gizmos directory._

This simulates very simplistic command substitutions similar to bash.  Any `$(command)` in a command line is replaced by the output from running the specified command.

For example, `echo $(date /t & time /t)` first runs the command `date /t & time /t` and replaces the `$(...)` with the output from the command.  Since the output is the current date and the current time, after command substitution the command line becomes something like `echo Sat 07/09/2022  11:08 PM`, and then finally the resulting command is executed.

The following global configuration variables in Lua control how this script functions:

Variable | Value | Description
-|-|-
`clink_gizmos_command_substitution` | `true` or `false` | Set this global variable to true to enable this script.  This script is disabled by default.

> [!CAUTION]
> This is a very simple and stupid implementation, and it does not (and cannot) work the same as bash.  It will not work quite as expected in many cases.  But if the limitations are understood and respected, then it can still be useful and powerful.

Here are some of the limitations:

- WHETHER a command substitution runs is different than in bash!
- The ORDER in which command substitutions run is different than in bash!
- Only a small subset of the bash syntax is supported.
- Nested substitutions are not supported; neither nested via typing nor nested via substitution.
- This spawns new cmd shells to invoke commands.  This means commands cannot affect the current shell's state:  changing env vars or cwd or etc do not affect the current shell.
- Newlines and tab characters in the output are replaced with spaces before substitution into the command line.
- CMD does not support command lines longer than a total length of about 8,000 characters.

Bash intelligently skips command substitutions that don't need to be performed, for example in an `else` clause that is not reached.  But this script stupidly ALWAYS performs ALL command substitutions no matter whether CMD will actually reach processing that part of the command line.

Bash intelligently performs command substitutions in the correct order with respect to other parts of the command line that precede or follow the command substitutions.  But this script stupidly performs ALL command substitutions BEFORE any other processing happens.  That means command substitutions can't successfully refer to or use outputs from earlier parts of the command line; because this script does not understand the rest of the command line and doesn't evaluate things in the right order.
