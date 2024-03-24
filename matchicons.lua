-- This is a sample script that replaces the clink.dirmatches() and
-- clink.filematches() functions and adds "icons" for file and directory
-- matches.
--
-- This is disabled by default.
--  - You can enable icons by running `clink set matchicons.enable true`
--  - You can disable icons by running `clink set matchicons.enable false`
--
-- Other Lua scripts can use the following public function to add their own
-- icons to matches, but --WARNING!-- ONLY IF nothing calls clink.dirmatches(),
-- or clink.filematches(), clink.dirmatchesexact(), or clink.filematchesexact().
-- If any of those are used along with the following, then some matches will
-- end up with TWO icons.
--
-- This adds a "!" icon to the match in m, where m is a table in the format
-- expected by builder:addmatch().  If matchicons are disabled or the matchicons
-- script is not loaded, then it gracefully has no effect.
--
--      if matchicons and matchicons.addicontomatch then
--          matchicons.addicontomatch(m, "!", "93")
--      end
--
-- This adds icons to all file and directory type matches in the input table,
-- which must be in the format expect by builder:addmatches().  If matchicons
-- are disabled or the matchicons script is not loaded, then it gracefully has
-- no effect.
--
--      if matchicons and matchicons.addicons then
--          matchicons.addicons(matches)
--      end
--
-- This gets the icon for a file or directory match.
--
--      local icon = matchicons.geticon(match)
--
--------------------------------------------------------------------------------
-- WARNING:  This script makes clink.dirmatches() and clink.filematches()
-- behave slightly differently than how they're documented.  That can break
-- scripts, if they expect the functions to behave exactly how they're
-- documented.
--
-- OTHER CAVEATS:  This can be incompatible with completion scripts that
-- generate custom display strings themselves.
--------------------------------------------------------------------------------

if not settings.add then
    return
end

settings.add("matchicons.enable", false,
             "Enables icons in file completions",
             "Requires a Nerd Font; visit https://nerdfonts.com")

--luacheck: globals matchicons
matchicons = {}

local NERDFONTICONS =
{
    AUDIO               = "",
    BINARY              = "",
    BOOK                = "",
    CALENDAR            = "",
    CLOCK               = "",
    COMPRESSED          = "",
    CONFIG              = "",
    CSS3                = "",
    DATABASE            = "",
    DIFF                = "",
    DISK_IMAGE          = "",
    DOCKER              = "",
    DOCUMENT            = "",
    DOWNLOAD            = "󰇚",
    EMACS               = "",
    ESLINT              = "",
    FILE                = "",
    FILE_OUTLINE        = "",
    FOLDER              = "",
    FOLDER_CONFIG       = "",
    FOLDER_GIT          = "",
    FOLDER_GITHUB       = "",
    FOLDER_HIDDEN       = "󱞞",
    FOLDER_KEY          = "󰢬",
    FOLDER_NPM          = "",
    FOLDER_OPEN         = "",
    FONT                = "",
    GIST_SECRET         = "",
    GIT                 = "",
    GRADLE              = "",
    GRUNT               = "",
    GULP                = "",
    HTML5               = "",
    IMAGE               = "",
    INTELLIJ            = "",
    JSON                = "",
    KEY                 = "",
    KEYPASS             = "",
    LANG_ASSEMBLY       = "",
    LANG_C              = "",
    LANG_CPP            = "",
    LANG_CSHARP         = "󰌛",
    LANG_D              = "",
    LANG_ELIXIR         = "",
    LANG_FORTRAN        = "󱈚",
    LANG_FSHARP         = "",
    LANG_GO             = "",
    LANG_GROOVY         = "",
    LANG_HASKELL        = "",
    LANG_JAVA           = "",
    LANG_JAVASCRIPT     = "",
    LANG_KOTLIN         = "",
    LANG_OCAML          = "",
    LANG_PERL           = "",
    LANG_PHP            = "",
    LANG_PYTHON         = "",
    LANG_R              = "",
    LANG_RUBY           = "",
    LANG_RUBYRAILS      = "",
    LANG_RUST           = "",
    LANG_SASS           = "",
    LANG_STYLUS         = "",
    LANG_TEX            = "",
    LANG_TYPESCRIPT     = "",
    LANG_V              = "",
    LIBRARY             = "",
    LICENSE             = "",
    LOCK                = "",
    MAKE                = "",
    MARKDOWN            = "",
    MUSTACHE            = "",
    NODEJS              = "",
    NPM                 = "",
    OS_ANDROID          = "",
    OS_APPLE            = "",
    OS_LINUX            = "",
    OS_WINDOWS          = "",
    OS_WINDOWS_CMD      = "",
    PLAYLIST            = "󰲹",
    POWERSHELL          = "",
    PRIVATE_KEY         = "󰌆",
    PUBLIC_KEY          = "󰷖",
    RAZOR               = "",
    REACT               = "",
    README              = "󰂺",
    SHEET               = "",
    SHELL               = "󱆃",
    SHELL_CMD           = "",
    SHIELD_CHECK        = "󰕥",
    SHIELD_KEY          = "󰯄",
    SHIELD_LOCK         = "󰦝",
    SIGNED_FILE         = "󱧃",
    SLIDE               = "",
    SUBLIME             = "",
    SUBTITLE            = "󰨖",
    TERRAFORM           = "󱁢",
    TEXT                = "",
    TYPST               = "𝐭",
    UNITY               = "",
    VECTOR              = "󰕙",
    VIDEO               = "",
    VIM                 = "",
    WRENCH              = "",
    XML                 = "󰗀",
    YAML                = "",
    YARN                = "",

    -- Directories.
    FOLDER_TRASH        = "",
    FOLDER_CONTACTS     = "",
    FOLDER_DESKTOP      = "",
    FOLDER_DOWNLOADS    = "󰉍",
    FOLDER_FAVORITES    = "󰚝",
    FOLDER_HOME         = "󱂵",
    FOLDER_MAIL         = "󰇰",
    FOLDER_MOVIES       = "󰿎",
    FOLDER_MUSIC        = "󱍙",
    FOLDER_PICTURES     = "󰉏",
    FOLDER_VIDEO        = "",

    -- Filenames.
    ATOM                = "",
    GITLAB              = "",
    SSH                 = "󰣀",
    EARTHFILE           = "",
    HEROKU              = "",
    JENKINS             = "",
    PKGBUILD            = "",
    MAVEN               = "",
    PROCFILE            = "",
    ROBOTS              = "󰚩",
    VAGRANT             = "⍱",
    WEBPACK             = "󰜫",

    -- Extensions.
    ACF                 = "",
    AI                  = "",
    CLJ                 = "",
    CLJS                = "",
    COFFEE              = "",
    CR                  = "",
    CU                  = "",
    DART                = "",
    DEB                 = "",
    DESKTOP             = "",
    DRAWIO              = "",
    EBUILD              = "",
    EJS                 = "",
    ELM                 = "",
    EML                 = "",
    ENV                 = "",
    ERL                 = "",
    GFORM               = "",
    GV                  = "󱁉",
    HAML                = "",
    IPYNB               = "",
    JL                  = "",
    LESS                = "",
    LISP                = "󰅲",
    LOG                 = "",
    LUA                 = "",
    MAGNET              = "",
    MID                 = "󰣲",
    NINJA               = "󰝴",
    NIX                 = "",
    ORG                 = "",
    OUT_EXT             = "",
    PDF                 = "",
    PKG                 = "",
    PP                  = "",
    PSD                 = "",
    PURS                = "",
    RDB                 = "",
    RPM                 = "",
    RSS                 = "",
    SCALA               = "",
    SERVICE             = "",
    SLN                 = "",
    SQLITE3             = "",
    SVELTE              = "",
    SWIFT               = "",
    TORRENT             = "",
    TWIG                = "",
    VUE                 = "󰡄",
    ZIG                 = "",

    -- More.
    INFO                = "",
    HISTORY             = "",
    PDB                 = "",
    OS_WINDOWS_EXE      = "",
    FOLDER_LINK         = "",
    FILE_LINK           = "",
}

local ____ = ""

local NERDFONTICONSv2 =
{
    BINARY              = "",
    CALENDAR            = "",
    DOCKER              = "",
    DOWNLOAD            = "",
    EMACS               = ____,
    ESLINT              = ____,
    FOLDER_HIDDEN       = ____,
    FOLDER_KEY          = ____,
    GIST_SECRET         = ____,
    GRADLE              = ____,
    KEY                 = "",
    LANG_ASSEMBLY       = ____,
    LANG_CSHARP         = "",
    LANG_FORTRAN        = ____,
    LANG_GO             = ____,
    LANG_KOTLIN         = ____,
    LANG_OCAML          = ____,
    LANG_PERL           = ____,
    LANG_R              = "ﳒ",
    LANG_RUST           = "",
    LANG_TEX            = ____,
    LANG_V              = ____,
    LIBRARY             = "",
    MAKE                = ____,
    OS_WINDOWS_CMD      = "",
    PLAYLIST            = ____,
    POWERSHELL          = "",
    PRIVATE_KEY         = "",
    PUBLIC_KEY          = "",
    README              = "",
    SHELL               = "#",
    SHIELD_CHECK        = ____,
    SHIELD_KEY          = ____,
    SHIELD_LOCK         = ____,
    SIGNED_FILE         = ____,
    SUBTITLE            = ____,
    TERRAFORM           = ____,
    VECTOR              = "縉",
    XML                 = "",
    YAML                = "!",
    YARN                = ____,

    -- Directories.
    FOLDER_DOWNLOADS    = "",
    FOLDER_FAVORITES    = "ﮛ",
    FOLDER_HOME         = "",
    FOLDER_MAIL         = "",
    FOLDER_MOVIES       = "",
    FOLDER_MUSIC        = "",
    FOLDER_PICTURES     = "",

    -- Filenames.
    SSH                 = ____,
    JENKINS             = ____,
    MAVEN               = ____,
    ROBOTS              = "ﮧ",
    WEBPACK             = "ﰩ",

    -- Extensions.
    CR                  = ____,
    CU                  = ____,
    DESKTOP             = ____,
    DRAWIO              = ____,
    GV                  = ____,
    HAML                = ____,
    IPYNB               = ____,
    LISP                = "",
    MID                 = ____,
    NINJA               = "ﱲ",
    ORG                 = ____,
    OUT_EXT             = ____,
    PKG                 = "",
    PP                  = ____,
    PURS                = ____,
    SERVICE             = ____,
    SVELTE              = ____,
    VUE                 = "﵂",
    ZIG                 = ____,

    -- More.
    HISTORY             = "",
    OS_WINDOWS_EXE      = "ﬓ",
}

local nerd_fonts_version = 3
local spacing = " "

local function get_icon(icon_name)
    if nerd_fonts_version == 2 then
        local v2 = NERDFONTICONSv2[icon_name]
        if v2 == ____ then
            return
        elseif v2 then
            return v2
        end
    end
    return NERDFONTICONS[icon_name]
end

local DIR_ICONS =
{
    [".config"]                         = "FOLDER_CONFIG",
    [".git"]                            = "FOLDER_GIT",
    [".github"]                         = "FOLDER_GITHUB",
    [".npm"]                            = "FOLDER_NPM",
    [".ssh"]                            = "FOLDER_KEY",
    [".Trash"]                          = "FOLDER_TRASH",
    ["config"]                          = "FOLDER_CONFIG",
    ["Contacts"]                        = "FOLDER_CONTACTS",
    ["cron.d"]                          = "FOLDER_CONFIG",
    ["cron.daily"]                      = "FOLDER_CONFIG",
    ["cron.hourly"]                     = "FOLDER_CONFIG",
    ["cron.monthly"]                    = "FOLDER_CONFIG",
    ["cron.weekly"]                     = "FOLDER_CONFIG",
    ["Desktop"]                         = "FOLDER_DESKTOP",
    ["Downloads"]                       = "FOLDER_DOWNLOADS",
    ["etc"]                             = "FOLDER_CONFIG",
    ["Favorites"]                       = "FOLDER_FAVORITES",
    ["hidden"]                          = "FOLDER_HIDDEN",
    ["home"]                            = "FOLDER_HOME",
    ["include"]                         = "FOLDER_CONFIG",
    ["Mail"]                            = "FOLDER_MAIL",
    ["Movies"]                          = "FOLDER_MOVIES",
    ["Music"]                           = "FOLDER_MUSIC",
    ["node_modules"]                    = "FOLDER_NPM",
    ["npm_cache"]                       = "FOLDER_NPM",
    ["pam.d"]                           = "FOLDER_KEY",
    ["Pictures"]                        = "FOLDER_PICTURES",
    ["ssh"]                             = "FOLDER_KEY",
    ["sudoers.d"]                       = "FOLDER_KEY",
    ["Videos"]                          = "FOLDER_VIDEO",
    ["xbps.d"]                          = "FOLDER_CONFIG",
    ["xorg.conf.d"]                     = "FOLDER_CONFIG",
}

local FILE_ICONS =
{
    [".atom"]                           = "ATOM",
    [".bashrc"]                         = "SHELL",
    [".bash_history"]                   = "SHELL",
    [".bash_logout"]                    = "SHELL",
    [".bash_profile"]                   = "SHELL",
    [".CFUserTextEncoding"]             = "OS_APPLE",
    [".clang-format"]                   = "CONFIG",
    [".cshrc"]                          = "SHELL",
    [".DS_Store"]                       = "OS_APPLE",
    [".emacs"]                          = "EMACS",
    [".eslintrc.cjs"]                   = "ESLINT",
    [".eslintrc.js"]                    = "ESLINT",
    [".eslintrc.json"]                  = "ESLINT",
    [".eslintrc.yaml"]                  = "ESLINT",
    [".eslintrc.yml"]                   = "ESLINT",
    [".gitattributes"]                  = "GIT",
    [".gitconfig"]                      = "GIT",
    [".gitignore"]                      = "GIT",
    [".gitignore_global"]               = "GIT",
    [".gitlab-ci.yml"]                  = "GITLAB",
    [".gitmodules"]                     = "GIT",
    [".htaccess"]                       = "CONFIG",
    [".htpasswd"]                       = "CONFIG",
    [".idea"]                           = "INTELLIJ",
    [".ideavimrc"]                      = "VIM",
    [".inputrc"]                        = "CONFIG",
    [".kshrc"]                          = "SHELL",
    [".login"]                          = "SHELL",
    [".logout"]                         = "SHELL",
    [".mailmap"]                        = "GIT",
    [".node_repl_history"]              = "NODEJS",
    [".npmignore"]                      = "NPM",
    [".npmrc"]                          = "NPM",
    [".profile"]                        = "SHELL",
    [".python_history"]                 = "LANG_PYTHON",
    [".rustfmt.toml"]                   = "LANG_RUST",
    [".rvm"]                            = "LANG_RUBY",
    [".rvmrc"]                          = "LANG_RUBY",
    [".tcshrc"]                         = "SHELL",
    [".viminfo"]                        = "VIM",
    [".vimrc"]                          = "VIM",
    [".Xauthority"]                     = "CONFIG",
    [".xinitrc"]                        = "CONFIG",
    [".Xresources"]                     = "CONFIG",
    [".yarnrc"]                         = "YARN",
    [".zlogin"]                         = "SHELL",
    [".zlogout"]                        = "SHELL",
    [".zprofile"]                       = "SHELL",
    [".zshenv"]                         = "SHELL",
    [".zshrc"]                          = "SHELL",
    [".zsh_history"]                    = "SHELL",
    [".zsh_sessions"]                   = "SHELL",
    ["._DS_Store"]                      = "OS_APPLE",
    ["a.out"]                           = "SHELL_CMD",
    ["authorized_keys"]                 = "SSH",
    ["bashrc"]                          = "SHELL",
    ["bspwmrc"]                         = "CONFIG",
    ["build.gradle.kts"]                = "GRADLE",
    ["Cargo.lock"]                      = "LANG_RUST",
    ["Cargo.toml"]                      = "LANG_RUST",
    ["CMakeLists.txt"]                  = "MAKE",
    ["composer.json"]                   = "LANG_PHP",
    ["composer.lock"]                   = "LANG_PHP",
    ["config"]                          = "CONFIG",
    ["config.status"]                   = "CONFIG",
    ["configure"]                       = "WRENCH",
    ["configure.ac"]                    = "CONFIG",
    ["configure.in"]                    = "CONFIG",
    ["constraints.txt"]                 = "LANG_PYTHON",
    ["COPYING"]                         = "LICENSE",
    ["COPYRIGHT"]                       = "LICENSE",
    ["crontab"]                         = "CONFIG",
    ["crypttab"]                        = "CONFIG",
    ["csh.cshrc"]                       = "SHELL",
    ["csh.login"]                       = "SHELL",
    ["csh.logout"]                      = "SHELL",
    ["docker-compose.yml"]              = "DOCKER",
    ["Dockerfile"]                      = "DOCKER",
    ["dune"]                            = "LANG_OCAML",
    ["dune-project"]                    = "WRENCH",
    ["Earthfile"]                       = "EARTHFILE",
    ["environment"]                     = "CONFIG",
    ["GNUmakefile"]                     = "MAKE",
    ["go.mod"]                          = "LANG_GO",
    ["go.sum"]                          = "LANG_GO",
    ["go.work"]                         = "LANG_GO",
    ["gradle"]                          = "GRADLE",
    ["gradle.properties"]               = "GRADLE",
    ["gradlew"]                         = "GRADLE",
    ["gradlew.bat"]                     = "GRADLE",
    ["group"]                           = "LOCK",
    ["gruntfile.coffee"]                = "GRUNT",
    ["gruntfile.js"]                    = "GRUNT",
    ["gruntfile.ls"]                    = "GRUNT",
    ["gshadow"]                         = "LOCK",
    ["gulpfile.coffee"]                 = "GULP",
    ["gulpfile.js"]                     = "GULP",
    ["gulpfile.ls"]                     = "GULP",
    ["heroku.yml"]                      = "HEROKU",
    ["hostname"]                        = "CONFIG",
    ["id_dsa"]                          = "PRIVATE_KEY",
    ["id_ecdsa"]                        = "PRIVATE_KEY",
    ["id_ecdsa_sk"]                     = "PRIVATE_KEY",
    ["id_ed25519"]                      = "PRIVATE_KEY",
    ["id_ed25519_sk"]                   = "PRIVATE_KEY",
    ["id_rsa"]                          = "PRIVATE_KEY",
    ["inputrc"]                         = "CONFIG",
    ["Jenkinsfile"]                     = "JENKINS",
    ["jsconfig.json"]                   = "LANG_JAVASCRIPT",
    ["Justfile"]                        = "WRENCH",
    ["known_hosts"]                     = "SSH",
    ["LICENCE"]                         = "LICENSE",
    ["LICENCE.md"]                      = "LICENSE",
    ["LICENCE.txt"]                     = "LICENSE",
    ["LICENSE"]                         = "LICENSE",
    ["LICENSE-APACHE"]                  = "LICENSE",
    ["LICENSE-MIT"]                     = "LICENSE",
    ["LICENSE.md"]                      = "LICENSE",
    ["LICENSE.txt"]                     = "LICENSE",
    ["localized"]                       = "OS_APPLE",
    ["localtime"]                       = "CLOCK",
    ["Makefile"]                        = "MAKE",
    ["makefile"]                        = "MAKE",
    ["Makefile.ac"]                     = "MAKE",
    ["Makefile.am"]                     = "MAKE",
    ["Makefile.in"]                     = "MAKE",
    ["MANIFEST"]                        = "LANG_PYTHON",
    ["MANIFEST.in"]                     = "LANG_PYTHON",
    ["npm-shrinkwrap.json"]             = "NPM",
    ["npmrc"]                           = "NPM",
    ["package-lock.json"]               = "NPM",
    ["package.json"]                    = "NPM",
    ["passwd"]                          = "LOCK",
    ["php.ini"]                         = "LANG_PHP",
    ["PKGBUILD"]                        = "PKGBUILD",
    ["pom.xml"]                         = "MAVEN",
    ["Procfile"]                        = "PROCFILE",
    ["profile"]                         = "SHELL",
    ["pyproject.toml"]                  = "LANG_PYTHON",
    ["Rakefile"]                        = "LANG_RUBY",
    ["README"]                          = "README",
    ["release.toml"]                    = "LANG_RUST",
    ["requirements.txt"]                = "LANG_PYTHON",
    ["robots.txt"]                      = "ROBOTS",
    ["rubydoc"]                         = "LANG_RUBYRAILS",
    ["rvmrc"]                           = "LANG_RUBY",
    ["settings.gradle.kts"]             = "GRADLE",
    ["shadow"]                          = "LOCK",
    ["shells"]                          = "CONFIG",
    ["sudoers"]                         = "LOCK",
    ["timezone"]                        = "CLOCK",
    ["tsconfig.json"]                   = "LANG_TYPESCRIPT",
    ["Vagrantfile"]                     = "VAGRANT",
    ["webpack.config.js"]               = "WEBPACK",
    ["yarn.lock"]                       = "YARN",
    ["zlogin"]                          = "SHELL",
    ["zlogout"]                         = "SHELL",
    ["zprofile"]                        = "SHELL",
    ["zshenv"]                          = "SHELL",
    ["zshrc"]                           = "SHELL",

    -- More.
    ["CHANGES"]                         = "HISTORY",
    ["CHANGES.md"]                      = "HISTORY",
    ["CHANGES.txt"]                     = "HISTORY",
    ["CHANGELOG"]                       = "HISTORY",
    ["CHANGELOG.md"]                    = "HISTORY",
    ["CHANGELOG.txt"]                   = "HISTORY",
}

local EXTENSION_ICONS =
{
    ["7z"]                              = "COMPRESSED",
    ["a"]                               = "OS_LINUX",
    ["acc"]                             = "AUDIO",
    ["acf"]                             = "ACF",
    ["ai"]                              = "AI",
    ["aif"]                             = "AUDIO",
    ["aifc"]                            = "AUDIO",
    ["aiff"]                            = "AUDIO",
    ["alac"]                            = "AUDIO",
    ["android"]                         = "OS_ANDROID",
    ["ape"]                             = "AUDIO",
    ["apk"]                             = "OS_ANDROID",
    ["apple"]                           = "OS_APPLE",
    ["ar"]                              = "COMPRESSED",
    ["arj"]                             = "COMPRESSED",
    ["arw"]                             = "IMAGE",
    ["asc"]                             = "SHIELD_LOCK",
    ["asm"]                             = "LANG_ASSEMBLY",
    ["asp"]                             = "XML",
    ["avi"]                             = "VIDEO",
    ["avif"]                            = "IMAGE",
    ["avro"]                            = "JSON",
    ["awk"]                             = "SHELL_CMD",
    ["bash"]                            = "SHELL_CMD",
    ["bat"]                             = "OS_WINDOWS_CMD",
    ["bats"]                            = "SHELL_CMD",
    ["bdf"]                             = "FONT",
    ["bib"]                             = "LANG_TEX",
    ["bin"]                             = "BINARY",
    ["bmp"]                             = "IMAGE",
    ["br"]                              = "COMPRESSED",
    ["bst"]                             = "LANG_TEX",
    ["bundle"]                          = "OS_APPLE",
    ["bz"]                              = "COMPRESSED",
    ["bz2"]                             = "COMPRESSED",
    ["bz3"]                             = "COMPRESSED",
    ["c"]                               = "LANG_C",
    ["c++"]                             = "LANG_CPP",
    ["cab"]                             = "OS_WINDOWS",
    ["cbr"]                             = "IMAGE",
    ["cbz"]                             = "IMAGE",
    ["cc"]                              = "LANG_CPP",
    ["cert"]                            = "GIST_SECRET",
    ["cfg"]                             = "CONFIG",
    ["cjs"]                             = "LANG_JAVASCRIPT",
    ["class"]                           = "LANG_JAVA",
    ["clj"]                             = "CLJ",
    ["cljs"]                            = "CLJS",
    ["cls"]                             = "LANG_TEX",
    ["cmake"]                           = "MAKE",
    ["cmd"]                             = "OS_WINDOWS",
    ["coffee"]                          = "COFFEE",
    ["com"]                             = "OS_WINDOWS_CMD",
    ["conf"]                            = "CONFIG",
    ["config"]                          = "CONFIG",
    ["cp"]                              = "LANG_CPP",
    ["cpio"]                            = "COMPRESSED",
    ["cpp"]                             = "LANG_CPP",
    ["cr"]                              = "CR",
    ["cr2"]                             = "IMAGE",
    ["crdownload"]                      = "DOWNLOAD",
    ["crt"]                             = "GIST_SECRET",
    ["cs"]                              = "LANG_CSHARP",
    ["csh"]                             = "SHELL_CMD",
    ["cshtml"]                          = "RAZOR",
    ["csproj"]                          = "LANG_CSHARP",
    ["css"]                             = "CSS3",
    ["csv"]                             = "SHEET",
    ["csx"]                             = "LANG_CSHARP",
    ["cts"]                             = "LANG_TYPESCRIPT",
    ["cu"]                              = "CU",
    ["cue"]                             = "PLAYLIST",
    ["cxx"]                             = "LANG_CPP",
    ["d"]                               = "LANG_D",
    ["dart"]                            = "DART",
    ["db"]                              = "DATABASE",
    ["deb"]                             = "DEB",
    ["desktop"]                         = "DESKTOP",
    ["di"]                              = "LANG_D",
    ["diff"]                            = "DIFF",
    ["djv"]                             = "DOCUMENT",
    ["djvu"]                            = "DOCUMENT",
    ["dll"]                             = "LIBRARY",
    ["dmg"]                             = "DISK_IMAGE",
    ["doc"]                             = "DOCUMENT",
    ["docx"]                            = "DOCUMENT",
    ["dot"]                             = "GV",
    ["download"]                        = "DOWNLOAD",
    ["drawio"]                          = "DRAWIO",
    ["dump"]                            = "DATABASE",
    ["dvi"]                             = "IMAGE",
    ["dylib"]                           = "OS_APPLE",
    ["ebook"]                           = "BOOK",
    ["ebuild"]                          = "EBUILD",
    ["editorconfig"]                    = "CONFIG",
    ["ejs"]                             = "EJS",
    ["el"]                              = "EMACS",
    ["elc"]                             = "EMACS",
    ["elm"]                             = "ELM",
    ["eml"]                             = "EML",
    ["env"]                             = "ENV",
    ["eot"]                             = "FONT",
    ["eps"]                             = "VECTOR",
    ["epub"]                            = "BOOK",
    ["erb"]                             = "LANG_RUBYRAILS",
    ["erl"]                             = "ERL",
    ["ex"]                              = "LANG_ELIXIR",
    ["exe"]                             = "OS_WINDOWS_EXE",
    ["exs"]                             = "LANG_ELIXIR",
    ["f"]                               = "LANG_FORTRAN",
    ["f90"]                             = "LANG_FORTRAN",
    ["fdmdownload"]                     = "DOWNLOAD",
    ["fish"]                            = "SHELL_CMD",
    ["flac"]                            = "AUDIO",
    ["flv"]                             = "VIDEO",
    ["fnt"]                             = "FONT",
    ["fon"]                             = "FONT",
    ["font"]                            = "FONT",
    ["for"]                             = "LANG_FORTRAN",
    ["fs"]                              = "LANG_FSHARP",
    ["fsi"]                             = "LANG_FSHARP",
    ["fsx"]                             = "LANG_FSHARP",
    ["gdoc"]                            = "DOCUMENT",
    ["gem"]                             = "LANG_RUBY",
    ["gemfile"]                         = "LANG_RUBY",
    ["gemspec"]                         = "LANG_RUBY",
    ["gform"]                           = "GFORM",
    ["gif"]                             = "IMAGE",
    ["git"]                             = "GIT",
    ["go"]                              = "LANG_GO",
    ["gpg"]                             = "SHIELD_LOCK",
    ["gradle"]                          = "GRADLE",
    ["groovy"]                          = "LANG_GROOVY",
    ["gsheet"]                          = "SHEET",
    ["gslides"]                         = "SLIDE",
    ["guardfile"]                       = "LANG_RUBY",
    ["gv"]                              = "GV",
    ["gvy"]                             = "LANG_GROOVY",
    ["gz"]                              = "COMPRESSED",
    ["h"]                               = "LANG_C",
    ["h++"]                             = "LANG_CPP",
    ["h264"]                            = "VIDEO",
    ["haml"]                            = "HAML",
    ["hbs"]                             = "MUSTACHE",
    ["heic"]                            = "IMAGE",
    ["heics"]                           = "VIDEO",
    ["heif"]                            = "IMAGE",
    ["hpp"]                             = "LANG_CPP",
    ["hs"]                              = "LANG_HASKELL",
    ["htm"]                             = "HTML5",
    ["html"]                            = "HTML5",
    ["hxx"]                             = "LANG_CPP",
    ["ical"]                            = "CALENDAR",
    ["icalendar"]                       = "CALENDAR",
    ["ico"]                             = "IMAGE",
    ["ics"]                             = "CALENDAR",
    ["ifb"]                             = "CALENDAR",
    ["image"]                           = "DISK_IMAGE",
    ["img"]                             = "DISK_IMAGE",
    ["iml"]                             = "INTELLIJ",
    ["inl"]                             = "LANG_C",
    ["ini"]                             = "CONFIG",
    ["ipynb"]                           = "IPYNB",
    ["iso"]                             = "DISK_IMAGE",
    ["j2c"]                             = "IMAGE",
    ["j2k"]                             = "IMAGE",
    ["jad"]                             = "LANG_JAVA",
    ["jar"]                             = "LANG_JAVA",
    ["java"]                            = "LANG_JAVA",
    ["jfi"]                             = "IMAGE",
    ["jfif"]                            = "IMAGE",
    ["jif"]                             = "IMAGE",
    ["jl"]                              = "JL",
    ["jmd"]                             = "MARKDOWN",
    ["jp2"]                             = "IMAGE",
    ["jpe"]                             = "IMAGE",
    ["jpeg"]                            = "IMAGE",
    ["jpf"]                             = "IMAGE",
    ["jpg"]                             = "IMAGE",
    ["jpx"]                             = "IMAGE",
    ["js"]                              = "LANG_JAVASCRIPT",
    ["json"]                            = "JSON",
    ["jsx"]                             = "REACT",
    ["jxl"]                             = "IMAGE",
    ["kbx"]                             = "SHIELD_KEY",
    ["kdb"]                             = "KEYPASS",
    ["kdbx"]                            = "KEYPASS",
    ["key"]                             = "KEY",
    ["ko"]                              = "OS_LINUX",
    ["ksh"]                             = "SHELL_CMD",
    ["kt"]                              = "LANG_KOTLIN",
    ["kts"]                             = "LANG_KOTLIN",
    ["latex"]                           = "LANG_TEX",
    ["ldb"]                             = "DATABASE",
    ["less"]                            = "LESS",
    ["lhs"]                             = "LANG_HASKELL",
    ["lib"]                             = "LIBRARY",
    ["license"]                         = "LICENSE",
    ["lisp"]                            = "LISP",
    ["localized"]                       = "OS_APPLE",
    ["lock"]                            = "LOCK",
    ["log"]                             = "LOG",
    ["ltx"]                             = "LANG_TEX",
    ["lua"]                             = "LUA",
    ["lz"]                              = "COMPRESSED",
    ["lz4"]                             = "COMPRESSED",
    ["lzh"]                             = "COMPRESSED",
    ["lzma"]                            = "COMPRESSED",
    ["lzo"]                             = "COMPRESSED",
    ["m"]                               = "LANG_C",
    ["m2ts"]                            = "VIDEO",
    ["m2v"]                             = "VIDEO",
    ["m3u"]                             = "PLAYLIST",
    ["m3u8"]                            = "PLAYLIST",
    ["m4a"]                             = "AUDIO",
    ["m4v"]                             = "VIDEO",
    ["magnet"]                          = "MAGNET",
    ["markdown"]                        = "MARKDOWN",
    ["md"]                              = "MARKDOWN",
    ["md5"]                             = "SHIELD_CHECK",
    ["mdb"]                             = "DATABASE",
    ["mid"]                             = "MID",
    ["mjs"]                             = "LANG_JAVASCRIPT",
    ["mk"]                              = "MAKE",
    ["mka"]                             = "AUDIO",
    ["mkd"]                             = "MARKDOWN",
    ["mkv"]                             = "VIDEO",
    ["ml"]                              = "LANG_OCAML",
    ["mli"]                             = "LANG_OCAML",
    ["mll"]                             = "LANG_OCAML",
    ["mly"]                             = "LANG_OCAML",
    ["mm"]                              = "LANG_CPP",
    ["mobi"]                            = "BOOK",
    ["mov"]                             = "VIDEO",
    ["mp2"]                             = "AUDIO",
    ["mp3"]                             = "AUDIO",
    ["mp4"]                             = "VIDEO",
    ["mpeg"]                            = "VIDEO",
    ["mpg"]                             = "VIDEO",
    ["msi"]                             = "OS_WINDOWS",
    ["mts"]                             = "LANG_TYPESCRIPT",
    ["mustache"]                        = "MUSTACHE",
    ["nef"]                             = "IMAGE",
    ["ninja"]                           = "NINJA",
    ["nix"]                             = "NIX",
    ["node"]                            = "NODEJS",
    ["o"]                               = "BINARY",
    ["odp"]                             = "SLIDE",
    ["ods"]                             = "SHEET",
    ["odt"]                             = "DOCUMENT",
    ["ogg"]                             = "AUDIO",
    ["ogm"]                             = "VIDEO",
    ["ogv"]                             = "VIDEO",
    ["opus"]                            = "AUDIO",
    ["orf"]                             = "IMAGE",
    ["org"]                             = "ORG",
    ["otf"]                             = "FONT",
    ["out"]                             = "OUT_EXT",
    ["p12"]                             = "KEY",
    ["par"]                             = "COMPRESSED",
    ["part"]                            = "DOWNLOAD",
    ["patch"]                           = "DIFF",
    ["pbm"]                             = "IMAGE",
    ["pcm"]                             = "AUDIO",
    ["pdf"]                             = "PDF",
    ["pem"]                             = "KEY",
    ["pfx"]                             = "KEY",
    ["pgm"]                             = "IMAGE",
    ["phar"]                            = "LANG_PHP",
    ["php"]                             = "LANG_PHP",
    ["pkg"]                             = "PKG",
    ["pl"]                              = "LANG_PERL",
    ["plist"]                           = "OS_APPLE",
    ["plx"]                             = "LANG_PERL",
    ["pm"]                              = "LANG_PERL",
    ["png"]                             = "IMAGE",
    ["pnm"]                             = "IMAGE",
    ["pod"]                             = "LANG_PERL",
    ["pp"]                              = "PP",
    ["ppm"]                             = "IMAGE",
    ["pps"]                             = "SLIDE",
    ["ppsx"]                            = "SLIDE",
    ["ppt"]                             = "SLIDE",
    ["pptx"]                            = "SLIDE",
    ["properties"]                      = "JSON",
    ["prql"]                            = "DATABASE",
    ["ps"]                              = "VECTOR",
    ["ps1"]                             = "POWERSHELL",
    ["psd"]                             = "PSD",
    ["psd1"]                            = "POWERSHELL",
    ["psf"]                             = "FONT",
    ["psm1"]                            = "POWERSHELL",
    ["pub"]                             = "PUBLIC_KEY",
    ["purs"]                            = "PURS",
    ["pxm"]                             = "IMAGE",
    ["py"]                              = "LANG_PYTHON",
    ["pyc"]                             = "LANG_PYTHON",
    ["pyd"]                             = "LANG_PYTHON",
    ["pyi"]                             = "LANG_PYTHON",
    ["pyo"]                             = "LANG_PYTHON",
    ["qcow"]                            = "DISK_IMAGE",
    ["qcow2"]                           = "DISK_IMAGE",
    ["r"]                               = "LANG_R",
    ["rar"]                             = "COMPRESSED",
    ["raw"]                             = "IMAGE",
    ["razor"]                           = "RAZOR",
    ["rb"]                              = "LANG_RUBY",
    ["rdata"]                           = "LANG_R",
    ["rdb"]                             = "RDB",
    ["rdoc"]                            = "MARKDOWN",
    ["rds"]                             = "LANG_R",
    ["readme"]                          = "README",
    ["rlib"]                            = "LANG_RUST",
    ["rmd"]                             = "MARKDOWN",
    ["rmeta"]                           = "LANG_RUST",
    ["rpm"]                             = "RPM",
    ["rs"]                              = "LANG_RUST",
    ["rspec"]                           = "LANG_RUBY",
    ["rspec_parallel"]                  = "LANG_RUBY",
    ["rspec_status"]                    = "LANG_RUBY",
    ["rss"]                             = "RSS",
    ["rst"]                             = "TEXT",
    ["rtf"]                             = "TEXT",
    ["ru"]                              = "LANG_RUBY",
    ["rubydoc"]                         = "LANG_RUBYRAILS",
    ["s"]                               = "LANG_ASSEMBLY",
    ["sass"]                            = "LANG_SASS",
    ["sbt"]                             = "SUBTITLE",
    ["scala"]                           = "SCALA",
    ["scss"]                            = "LANG_SASS",
    ["service"]                         = "SERVICE",
    ["sh"]                              = "SHELL_CMD",
    ["sha1"]                            = "SHIELD_CHECK",
    ["sha224"]                          = "SHIELD_CHECK",
    ["sha256"]                          = "SHIELD_CHECK",
    ["sha384"]                          = "SHIELD_CHECK",
    ["sha512"]                          = "SHIELD_CHECK",
    ["shell"]                           = "SHELL_CMD",
    ["shtml"]                           = "HTML5",
    ["sig"]                             = "SIGNED_FILE",
    ["signature"]                       = "SIGNED_FILE",
    ["slim"]                            = "LANG_RUBYRAILS",
    ["sln"]                             = "SLN",
    ["so"]                              = "OS_LINUX",
    ["sql"]                             = "DATABASE",
    ["sqlite3"]                         = "SQLITE3",
    ["srt"]                             = "SUBTITLE",
    ["ssa"]                             = "SUBTITLE",
    ["stl"]                             = "IMAGE",
    ["sty"]                             = "LANG_TEX",
    ["styl"]                            = "LANG_STYLUS",
    ["stylus"]                          = "LANG_STYLUS",
    ["sub"]                             = "SUBTITLE",
    ["sublime-build"]                   = "SUBLIME",
    ["sublime-keymap"]                  = "SUBLIME",
    ["sublime-menu"]                    = "SUBLIME",
    ["sublime-options"]                 = "SUBLIME",
    ["sublime-package"]                 = "SUBLIME",
    ["sublime-project"]                 = "SUBLIME",
    ["sublime-session"]                 = "SUBLIME",
    ["sublime-settings"]                = "SUBLIME",
    ["sublime-snippet"]                 = "SUBLIME",
    ["sublime-theme"]                   = "SUBLIME",
    ["svelte"]                          = "SVELTE",
    ["svg"]                             = "VECTOR",
    ["swift"]                           = "SWIFT",
    ["t"]                               = "LANG_PERL",
    ["tar"]                             = "COMPRESSED",
    ["taz"]                             = "COMPRESSED",
    ["tbz"]                             = "COMPRESSED",
    ["tbz2"]                            = "COMPRESSED",
    ["tc"]                              = "DISK_IMAGE",
    ["tex"]                             = "LANG_TEX",
    ["tf"]                              = "TERRAFORM",
    ["tfstate"]                         = "TERRAFORM",
    ["tfvars"]                          = "TERRAFORM",
    ["tgz"]                             = "COMPRESSED",
    ["tif"]                             = "IMAGE",
    ["tiff"]                            = "IMAGE",
    ["tlz"]                             = "COMPRESSED",
    ["tml"]                             = "CONFIG",
    ["toml"]                            = "CONFIG",
    ["torrent"]                         = "TORRENT",
    ["ts"]                              = "LANG_TYPESCRIPT",
    ["tsv"]                             = "SHEET",
    ["tsx"]                             = "REACT",
    ["ttc"]                             = "FONT",
    ["ttf"]                             = "FONT",
    ["twig"]                            = "TWIG",
    ["txt"]                             = "TEXT",
    ["typ"]                             = "TYPST",
    ["txz"]                             = "COMPRESSED",
    ["tz"]                              = "COMPRESSED",
    ["tzo"]                             = "COMPRESSED",
    ["unity"]                           = "UNITY",
    ["unity3d"]                         = "UNITY",
    ["v"]                               = "LANG_V",
    ["vcxproj"]                         = "SLN",
    ["vdi"]                             = "DISK_IMAGE",
    ["vhd"]                             = "DISK_IMAGE",
    ["video"]                           = "VIDEO",
    ["vim"]                             = "VIM",
    ["vmdk"]                            = "DISK_IMAGE",
    ["vob"]                             = "VIDEO",
    ["vue"]                             = "VUE",
    ["war"]                             = "LANG_JAVA",
    ["wav"]                             = "AUDIO",
    ["webm"]                            = "VIDEO",
    ["webmanifest"]                     = "JSON",
    ["webp"]                            = "IMAGE",
    ["whl"]                             = "LANG_PYTHON",
    ["windows"]                         = "OS_WINDOWS",
    ["wma"]                             = "AUDIO",
    ["wmv"]                             = "VIDEO",
    ["woff"]                            = "FONT",
    ["woff2"]                           = "FONT",
    ["wv"]                              = "AUDIO",
    ["xcf"]                             = "IMAGE",
    ["xhtml"]                           = "HTML5",
    ["xlr"]                             = "SHEET",
    ["xls"]                             = "SHEET",
    ["xlsm"]                            = "SHEET",
    ["xlsx"]                            = "SHEET",
    ["xml"]                             = "XML",
    ["xpm"]                             = "IMAGE",
    ["xul"]                             = "XML",
    ["xz"]                              = "COMPRESSED",
    ["yaml"]                            = "YAML",
    ["yml"]                             = "YAML",
    ["z"]                               = "COMPRESSED",
    ["zig"]                             = "ZIG",
    ["zip"]                             = "COMPRESSED",
    ["zsh"]                             = "SHELL_CMD",
    ["zsh-theme"]                       = "SHELL",
    ["zst"]                             = "COMPRESSED",

    -- More.
    ["pdb"]                             = "PDB",
}

local function get_dir_name(dir)
    dir = dir:gsub("[/\\]+$", "")
    local name = path.getname(dir) or ""
    if name == "" then
        name = dir:match("[/\\]([^/\\]+)$") or ""
    end
    return name
end

local function get_dir_icon(name)
    name = name:gsub("[/\\]+$", "")
    local icon_name = DIR_ICONS[get_dir_name(name)]
    if icon_name then
        return get_icon(icon_name)
    end
end

local function get_file_icon(name)
    local icon_name = FILE_ICONS[name]
    if not icon_name then
        name = clink.lower(path.getname(name))
        if name:match("^readme") then
            icon_name = "INFO"
        else
            local ext = path.getextension(name)
            if ext then
                icon_name = EXTENSION_ICONS[ext:sub(2)]
            end
        end
    end
    if icon_name then
        return get_icon(icon_name)
    end
end

local function backfill_icons(matches)
    for _, m in ipairs(matches) do
        if m.type then
            local icon
            local text = m.display or m.match

            -- See documentation for info on how match type strings work.
            -- https://chrisant996.github.io/clink/clink.html#builder:addmatch

            -- Choose icons for word, arg, cmd, alias, and none match types.
            if m.type:find("alias") then
                icon = "="
            elseif m.type:find("cmd") then
                icon = get_icon("OS_WINDOWS_CMD")
            elseif not m.type:find("file") and not m.type:find("dir") then
                icon = ""
            end

            -- If an icon was chosen, jam it together with a color and the match
            -- text, and make a custom display string.
            if icon then
                local color = rl.getmatchcolor(m)
                m.display = "\x1b[m"..color..icon..spacing..text
            end
        end
    end
    return matches
end

local function init(nobackfill)
    if settings.get("matchicons.enable") then
        nerd_fonts_version = tonumber(os.getenv("DIRX_NERD_FONTS_VERSION") or "") or 0
        if nerd_fonts_version ~= 2 then
            nerd_fonts_version = 3
        end

        spacing = os.getenv("DIRX_ICON_SPACING") or os.getenv("EZA_ICON_SPACING") or os.getenv("EXA_ICON_SPACING")
        spacing = tonumber(spacing or "") or 0
        if spacing < 1 then
            spacing = 1
        elseif spacing > 4 then
            spacing = 4
        end
        spacing = string.rep(" ", spacing)

        if not nobackfill then
            clink.ondisplaymatches(backfill_icons)
        end
        return true
    end
end

local function get_match_icon(m)
    if m.type then
        if m.type:find("file") then
            local text = path.getname(m.match)
            local icon = get_file_icon(text)
            if not icon then
                if m.type:find("link") then
                    icon = get_icon("FILE_LINK")
                else
                    local ext = path.getextension(text) or ""
                    icon = get_icon(ext == "" and "FILE_OUTLINE" or "FILE")
                end
            end
            return icon
        elseif m.type:find("dir") then
            local text = get_dir_name(m.match)
            local icon = get_dir_icon(text) or get_icon(m.type:find("link") and "FOLDER_LINK" or "FOLDER")
            return icon
        end
    end
end

local function add_icons(matches, nobackfill)
    if init(nobackfill) then
        for _, m in ipairs(matches) do
            if m.type then
                -- See documentation for info on how match type strings work.
                -- https://chrisant996.github.io/clink/clink.html#builder:addmatch

                -- Choose icons for file and directory matches.
                local icon
                local text
                if m.type:find("file") then
                    text = path.getname(m.match)
                    icon = get_file_icon(text)
                    if not icon then
                        if m.type:find("link") then
                            icon = get_icon("FILE_LINK")
                        else
                            local ext = path.getextension(text) or ""
                            icon = get_icon(ext == "" and "FILE_OUTLINE" or "FILE")
                        end
                    end
                    text = m.display or text
                elseif m.type:find("dir") then
                    text = get_dir_name(m.match)
                    icon = get_dir_icon(text) or get_icon(m.type:find("link") and "FOLDER_LINK" or "FOLDER")
                    text = m.display or text.."\\"
                else
                    text = m.display or m.match
                end

                -- If an icon was chosen, jam it together with a color and the match
                -- text, and make a custom display string.
                if icon then
                    local color = rl.getmatchcolor(m)
                    m.display = "\x1b[m"..color..icon..spacing..text
                end
            end
        end
    end
    return matches
end

-- WARNING:  The technique of replacing functions is possible in Lua, but it can
--           very easily break scripts that use the functions.  There's no way
--           for a replacement function to be completely safe:  since it changes
--           the behavior of the replaced function, that can inherently break
--           scripts that call the function.

-- Remember the original functions, so the new functions can call the original
-- functions to do the work of actually generating the matches.
local original_dirmatches = clink.dirmatches
local original_filematches = clink.filematches
local original_dirmatchesexact = clink.dirmatchesexact
local original_filematchesexact = clink.filematchesexact

-- Replace the functions with variants that add icons.
clink.dirmatches = function (word)
    return add_icons(original_dirmatches(word))
end
clink.filematches = function (word)
    return add_icons(original_filematches(word))
end
if original_dirmatchesexact then
    clink.dirmatchesexact = function (word)
        return add_icons(original_dirmatchesexact(word))
    end
end
if original_filematchesexact then
    clink.filematchesexact = function (word)
        return add_icons(original_filematchesexact(word))
    end
end

matchicons.geticon = function(match)
    if type(match) == "table" then
        return get_match_icon(match)
    elseif match then
        return get_match_icon({ match=match })
    end
end

matchicons.addicons = function(matches)
    return add_icons(matches, true)
end

matchicons.addicontomatch = function (m, icon, color)
    if init(true) then
        -- See documentation for info on how match type strings work.
        -- https://chrisant996.github.io/clink/clink.html#builder:addmatch

        if not icon then
            icon = get_match_icon(m)
        end

        if icon and console.cellcount(icon) == 1 then
            local text
            if m.type:find("file") then
                text = m.display or path.getname(m.match)
            elseif m.type:find("dir") then
                text = m.display or get_dir_name(m.match).."\\"
            else
                text = m.display or m.match
            end

            -- Jam the icon together with a color and the match text, and make a
            -- custom display string.
            if icon then
                if color then
                    color = "\x1b[0;"..color.."m"
                else
                    color = "\x1b[m"
                end
                m.display = color..icon..spacing..text
            end
        end
    end
    return m
end
