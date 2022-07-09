--------------------------------------------------------------------------------
-- Clink argmatcher for Robocopy.
-- Uses delayinit to parse the Robocopy help text.

-- This script requires Clink v1.3.10 or higher.
if (clink.version_encoded or 0) < 10030010 then
    return
end

require('arghelper')

local function delayinit(argmatcher)
    local r = io.popen('robocopy.exe /??? 2>nul')
    if not r then
        return
    end

    local flags = {}
    local descriptions = {}

    local function add_match(flag, disp, desc)
        desc = clink.upper(desc:sub(1,1))..desc:sub(2)
        table.insert(flags, flag)
        if disp then
            descriptions[flag] = { disp, desc }
        else
            descriptions[flag] = { desc }
        end
    end

    local flag, disp, desc
    for line in r:lines() do
        if unicode.fromcodepage then
            line = unicode.fromcodepage(line)
        end
        local f,d = line:match('^ *(/[^ ]+) :: (.+)$')
        if f then
            local a,b = f:match('^(.-)%[:(.+)%]$')
            if a then
                add_match(a, nil, d)
                add_match(a..':', b, d)
            else
                a,b = f:match('^([^:]+:)(.+)$')
                if not a then
                    a,b = f:match('^([^ ]+)( .+)$')
                end
                if a then
                    add_match(a, b, d)
                else
                    add_match(f, nil, d)
                end
            end
        end
    end

    r:close()

    argmatcher:addflags(flags)
    argmatcher:adddescriptions(descriptions)
    return true
end

clink.argmatcher('robocopy'):setdelayinit(delayinit)
