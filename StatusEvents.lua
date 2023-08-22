require "tprint"
require "var"
require "serialize"
require "gmcphelper"
require "wait"
require "wrapped_captures"

dofile(GetInfo(60) .. "aardwolf_colors.lua")

local VERSION = "1.002"

--   1         At login screen, no player yet
--   2         Player at MOTD or other login sequence
--   3         Player fully active and able to receive MUD commands
--   4         Player AFK
--   5         Player in note
--   6         Player in Building/Edit mode
--   7         Player at paged output prompt
--   8         Player in combat
--   9         Player sleeping
--   11        Player resting or sitting
--   12        Player running

----------------------------------------------------------

--  Types

----------------------------------------------------------

---@alias TokenType
---| "string"
---| "keyword"
---| "number"
---| "boolean"
---| "any"

---@alias Token { value: string|number|boolean?, type: TokenType }

---@alias HelpCategory
---| "Meta"
---| "Use"
---| "Manage"

---@alias HelpEntry { command: string, summary: string, body: string}

----------------------------------------------------------

--  State

----------------------------------------------------------

local oStatusEvts = {
    aardStatus = {
        ["1"] = false,
        ["2"] = false,
        ["3"] = false,
        ["4"] = false,
        ["5"] = false,
        ["6"] = false,
        ["7"] = false,
        ["8"] = false,
        ["9"] = false,
        ["11"] = false,
        ["12"] = false,
        ["99"] = false
    },
    aardStatusLabel = {
        ["1"] = "login",
        ["2"] = "motd",
        ["3"] = "active",
        ["4"] = "afk",
        ["5"] = "note",
        ["6"] = "building/edit",
        ["7"] = "paged",
        ["8"] = "combat",
        ["9"] = "sleeping",
        ["11"] = "resting/sitting",
        ["12"] = "running",
        ["99"] = "pk combat"
    },
    options = {}
}

---@type { [HelpCategory]: {[string]: HelpEntry} }
local helpFiles = {
    Meta = {
        Help = {
            command = "events help [topic]",
            summary = "Help about Help!",
            body = [[events help by itself will show a categorized index of all help files.

Passing in a topic will pull up the help file for that specific command for
more detailed help.]],
        },
        Overview = {
            command = "<n/a>",
            summary = "A general overview of the plugin.",
            body = [[StatusEvents is a simple plugin. It provides a mechanism to respond to the
character status information Aardwolf provides via GMCP. The status can be
one of the following values:

1         At login screen, no player yet
2         Player at MOTD or other login sequence
3         Player fully active and able to receive MUD commands
4         Player AFK
5         Player in note
6         Player in Building/Edit mode
7         Player at paged output prompt
8         Player in combat
9         Player sleeping
11        Player resting or sitting
12        Player running

The plugin can operate in two modes:
    1) It can generate a line from the mud that can be triggered upon
       using Mushclient's trigger functionality.

    2) It can execute actions stored in the plugin on either the Start or
       End of an event.

Both modes can be used at the same time. There is an additional synthetic
event the plugin provides for PK Combat. PK Combat is treated as an
addition to regular combat. For PK Combat, both Combat and PK Combat
actions will be fired and triggers generated.

The plugin exposes all the events the game provides and the actions the
plugin runs are processed in the same manner as if you typed them into
Mushclient yourself. This means that aliases, etc work fine as an action.]]
        }
    },
    Use = {},
    Manage = {
        List = {
            command = "events list",
            summary = "Show all configure for events and manage them.",
            body = [[Shows a list of all events. Events may be enabled individually.

            Per event configuration is saved through enable and disable cycles.  By default,
            only the Combat (8) event is enabled.  Clicking the View link on an event will
            open that individual event's configuration.]],
        },
        View = {
            command = "events view <event number>",
            summary = "View details for a specific event.",
            body = [[Views the details of the passed event.

Allows you to toggle trigger text emission and custom trigger messaging.

An action management table allows for the addition, removal, moving, and
editing of actions.  All the links have tool tips and it should be fairly
self explanatory.  Actions may fire either at the Start of an event or at
the End.  Clicking the 'Fire at Start' or 'Fire at End' link will toggle
it to the other state. Actions maybe individual disabled.  They are
executed in the order listed but may be moved by clicking the \/ and /\
arrow links to move the action up and down the list respectively.]]
        },
        Modify = {
            command = "modify <event number> action [subcommand] [subcommand parameters]",
            summary = "Modifies the configuration for the provided event.",
            body = [[This is a fairly large command. Luckily, chances are you will rarely if
ever use this command directly. The user interface uses this command to do
all the different modifications that are supported.

This command is really multiple sub-commands grouped under a common
banner. We'll go through each of these sub-commands one by one. Parameters
surrounded by square brackets [] are optional.

events modify <event index> action toggle [true or false]

Enables or disables event processing.

events modify <event index> action <action index> remove

Deletes the action from the action table.

events modify <event index> action <action index> edit prompt|string

Edits the action provided. A value of prompt opens a dialog to enter a
string or, the string can be passed in directly.

events modify <event index> action <action index> move up

Moves the action located at 'action index' in the action list higher in
the list of actions that belong to the event.

events modify <event index> action <action index> move down

Moves the action located at 'action index' in the action list lower in the
list of actions that belong to the event.

events modify <event index> action <action index> togglephase

Toggles the phase of the action between Fire at Start and Fire at End.

events modify <event index> action new prompt|string

Adds a new action to the event's action list. If the value of prompt is
provided then a dialog appears which accepts the new action value. If a
string is provided then the action value is directly set.

events modify <event index> action <action index> toggle

Enables or Disables the action located at 'action index' in the action
list.

events modify <event index> action togglecustom

Enables or Disables the use of custom trigger messages for an event.

events modify <event index> action setenable prompt|string

Set the Start of Event custom trigger value. If a value of prompt is
provided then a dialog appears which acepts the new value. If a string is
provided then the value is directly set.

events modify <event index> action setdisable prompt|string

Set the End of Event custom trigger value. If a value of prompt is
provided then a dialog appears which acepts the new value. If a string is
provided then the value is directly set.]]
        }
    },
}

---@type { [string]: boolean }
local keywords = {
    action = true,
    toggle = true,
    remove = true,
    edit = true,
    prompt = true,
    new = true,
    move = true,
    up = true,
    down = true,
    togglephase = true,
    togglecustom = true,
    setenable = true,
    setdisable = true
}

---@type { [string]: Token[][] }
local parameters = {
    modify = {
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "toggle" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "toggle" },
            { type = "boolean" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "remove" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "edit" },
            { type = "keyword", value = "prompt" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "edit" },
            { type = "string" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "move" },
            { type = "keyword", value = "up" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "move" },
            { type = "keyword", value = "down" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "togglephase" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "new" },
            { type = "keyword", value = "prompt" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "new" },
            { type = "string" }
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "number" },
            { type = "keyword", value = "toggle" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "togglecustom" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "setenable" },
            { type = "keyword", value = "prompt" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "setenable" },
            { type = "string" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "setdisable" },
            { type = "keyword", value = "prompt" },
        },
        {
            { type = "number" },
            { type = "keyword", value = "action" },
            { type = "keyword", value = "setdisable" },
            { type = "string" },
        },
    },
}
----------------------------------------------------------

--  Utilities

----------------------------------------------------------

---Returns iterator that traverses table following order of its keys.
---From Programming in Lua 19.3
---@param t table
---@param f function?
---@return function
function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0             -- iterator variable
    local iter = function() -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end

    return iter
end

---Returns a shallow copy of a subset of a table.
---@param t table
---@param s integer
---@param e integer
---@return table
local function slice(t, s, e)
    local pos, new = 1, {}

    for i = s, e do
        new[pos] = t[i]
        pos = pos + 1
    end

    return new
end

---Escapes special characters for pattern matching
---@param str string
---@return string
local function escapePattern(str)
    return (str:gsub('%%', '%%%%')
        :gsub('^%^', '%%^')
        :gsub('%$$', '%%$')
        :gsub('%(', '%%(')
        :gsub('%)', '%%)')
        :gsub('%.', '%%.')
        :gsub('%[', '%%[')
        :gsub('%]', '%%]')
        :gsub('%*', '%%*')
        :gsub('%+', '%%+')
        :gsub('%-', '%%-')
        :gsub('%?', '%%?'))
end

---Trims whitespace from string
---@param str string
---@return string
local function trim(str)
    return str:match '^()%s*$' and '' or str:match '^%s*(.*%S)'
end

---Returns the first word in a string
---@param str string The deliminated string
---@param delimiter string? The separator character. Defaults to space.
---@return string head The first 'word' in the string
local function head(str, delimiter)
    local delim = delimiter or " "

    if not str then
        return ""
    end

    local result = string.match(str, "^[^" .. escapePattern(delim) .. "]+")

    return result or ""
end

---Returns the rest of the words in a string
---@param str string The deliminated string
---@param delimiter string? The separator character. Defaults to space.
---@return string body The every after the head of the string
local function body(str, delimiter)
    local head = head(str, delimiter)
    local delim = delimiter or " "
    local hasMatches = string.match(str, head .. delim)

    if hasMatches then
        return (string.gsub(str, escapePattern(head .. delim), "", 1))
    else
        return ""
    end
end

---Iterates through a delimiter separated string.
---Each chunk is passed through the supplied callback.
---@param str string
---@param callback fun(chunk: string): nil
---@param delimiter string? The delimiter to use. Defaults to space.
---@return nil
local function iter(str, callback, delimiter)
    local delim = delimiter or " "
    local head = head(str, delim)

    if head:len() ~= 0 then
        callback(head)
        iter(body(str, delim), callback, delim)
    end
end

---Strips color codes from passed string.
---@param str string
---@return string
local function stripCodes(str)
    local stripped = (str:gsub("@[Xx]%d%d?%d?", ""))
    return (stripped:gsub("@[a-zA-Z]", ""))
end

---Repeats a string a given number of times with an optional border.
---@param item string
---@param times number
---@param border string?
---@return string
local function strrepeat(item, times, border)
    local result = ""
    local borderChar = border and border or ""

    for _ = 1, times do
        result = result .. item
    end

    if (border) then
        result = borderChar .. result:sub(2, #result - 1) .. borderChar
    end

    return result
end

---Centers a string within a given width, an optional fill character,
---and an optional border string.
---@param item string
---@param width number
---@param char string? Defaults to space
---@param border string? Defaults to no border
local function center(item, width, char, border)
    local itemHalfLen = math.ceil(string.len(item) / 2)
    local widthHalfLen = math.ceil((width / 2))
    local itemStart = widthHalfLen - itemHalfLen
    local remainder = width - itemStart - string.len(item)
    local result = ""
    local centerChar = char and char or " "
    local borderChar = border and border or nil

    result = strrepeat(centerChar, itemStart) .. item .. strrepeat(centerChar, remainder)

    if (border) then
        result = borderChar .. result:sub(2, #result - 1) .. borderChar
    end

    return result
end

---Right pads the given string
---@param str string
---@param width number
---@param char? string Defaults to space
---@return string
local function rightpad(str, width, char)
    local char = char and char or " "
    local stripped = str

    if #stripped == width then
        return str
    end

    if #stripped > width then
        str = stripped:sub(1, width)
    end

    return str .. string.rep(char, width - #stripped)
end

---Left pads the given string
---@param str string
---@param width number
---@param char? string Defaults to space
---@return string
local function leftpad(str, width, char)
    local char = char and char or " "
    local stripped = stripCodes(str)

    if #stripped == width then
        return str
    end

    if #stripped > width then
        str = stripped:sub(1, width)
    end

    return string.rep(char, width - #stripped) .. str
end

----------------------------------------------------------

--  UI

----------------------------------------------------------

local function printUIString(text)
    local colored = ColoursToANSI("@c" .. text .. "@w")
    AnsiNote(colored)
end

---Prints the header for UI elements
---@param title string
local function header(title)
    local titleStr = "--[ " .. title .. " ]"
    local headerStr = titleStr .. strrepeat("-", 80 - string.len(titleStr))

    printUIString(headerStr)
end

---Prints the footer for UI elements.
local function footer()
    local footerStr = strrepeat("_", 80)

    printUIString(footerStr)
end

---Prints a separator UI elements.
local function separator()
    local sep = strrepeat("-", 80)

    printUIString(sep)
end

---Prints a titled separator for UI elements
---@param title string
local function titledSeparator(title)
    local titleStr = "-- " .. title .. " "
    local headerStr = titleStr .. strrepeat("-", 80 - string.len(titleStr))

    printUIString(headerStr)
end

---Helper function to standardize error printing.
---@param title string
---@param msg string
---@param errorMsg string?
local function reportError(title, msg, errorMsg)
    local guru = "Guru Meditation:"
    local message = "@w" .. msg

    if errorMsg ~= nil then
        message = message .. "\n\n" .. guru .. "\n" .. errorMsg
    end

    local colored = ColoursToANSI("@w" .. message)

    header(title)
    AnsiNote(colored)
    footer()
end

----------------------------------------------------------

--  Configuration

----------------------------------------------------------

local function oDefaultOptions()
    local defaultOptions = {
        version = VERSION,
        actions = {
            ["1"] = {},
            ["2"] = {},
            ["3"] = {},
            ["4"] = {},
            ["5"] = {},
            ["6"] = {},
            ["7"] = {},
            ["8"] = {},
            ["9"] = {},
            ["11"] = {},
            ["12"] = {},
            ["99"] = {}
        },
        meta = {
            ["1"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["2"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["3"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["4"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false,
            },
            ["5"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false,
            },
            ["6"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["7"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["8"] = {
                enabled = true,
                messageEnabled = true,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["9"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["11"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["12"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            },
            ["99"] = {
                enabled = false,
                messageEnabled = false,
                enableMessage = nil,
                disableMessage = nil,
                useCustomMessage = false
            }
        }
    }

    return defaultOptions
end

local function oResetEvents()
    oStatusEvts['aardStatus'] = {
        ["1"] = false,
        ["2"] = false,
        ["3"] = false,
        ["4"] = false,
        ["5"] = false,
        ["6"] = false,
        ["7"] = false,
        ["8"] = false,
        ["9"] = false,
        ["11"] = false,
        ["12"] = false,
        ["99"] = false
    }
end

local function oCheckOptions()
    if oStatusEvts.options.version ~= oDefaultOptions().version then
        Note('StatusEvents: Settings options to default values.')
        oStatusEvts.options = copytable.deep(oDefaultOptions())
    end
end

local function oSaveOptions()
    var.config = serialize.save_simple(oStatusEvts.options)
end

local function oLoadOptions()
    oStatusEvts.options = loadstring(string.format("return %s", var.config or serialize.save_simple(oDefaultOptions())))()
    oCheckOptions()
    oSaveOptions()
end

local function oResetOptions()
    oStatusEvts.options = copytable.deep(oDefaultOptions())
    Note('StatusEvents: Options set to default values.')
    oCheckOptions()
    oSaveOptions()
end

----------------------------------------------------------

--  Core

----------------------------------------------------------

function oSimulate(state, status)
    if oStatusEvts.options.meta[state].enabled and oStatusEvts.options.meta[state].messageEnabled then
        if status then
            if oStatusEvts.options.meta[state].useCustomMessage and oStatusEvts.options.meta[state].enableMessage then
                local styled = ColoursToANSI(oStatusEvts.options.meta[state].enableMessage)
                Simulate(styled .. "\n")
            else
                Simulate('[' .. string.upper(oStatusEvts.aardStatusLabel[state]) .. ' ON' .. ']\n')
            end
        else
            if oStatusEvts.options.meta[state].useCustomMessage and oStatusEvts.options.meta[state].disableMessage then
                local styled = ColoursToANSI(oStatusEvts.options.meta[state].disableMessage)
                Simulate(styled .. "\n")
            else
                Simulate('[' .. string.upper(oStatusEvts.aardStatusLabel[state]) .. ' OFF' .. ']\n')
            end
        end
    end
end

function oExecute(state, phase)
    if oStatusEvts.options.meta[state].enabled then
        for _, action in ipairs(oStatusEvts.options.actions[state]) do
            if action.enabled and action.atStart == phase then
                Execute(action.command)
            end
        end
    end
end

function oSetPKCombat()
    oSimulate("99", true)
    oExecute("99", true)
    oStatusEvts.aardStatus['99'] = true
end

function oStatusEventEmit(state)
    local enabledState = ''

    if not oStatusEvts.aardStatus[state] then
        enabledState = state
    end

    oStatusEvts.aardStatus[state] = true

    for k, _ in pairs(oStatusEvts.aardStatus) do
        if k ~= state then
            if oStatusEvts.aardStatus[k] then
                oSimulate(k, false)
                oExecute(k, false)

                if k == '8' and oStatusEvts.aardStatus["99"] then
                    oSimulate("99", false)
                    oExecute("99", false)
                    oStatusEvts.aardStatus["99"] = false
                end
            end
            oStatusEvts.aardStatus[k] = false
        end
    end

    if #enabledState > 0 then
        oSimulate(enabledState, true)
        oExecute(enabledState, true)
    end
end

---Prints version information.
local function oAbout(args)
    header("About StatusEvents v" .. VERSION)
    titledSeparator("About")
    ColourTell("#ffeeee", "", center("This travesty brought to you by Orphean", 80))
    Note(" ")
    titledSeparator("Basic Usage")

    local ansied = ColoursToANSI(
        "@w\n  Use @gevents list@w to get started - just start clicking on things.\n\n" ..
        "  When you're ready for more detailed help then checkout @gevents help@w and\n  @gevents help overview@w.\n")
    AnsiNote(ansied)
    footer()
end

----------------------------------------------------------

--  Plugin Hooks

----------------------------------------------------------

function OnPluginInstall()
    OnPluginEnable()
    oAbout()
end

function OnPluginEnable()
    OnPluginConnect()
end

function OnPluginConnect()
    oResetEvents()
    oLoadOptions()
    Send_GMCP_Packet("request char")
end

function OnPluginDisconnect()
    oSaveOptions()
end

function OnPluginSaveState()
    oSaveOptions()
end

local gmcpPluginId = "3e7dedbe37e44942dd46d264"
function OnPluginBroadcast(msg, pluginId, name, text)
    if (pluginId == gmcpPluginId) then
        if (text == "char.status") then
            res, value = CallPlugin("3e7dedbe37e44942dd46d264", "gmcpval", "char.status")
            local statusData = loadstring("return " .. value)()

            if (statusData ~= nil) then
                oStatusEventEmit(statusData.state)
            end
        end
    end
end

----------------------------------------------------------

--  Argument Parsing

----------------------------------------------------------

---Parses args into a list of tokens.
---@param args string
---@param noCollapse boolean? If true, consequtive string tokens will not be collapsed into a single token.
---@return Token[]
local function parseArgs(args, noCollapse)
    local tokens = {}

    for chunk in args:gmatch("[^ ]+") do
        local token = {
            value = "",
            type = "string"
        }

        if chunk == "true" or chunk == "false" then
            token.type = "boolean"
            token.value = chunk == "true"
        elseif keywords[chunk] then
            token.type = "keyword"
            token.value = trim(chunk)
        elseif tonumber(chunk) then
            token.type = "number"
            token.value = tonumber(chunk) --[[@as number]]
        else
            token.type = "string"
            token.value = trim(chunk)
        end

        table.insert(tokens, token)
    end

    --Collapses consequtive string tokens into a single token.
    --Probably should have made this happen during the initial
    --tokenization but lazy :(  So we get this post-processing instead.
    if not noCollapse then
        local stringValue = ""
        local newTokens = {}

        for _, token in ipairs(tokens) do
            if token.type ~= "string" then
                if #stringValue > 0 then
                    table.insert(newTokens, {
                        type = "string",
                        value = stringValue
                    })
                    stringValue = ""
                end

                table.insert(newTokens, token)
            else
                if #stringValue > 0 then
                    stringValue = stringValue .. " " .. token.value
                else
                    stringValue = token.value
                end
            end
        end

        -- Make sure to insert any leftover string bits as a token.
        if #stringValue > 0 then
            table.insert(newTokens, {
                type = "string",
                value = stringValue
            })
        end

        tokens = newTokens
    end

    return tokens
end

---Checks tokens against all possible sub-commands.
---Returns matching token list if a valid sub-command is found.
---@param command string
---@param args Token[]
---@return Token[]|nil
local function getCommand(command, args)
    if type(parameters[command]) == "nil" then
        return nil
    end

    local anyFound = false
    for _, format in ipairs(parameters[command]) do
        local matched = true

        for i = 1, #format do
            if type(args[i]) ~= "nil" then
                if format[i].type == "any" then
                    anyFound = true
                end

                if args[i].type ~= format[i].type and not anyFound then
                    matched = false
                    break
                end

                if args[i].type == "keyword" and format[i].value ~= args[i].value then
                    matched = false
                    break
                end
            else
                matched = false
                break
            end
        end

        if matched then
            return format
        end
    end

    return nil
end

---Concatentes a token list to a single string token.
---@param tokens Token[]
---@return Token
local function concatTokens(tokens)
    local result = {
        type = "string",
        value = ""
    }

    for _, token in ipairs(tokens) do
        if type(token.value) == "boolean" then
            token.value = token.value and "true" or "false"
        end

        result.value = result.value .. " " .. token.value
    end

    result.value = trim(result.value)

    return result
end

----------------------------------------------------------

--  Commands

----------------------------------------------------------

---Help
---@param args string?
local function oHelp(args)
    if not args or #args == 0 then
        header("StatusEvents Help")

        titledSeparator("Manage")

        for title, entry in pairsByKeys(helpFiles.Manage) do
            Tell(" ")
            Hyperlink("events help " .. title, leftpad(title, 8), "Help for " .. title, "dodgerblue", "", false, true)
            ColourTell("silver", "", " - " .. entry.command)
            Note("")
            ColourNote("silver", "", "    " .. entry.summary .. "\n")
        end

        titledSeparator("Meta")

        for title, entry in pairsByKeys(helpFiles.Meta) do
            Tell(" ")
            Hyperlink("events help " .. title, leftpad(title, 8), "Help for " .. title, "dodgerblue", "", false, true)
            ColourTell("silver", "", " - " .. entry.command)
            Note("")
            ColourNote("silver", "", "    " .. entry.summary .. "\n")
        end

        footer()
    else
        local entry
        local entryTitle
        local found = false

        for _, articles in pairs(helpFiles) do
            for title, article in pairs(articles) do
                if args and args:lower() == title:lower() then
                    entryTitle = title
                    entry = article
                    found = true
                    break
                end
            end
            if found then
                break
            end
        end

        if not found then
            oHelp()
            return
        end

        header("StatusEvents Help: " .. entryTitle)
        ColourNote("silver", "", " " .. entry.command)
        ColourNote("silver", "", " " .. entry.summary)
        separator()
        ColourNote("silver", "", entry.body)
        footer()
    end
end

local function oEventsList(args)
    local events = {
        ["1"] = "At login screen, no player yet",
        ["2"] = "Player at MOTD or other login sequence",
        ["3"] = "Player fully active and able to receive MUD commands",
        ["4"] = "Player AFK",
        ["5"] = "Player in note",
        ["6"] = "Player in Building/Edit mode",
        ["7"] = "Player at paged output prompt",
        ["8"] = "Player in combat",
        ["9"] = "Player sleeping",
        ["11"] = "Player resting or sitting",
        ["12"] = "Player running",
        ["99"] = "Player in PK combat"
    }

    local headers = rightpad(" Name", 56) .. center("Enabled", 7) .. " Actions"

    header("Events")
    printUIString(headers)
    separator()
    for index, event in pairsByKeys(events) do
        local enabled = oStatusEvts.options.meta[index].enabled and "[X]" or "[ ]"
        local row = rightpad(" " ..
            event, 56) .. center(enabled, 7) .. " "
        ColourTell("#FFEEEE", "", row)
        Hyperlink("events view " .. index, "View", "View Event Details", "white", "", false)
        Tell(" ")
        if oStatusEvts.options.meta[index].enabled then
            Hyperlink("events disable " .. index, "Disable", "Disable Event", "white", "", false)
        else
            Hyperlink("events enable " .. index, "Enable", "Enable Event", "white", "", false)
        end
        Note("")
    end
    footer()
end

local function oEventEnable(index)
    if type(oStatusEvts.options.meta[index]) == "nil" then
        reportError("Invalid Index", "Index does not correspond to an event.")
    else
        oStatusEvts.options.meta[index].enabled = true
        oSaveOptions()
        oEventsList()
    end
end

local function oEventDisable(index)
    if type(oStatusEvts.options.meta[index]) == "nil" then
        reportError("Invalid Index", "Index does not correspond to an event.")
    else
        oStatusEvts.options.meta[index].enabled = false
        oSaveOptions()
        oEventsList()
    end
end

---View a specific Event's details
---@param args Token[]
local function oEventView(args)
    local index = args

    if type(oStatusEvts.options.meta[index]) == "nil" then
        reportError("Invalid Index", "Index does not correspond to an event.")
        return
    end

    local showTrigger = oStatusEvts.options.meta[index].messageEnabled
    local useCustom = oStatusEvts.options.meta[index].useCustomMessage
    local enableMsg = oStatusEvts.options.meta[index].enableMessage
    local disableMsg = oStatusEvts.options.meta[index].disableMessage

    Note(" ")
    header("View Event: " .. string.upper(oStatusEvts.aardStatusLabel[index]) .. " (" .. index .. ")")

    ColourTell("#FFEEEE", "", "  Show Trigger Text: ")
    ColourTell("#ffeeee", "", showTrigger and "Yes " or "No ")
    Hyperlink("events modify " .. index .. " action toggle", "Toggle", "Toggle Trigger Text", "white", "", false)
    Note("")

    if showTrigger then
        ColourTell("#FFEEEE", "", " Use Custom Message: ")
        ColourTell("#ffeeee", "", useCustom and "Yes " or "No ")
        Hyperlink("events modify " .. index .. " action togglecustom", "Toggle", "Toggle Custom Message", "white", "",
            false)
        Note("")

        if useCustom then
            ColourTell("#FFEEEE", "", " Begin Message: ")
            ColourTell('#ffeeee', "", rightpad(enableMsg and enableMsg or "", 59))
            Hyperlink("events modify " .. index .. " action setenable prompt", " Set ", "Set Begin Message", "white", "",
                false)
            Note("")

            ColourTell("#FFEEEE", "", "   End Message: ")
            ColourTell('#ffeeee', "", rightpad(disableMsg and disableMsg or "", 59))
            Hyperlink("events modify " .. index .. " action setdisable prompt", " Set ", "Set End Message", "white", "",
                false)
            Note("")
        end
    end

    separator()
    local headers = rightpad(" Move     Action", 32) .. strrepeat(" ", 30) .. "Actions"
    printUIString(headers)
    separator()

    for i, action in ipairs(oStatusEvts.options.actions[index]) do
        Tell(" ")
        Hyperlink("events modify " .. index .. " action " .. i .. " move up", "/\\", "Move Up", "dodgerblue",
            "",
            false, true)
        Tell("  ")
        Hyperlink("events modify " .. index .. " action " .. i .. " move down", "\\/", "Move Down",
            "dodgerblue",
            "", false, true)
        Tell("  ")

        ColourTell("#FFEEEE", "", rightpad(" " .. action.command, 34) .. " ")

        Hyperlink("events modify " .. index .. " action " .. i .. " edit prompt", "Edit", "Edit Action",
            "#FFEEEE", "", false)
        Tell("  ")

        Hyperlink("events modify " .. index .. " action " .. i .. " toggle", action.enabled and "Disable" or "Enable",
            "Toggle Action",
            "#FFEEEE", "", false)
        Tell("  ")

        Hyperlink("events modify " .. index .. " action " .. i .. " togglephase",
            action.atStart and "Fire at Start" or " Fire at End ",
            "Toggle Phase",
            "#FFEEEE", "", false)
        Tell("  ")

        Hyperlink("events modify " .. index .. " action " .. i .. " remove", "Remove", "Remove Action", "red",
            "",
            false)

        Note("")
    end

    separator()
    Tell(" ")
    Hyperlink("events modify " .. index .. " action new prompt", "Add New Action", "Add New Action", "#FFEEEE", "",
        false)

    Note("")

    footer()
end

local function oEventModify(args, format)
    local eventIndex = args[1].value .. ""
    local subcommand = args[2].value
    local subargs = slice(args, 3, #args)
    local subformat = slice(format, 3, #format)

    if subformat[1].type == "number" then
        local operation = subformat[2].value
        local opparams = slice(subformat, 3, #subformat)

        if operation == "move" then
            if opparams[1].value == "up" and subargs[1].value ~= 1 then
                local index = subargs[1].value --[[@as number]]

                oStatusEvts.options.actions[eventIndex][index], oStatusEvts.options.actions[eventIndex][index - 1] =
                    oStatusEvts.options.actions[eventIndex][index - 1], oStatusEvts.options.actions[eventIndex][index]
                oSaveOptions()
                oEventView(eventIndex)
            end

            if opparams[1].value == "down" and subargs[1].value ~= #(oStatusEvts.options.actions[eventIndex]) then
                local index = subargs[1].value --[[@as number]]

                oStatusEvts.options.actions[eventIndex][index], oStatusEvts.options.actions[eventIndex][index + 1] =
                    oStatusEvts.options.actions[eventIndex][index + 1], oStatusEvts.options.actions[eventIndex][index]
                oSaveOptions()
                oEventView(eventIndex)
            end
        end

        if operation == "edit" then
            if opparams[1].type == "keyword" and opparams[1].value == "prompt" then
                local newAction = utils.inputbox("Please enter new value for action:", "Edit Action",
                    oStatusEvts.options.actions[eventIndex][subargs[1].value].command)

                if newAction and #newAction ~= 0 then
                    oStatusEvts.options.actions[eventIndex][subargs[1].value].command = newAction
                    oSaveOptions()
                    oEventView(eventIndex)
                else
                    reportError("Missing Action Value", "The action value can't be blank!")
                end
            end

            if opparams[1].type == "string" then
                local value = subargs[3].value --[[@as string]]
                oStatusEvts.options.actions[eventIndex][subargs[1].value].command = value
                oSaveOptions()
            end
        end

        if operation == "remove" then
            local response = utils.msgbox("Are you sure you want to remove this action?", "Really remove action?",
                "yesno",
                "!", 2)

            if response ~= "no" then
                local index = subargs[1].value --[[@as number]]
                table.remove(oStatusEvts.options.actions[eventIndex], index)
                oSaveOptions()
                oEventView(eventIndex)
            end
        end

        if operation == "toggle" then
            local index = subargs[1].value --[[@as number]]
            oStatusEvts.options.actions[eventIndex][index].enabled = not oStatusEvts.options.actions[eventIndex][index]
                .enabled
            oSaveOptions()
            oEventView(eventIndex)
        end

        if operation == "togglephase" then
            local index = subargs[1].value --[[@as number]]
            oStatusEvts.options.actions[eventIndex][index].atStart = not oStatusEvts.options.actions[eventIndex][index]
                .atStart
            oSaveOptions()
            oEventView(eventIndex)
        end
    end

    if subformat[1].type == "keyword" and subformat[1].value == "new" then
        if subformat[2].type == "keyword" and subformat[2].value == "prompt" then
            local action = utils.inputbox("Please enter the action to add:", "Add New Action", "", nil, nil)

            if action and #action ~= 0 then
                table.insert(oStatusEvts.options.actions[eventIndex],
                    { command = action, enabled = true, atStart = false })
                oSaveOptions()
                oEventView(eventIndex)
            else
                reportError("Missing Action Value", "The action value can't be blank!")
            end
        end

        if subformat[2].type == "string" then
            local value = subargs[2].value --[[@as string|number]]
            table.insert(oStatusEvts.options.actions[eventIndex], { command = value, enabled = true, atStart = false })
            oSaveOptions()
        end
    end

    if subformat[1].type == "keyword" and subformat[1].value == "toggle" then
        oStatusEvts.options.meta[eventIndex].messageEnabled = not oStatusEvts.options.meta[eventIndex].messageEnabled
        oSaveOptions()
        oEventView(eventIndex)
    end

    if subformat[1].type == "keyword" and subformat[1].value == "togglecustom" then
        oStatusEvts.options.meta[eventIndex].useCustomMessage = not oStatusEvts.options.meta[eventIndex]
            .useCustomMessage
        oSaveOptions()
        oEventView(eventIndex)
    end

    if subformat[1].type == "keyword" and subformat[1].value == "setenable" then
        if subformat[2].type == "keyword" and subformat[2].value == "prompt" then
            local newMsg = utils.inputbox("Please enter new value for the Begin Event Message:",
                "Edit Begin Event Message",
                oStatusEvts.options.meta[eventIndex].enableMessage and
                oStatusEvts.options.meta[eventIndex].enableMessage or "")

            if newMsg and #newMsg ~= 0 then
                oStatusEvts.options.meta[eventIndex].enableMessage = newMsg
                oSaveOptions()
                oEventView(eventIndex)
            else
                reportError("Missing Begin Event Message Value", "The message value can't be blank!")
            end
        end

        if subformat[2].type == "string" then
            local value = subargs[2].value --[[@as string]]
            oStatusEvts.options.meta[eventIndex].enableMessage = value
            oSaveOptions()
        end
    end

    if subformat[1].type == "keyword" and subformat[1].value == "setdisable" then
        if subformat[2].type == "keyword" and subformat[2].value == "prompt" then
            local newMsg = utils.inputbox("Please enter new value for the End Event Message:",
                "Edit End Event Message",
                oStatusEvts.options.meta[eventIndex].disableMessage and
                oStatusEvts.options.meta[eventIndex].disableMessage or "")

            if newMsg and #newMsg ~= 0 then
                oStatusEvts.options.meta[eventIndex].disableMessage = newMsg
                oSaveOptions()
                oEventView(eventIndex)
            else
                reportError("Missing End Event Message Value", "The message value can't be blank!")
            end
        end

        if subformat[2].type == "string" then
            local value = subargs[2].value --[[@as string]]
            oStatusEvts.options.meta[eventIndex].disableMessage = value
            oSaveOptions()
        end
    end
end

----------------------------------------------------------

--  Entry Point

----------------------------------------------------------

---Parses input from Mushclient and dispatches commands.
---@param raw string[] The unparsed arguments from mush.
function oStatusEventsDispatch(_, _, raw)
    local args = raw[#raw]
    local command = head(args)
    local commandArgs = body(args)
    local dispatch = {
        about = oAbout,
        list = oEventsList,
        enable = oEventEnable,
        disable = oEventDisable,
        view = oEventView,
        modify = oEventModify,
        reset = oResetOptions
    }

    local method = dispatch[command] or oHelp

    if type(dispatch[command]) ~= "nil" and
        type(parameters[command]) ~= "nil" then
        local parsed = parseArgs(commandArgs)
        local format = getCommand(command, parsed)

        if type(format) == "nil" then
            oHelp(command)
        else
            if format[1].type == "any" then
                parsed = { concatTokens(parsed) }
            end

            method(parsed, format)
        end
    else
        method(commandArgs)
    end
end
