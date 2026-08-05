-- ============================================================================
-- db/exportimport.lua (OpenHeal)
-- Profile serialisation to and from a shareable string.
--
-- WHY:
--   Two reasons, and the second is the important one:
--     1. Sharing a setup with someone.
--     2. Backing up before a patch. Every expansion cycle someone loses a
--        carefully tuned layout to a SavedVariables corruption or a bad
--        migration, and there is no way back.
--
-- FORMAT:
--   "OH1:" .. base64(serialised table)
--
--   No compression: LibDeflate is not embedded (nothing else here needs a lib
--   folder, and an unmaintained embedded copy is worse than a long string).
--   Strings run a few KB, which pastes fine in Discord and in the import box.
--
-- SAFETY:
--   The decoder is a hand-written parser, NOT loadstring(). An imported profile
--   string is untrusted input; running it as code would let anyone who hands
--   you a string execute anything in your UI. It only ever produces tables,
--   numbers, strings and booleans.
-- ============================================================================

local ADDON, ns = ...
ns = _G[ADDON] or ns or {}
_G[ADDON] = ns

ns.Transfer = ns.Transfer or {}
local X = ns.Transfer

local type    = type
local pairs   = pairs
local ipairs  = ipairs
local tostring = tostring
local tonumber = tonumber
local format  = string.format
local concat  = table.concat
local byte    = string.byte
local char    = string.char
local sub     = string.sub
local gsub    = string.gsub
local floor   = math.floor

local PREFIX = "OH1:"

-- ---------------------------------------------------------------------------
-- Serialise
-- ---------------------------------------------------------------------------
local function EscapeString(s)
    s = gsub(s, "\\", "\\\\")
    s = gsub(s, '"', '\\"')
    s = gsub(s, "\n", "\\n")
    s = gsub(s, "\r", "\\r")
    return s
end

local function SerializeValue(v, out, depth)
    if depth > 20 then
        out[#out + 1] = "nil"
        return
    end

    local t = type(v)

    if t == "number" then
        -- %.14g round-trips a double without dragging in float noise.
        out[#out + 1] = format("%.14g", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "string" then
        out[#out + 1] = '"' .. EscapeString(v) .. '"'
    elseif t == "table" then
        out[#out + 1] = "{"
        local first = true

        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "string" or kt == "number" then
                local vt = type(val)
                if vt == "number" or vt == "boolean" or vt == "string" or vt == "table" then
                    if not first then out[#out + 1] = "," end
                    first = false

                    if kt == "number" then
                        out[#out + 1] = "[" .. format("%.14g", k) .. "]="
                    else
                        out[#out + 1] = "[" .. '"' .. EscapeString(k) .. '"' .. "]="
                    end

                    SerializeValue(val, out, depth + 1)
                end
            end
        end

        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

function X:Serialize(tbl)
    local out = {}
    SerializeValue(tbl, out, 0)
    return concat(out)
end

-- ---------------------------------------------------------------------------
-- Parse (hand-written; never loadstring)
-- ---------------------------------------------------------------------------
local function ParseError(pos, msg)
    return nil, format("parse error at %d: %s", pos, msg)
end

local ParseValue

local function SkipSpace(s, i)
    while i <= #s do
        local c = sub(s, i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end

local function ParseString(s, i)
    -- assumes s[i] == '"'
    i = i + 1
    local buf = {}

    while i <= #s do
        local c = sub(s, i, i)

        if c == '"' then
            return concat(buf), i + 1
        elseif c == "\\" then
            local n = sub(s, i + 1, i + 1)
            if n == "n" then buf[#buf + 1] = "\n"
            elseif n == "r" then buf[#buf + 1] = "\r"
            elseif n == "\\" then buf[#buf + 1] = "\\"
            elseif n == '"' then buf[#buf + 1] = '"'
            else buf[#buf + 1] = n end
            i = i + 2
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end

    return nil, i
end

local function ParseNumber(s, i)
    local start = i
    while i <= #s do
        local c = sub(s, i, i)
        if c:match("[%d%.%-%+eExXaAbBcCdDfF]") then
            i = i + 1
        else
            break
        end
    end
    local n = tonumber(sub(s, start, i - 1))
    return n, i
end

local function ParseTable(s, i)
    -- assumes s[i] == '{'
    i = i + 1
    local t = {}

    while true do
        i = SkipSpace(s, i)
        if i > #s then return ParseError(i, "unterminated table") end

        local c = sub(s, i, i)
        if c == "}" then
            return t, i + 1
        end

        if c == "," then
            i = i + 1
        elseif c == "[" then
            i = i + 1
            i = SkipSpace(s, i)

            local key
            local kc = sub(s, i, i)
            if kc == '"' then
                key, i = ParseString(s, i)
                if key == nil then return ParseError(i, "bad string key") end
            else
                key, i = ParseNumber(s, i)
                if key == nil then return ParseError(i, "bad numeric key") end
            end

            i = SkipSpace(s, i)
            if sub(s, i, i) ~= "]" then return ParseError(i, "expected ]") end
            i = i + 1

            i = SkipSpace(s, i)
            if sub(s, i, i) ~= "=" then return ParseError(i, "expected =") end
            i = i + 1

            local val
            val, i = ParseValue(s, i)
            if i == nil then return ParseError(0, "bad value") end

            t[key] = val
        else
            return ParseError(i, "unexpected '" .. c .. "'")
        end
    end
end

ParseValue = function(s, i)
    i = SkipSpace(s, i)
    if i > #s then return nil, nil end

    local c = sub(s, i, i)

    if c == "{" then
        return ParseTable(s, i)
    elseif c == '"' then
        local v
        v, i = ParseString(s, i)
        return v, i
    elseif sub(s, i, i + 3) == "true" then
        return true, i + 4
    elseif sub(s, i, i + 4) == "false" then
        return false, i + 5
    elseif sub(s, i, i + 2) == "nil" then
        return nil, i + 3
    else
        local v
        v, i = ParseNumber(s, i)
        return v, i
    end
end

function X:Deserialize(str)
    if type(str) ~= "string" then return nil, "not a string" end
    local v, i = ParseValue(str, 1)
    if i == nil then return nil, "malformed data" end
    if type(v) ~= "table" then return nil, "payload is not a table" end
    return v
end

-- ---------------------------------------------------------------------------
-- Base64
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_DEC = {}
for i = 1, #B64 do
    B64_DEC[sub(B64, i, i)] = i - 1
end

local function Encode64(data)
    local out = {}
    local n = #data
    local i = 1

    while i + 2 <= n do
        local a, b, c = byte(data, i, i + 2)
        local v = a * 65536 + b * 256 + c
        out[#out + 1] = sub(B64, floor(v / 262144) + 1, floor(v / 262144) + 1)
        out[#out + 1] = sub(B64, floor(v / 4096) % 64 + 1, floor(v / 4096) % 64 + 1)
        out[#out + 1] = sub(B64, floor(v / 64) % 64 + 1, floor(v / 64) % 64 + 1)
        out[#out + 1] = sub(B64, v % 64 + 1, v % 64 + 1)
        i = i + 3
    end

    local rem = n - i + 1
    if rem == 1 then
        local a = byte(data, i)
        local v = a * 65536
        out[#out + 1] = sub(B64, floor(v / 262144) + 1, floor(v / 262144) + 1)
        out[#out + 1] = sub(B64, floor(v / 4096) % 64 + 1, floor(v / 4096) % 64 + 1)
        out[#out + 1] = "=="
    elseif rem == 2 then
        local a, b = byte(data, i, i + 1)
        local v = a * 65536 + b * 256
        out[#out + 1] = sub(B64, floor(v / 262144) + 1, floor(v / 262144) + 1)
        out[#out + 1] = sub(B64, floor(v / 4096) % 64 + 1, floor(v / 4096) % 64 + 1)
        out[#out + 1] = sub(B64, floor(v / 64) % 64 + 1, floor(v / 64) % 64 + 1)
        out[#out + 1] = "="
    end

    return concat(out)
end

local function Decode64(data)
    data = gsub(data, "[^A-Za-z0-9%+/=]", "")

    local out = {}
    local i = 1

    while i + 3 <= #data do
        local c1, c2, c3, c4 = sub(data, i, i), sub(data, i + 1, i + 1), sub(data, i + 2, i + 2), sub(data, i + 3, i + 3)

        local n1, n2 = B64_DEC[c1], B64_DEC[c2]
        if not n1 or not n2 then return nil end

        local n3 = B64_DEC[c3]
        local n4 = B64_DEC[c4]

        local v = n1 * 262144 + n2 * 4096 + (n3 or 0) * 64 + (n4 or 0)

        out[#out + 1] = char(floor(v / 65536) % 256)
        if c3 ~= "=" then out[#out + 1] = char(floor(v / 256) % 256) end
        if c4 ~= "=" then out[#out + 1] = char(v % 256) end

        i = i + 4
    end

    return concat(out)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function X:ExportProfile(profileName)
    local gdb = ns:GetGlobalDB()
    profileName = profileName or ns:GetActiveProfileKey()

    local src = gdb.profiles and gdb.profiles[profileName]
    if type(src) ~= "table" then
        return nil, "no such profile: " .. tostring(profileName)
    end

    local payload = {
        v = 1,
        name = profileName,
        addon = "OpenHeal",
        data = src,
    }

    return PREFIX .. Encode64(self:Serialize(payload))
end

-- Returns profileName, payloadTable, err
function X:DecodeProfile(str)
    if type(str) ~= "string" then return nil, nil, "empty string" end

    str = gsub(str, "^%s+", "")
    str = gsub(str, "%s+$", "")

    if sub(str, 1, #PREFIX) ~= PREFIX then
        return nil, nil, "not an OpenHeal profile string (missing " .. PREFIX .. " prefix)"
    end

    local raw = Decode64(sub(str, #PREFIX + 1))
    if not raw or raw == "" then
        return nil, nil, "could not decode - string is truncated or corrupted"
    end

    local payload, err = self:Deserialize(raw)
    if not payload then
        return nil, nil, err or "could not parse"
    end

    if type(payload.data) ~= "table" then
        return nil, nil, "no profile data in string"
    end

    return payload.name or "Imported", payload, nil
end

-- Returns ok, errOrName
function X:ImportProfile(str, targetName, overwrite)
    local name, payload, err = self:DecodeProfile(str)
    if not name then return false, err end

    targetName = targetName or name
    if ns.DB and ns.DB._NormalizeProfileName then
        targetName = ns.DB._NormalizeProfileName(targetName) or name
    end

    local gdb = ns:GetGlobalDB()
    gdb.profiles = gdb.profiles or {}

    if gdb.profiles[targetName] and not overwrite then
        return false, "a profile named '" .. targetName .. "' already exists"
    end

    -- Deep copy so the imported table is not shared with the decoder's output.
    local function DeepCopy(src)
        local t = {}
        for k, v in pairs(src) do
            if type(v) == "table" then t[k] = DeepCopy(v) else t[k] = v end
        end
        return t
    end

    gdb.profiles[targetName] = DeepCopy(payload.data)

    -- Fill in anything the source profile was missing (older export, new keys).
    if ns.Profile and ns.Profile.EnsureProfile then
        ns.Profile:EnsureProfile(targetName)
    end

    if ns.InvalidateProfileCache then ns:InvalidateProfileCache() end

    return true, targetName
end
