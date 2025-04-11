--------------------------------------------------------------------------------
-- This script adds aliases for searching various popular services from the
-- command line.
--
-- You can disable this by running "clink set web_search.enable false".
--
-- USAGE:
--
--  You can use this either of these ways:
--
--      - Run "web_search <context> <term> [more terms...]"
--      - Run "<context> <term> [more terms...]"
--
--  For example, these do the same thing:
--
--      c:\> web_search google clink
--      c:\> google clink
--
--  Each search context has a doskey alias created for convenience, so that
--  the Executable Completion feature of Clink can offer them as completions.
--
--  See further below for the list of available search contexts, or run
--  "web_search --list" to print a list of available search contexts in the
--  terminal window.
--
--  When this script is loaded by Clink, it looks for a ".web_search" file and
--  loads additional search contexts from the file.  Each line in the file can
--  add a context or remove a context.  The script tries to load a ".web_search"
--  file from each of these locations:  the %USERPROFILE% directory, the Clink
--  profile directory, the directory containing the Clink program files, and the
--  directory in the %CLINK_WEB_SEARCH% environment variable.
--
--  To add a search context, a line can have a name and a URL:
--
--      name_to_add https://someservice.com/search?q=
--
--  To remove a search context, a line can have just a name:
--
--      name_to_remove
--
--------------------------------------------------------------------------------
-- This is similar to the "web-search" plugin for zsh:
-- https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/web-search
-- The license there is the MIT license.
--------------------------------------------------------------------------------

local contexts = {
    -- Popular search engines.
    ["bing"] = "https://www.bing.com/search?q=",
    ["google"] = "https://www.google.com/search?q=",
    ["brave"] = "https://search.brave.com/search?q=",
    ["yahoo"] = "https://search.yahoo.com/search?p=",
    ["duckduckgo"] = "https://www.duckduckgo.com/?q=",
    ["startpage"] = "https://www.startpage.com/do/search?q=",
    ["ecosia"] = "https://www.ecosia.org/search?q=",
    ["qwant"] = "https://www.qwant.com/?q=",
    ["givero"] = "https://www.givero.com/search?q=",
    ["stackoverflow"] = "https://stackoverflow.com/search?q=",
    ["wolframalpha"] = "https://www.wolframalpha.com/input/?i=",
    ["archive"] = "https://web.archive.org/web/*/",
    ["scholar"] = "https://scholar.google.com/scholar?q=",
    ["ask"] = "https://www.ask.com/web?q=",
    ["baidu"] = "https://www.baidu.com/s?wd=",
    ["yandex"] = "https://yandex.ru/yandsearch?text=",

    -- Translation.
    ["deepl"] = "https://www.deepl.com/translator#auto/auto/",

    -- Programming.
    ["github"] = "https://github.com/search?q=",
    ["cplusplus"] = "https://cplusplus.com/search.do?q=",
    ["cppreference"] = "https://www.duckduckgo.com/?sites=cppreference.com&q=",
    ["crates"] = "https://crates.io/search?q=",
    ["dockerhub"] = "https://hub.docker.com/search?q=",
    ["npmpkg"] = "https://www.npmjs.com/search?q=",
    ["packagist"] = "https://packagist.org/?query=",
    ["gopkg"] = "https://pkg.go.dev/search?m=package&q=",

    -- Books, videos, conversations.
    ["goodreads"] = "https://www.goodreads.com/search?q=",
    ["youtube"] = "https://www.youtube.com/results?search_query=",
    ["reddit"] = "https://www.reddit.com/search/?q=",

    -- AI.
    ["chatgpt"] = "https://chatgpt.com/?q=",
    ["ppai"] = "https://www.perplexity.ai/search/new?q=",

    -- Commerce.
    ["amazon"] = "https://www.amazon.com/s?k=",

    -- Bang-searching shortcuts for DuckDuckGo.
    ["wiki"] = "duckduckgo !w",
    ["news"] = "duckduckgo !n",
    ["map"] = "duckduckgo !m",
    ["image"] = "duckduckgo !i",
    ["ducky"] = "duckduckgo !",

    -- Shortcut names for some search contexts.
    ["brs"] = "brave",
    ["ddg"] = "duckduckgo",
    ["sp"] = "startpage",
    ["yt"] = "youtube",
}

--------------------------------------------------------------------------------
-- Decide whether the script can be loaded.

if not clink.onfilterinput then
    print("web_search.lua requires a newer version of Clink; please upgrade.")
    return
end

settings.add("web_search.enable", true, "Web search shortcuts",
             "Adds aliases for web search shortcuts.  For example,\n"..
             "type \"bing some words\" to use Bing to search for \"some words\".\n"..
             "Type \"web_search --list\" to list the available search shortcuts.")

if not settings.get("web_search.enable") then
    return
end

--------------------------------------------------------------------------------
-- Load additional search contexts.

local function load_contexts(from)
    from = (from or ""):gsub("^ +", ""):gsub(" +$", "")
    if from ~= "" then
        local name = path.join(from, ".web_search")
        local f = io.open(name)
        if f then
            local n = 0
            for l in f:lines() do
                if l:match("^[^-;#/]") then
                    local url
                    name, url = l:match("^%s*([^%s]+)%s+(.*)$")
                    if name then
                        if url then
                            -- Add a search context
                            contexts[name] = url
                            n = n + 1
                        else
                            -- Remove a search context.
                            contexts[name:sub(2)] = nil
                            n = n + 1
                        end
                    end
                end
            end
            f:close()
            if n > 0 then
                log.info(string.format('Loaded %d search contexts from "%s".', n, name))
            end
        end
    end
end

load_contexts(os.getenv("USERPROFILE"))
load_contexts(os.getenv("=clink.profile"))
load_contexts(os.getenv("=clink.bin"))

--------------------------------------------------------------------------------
-- Create doskey aliases for the available search contexts.

local context_names = {}
for n in pairs(contexts) do
    table.insert(context_names, n)
    local a = os.getalias(n)
    if not a or a:find("^web_search%s") then
        os.setalias(n, "web_search "..n.." $*")
    end
end

if (clink.version_encoded or 0) < 10070015 then
    -- Work around a bug in clink.parseline() in Clink v1.7.14 and lower.
    os.setalias("web_search", "web_search_workaround $*")
else
    os.setalias("web_search", "web_search $*")
end

--------------------------------------------------------------------------------
-- The web_search() function.

local function pad(text, max_width)
    local width = console.cellcount(text)
    return text..string.rep(" ", max_width - width)
end

local function web_search(input, nested)
    -- Parse the context name and arguments.
    local name = input:match("^%s*([^%s]+)")
    local _, args = input:match("^%s*([^%s]+)%s+(.*)$")

    -- List available contexts, if requested.
    if name == "--list" then
        local list = {}
        local max_width = 0
        for n in pairs(contexts) do
            max_width = math.max(max_width, console.cellcount(n))
            table.insert(list, n)
        end
        table.sort(list)
        max_width = max_width + 4
        for _, n in ipairs(list) do
            clink.print(pad(n, max_width)..contexts[n])
        end
        return
    end

    -- Verify that the specified context is available.
    local url = contexts[name or ""]
    if not name or not url then
        print("Search engine '"..(name or "").."' not supported.")
        return
    end

    -- A context can be a shortcut for another context (shortcuts are not
    -- recursive).
    if url and not nested then
        local engine = url:match("^([^:%s]+)")
        if engine and contexts[url] then
            web_search(url..(args and " "..args or ""), true--[[nested]])
            return
        end
    end

    -- Translate spaces as needed.
    if args then
        args = args:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "+")
        args = (args ~= "") and args or nil
    end

    -- If no arguments were provided, navigate to the context's domain name.
    if not args then
        url = url:match("^([a-zA-Z0-9]+://[^/]+/)")
        if not url then
            print("Search engine URL format is unexpected for '"..name.."'.")
            return
        end
    end

    -- If arguments were provided, use them to build the web query URL.
    if args then
        args = args:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "+")
        url = url..args
    end

    -- Launch the URL.
    os.execute(string.format(' start "" %s', url))
end

--------------------------------------------------------------------------------
-- Intercept input lines and process web_search commands.

clink.onfilterinput(function(text)
    local context = text:match("^%s*([^%s]+)")
    if context then
        local args
        if contexts[context:lower()] then
            args = text:match("^%s*(.*)$")
        elseif context == "web_search" then
            args = text:match("^%s*[^%s]+%s+(.*)$")
        end
        if args then
            web_search(args)
            return "", false
        end
    end
end)

--------------------------------------------------------------------------------
-- Completions for web_search commands.

local ws = clink.argmatcher("web_search")
:addflags("--list")
:addarg(context_names)
:addarg()
:loop(2)

if ws.setflagsanywhere then
    ws:setflagsanywhere(false)
end
