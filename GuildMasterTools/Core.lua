-- ============================================================
-- GuildMaster Tools  |  Core.lua  |  v2.0.0
-- Addon table   SavedVars   Events   Slash cmds   Comm
-- ============================================================
local addonName, GMT = ...

--    Version & identity                                       
GMT.VERSION = "4.3.0"
GMT.PREFIX  = "GMT2"
GMT.CONFIG_VERSION = 2
GMT.DEBUG   = false

--    Print helpers                                            
local tag = "|cffcf9030[GMT]|r "

function GMT.Print(msg)  print(tag .. tostring(msg)) end
function GMT.Warn(msg)   print("|cffffaa00[GMT]|r "  .. tostring(msg)) end
function GMT.Err(msg)    print("|cffff4444[GMT ERR]|r " .. tostring(msg)) end
function GMT.Debug(msg)
    if GMT.DEBUG then print("|cff888888[GMT dbg]|r " .. tostring(msg)) end
end

function GMT.SafeReload()
    if InCombatLockdown and InCombatLockdown() then
        GMT.Warn("Cannot reload UI during combat.")
        return false
    end

    local ok = false

    if type(C_UI) == "table" and type(C_UI.Reload) == "function" then
        ok = pcall(C_UI.Reload)
        if ok then return true end
    end

    if type(ReloadUI) == "function" then
        ok = pcall(ReloadUI)
        if ok then return true end
    end

    if type(RunMacroText) == "function" then
        ok = pcall(RunMacroText, "/reload")
        if ok then return true end
    end

    GMT.Err("Reload is unavailable in this client state.")
    return false
end

function GMT.ReloadNow(msg)
    if msg and msg ~= "" then GMT.Print(msg) end
    return GMT.SafeReload()
end

function GMT.PlayerGuildRankIndex()
    if type(GetGuildInfo) ~= "function" then return 99 end
    local _, _, idx = GetGuildInfo("player")
    return tonumber(idx) or 99
end

function GMT.IsOfficer()
    return GMT.PlayerGuildRankIndex() <= 1
end

function GMT.IsWhitelisted(name)
    local db = GMT.DB and GMT.DB.settings and GMT.DB.settings.access
    local wl = db and db.whitelist or nil
    if type(wl) ~= "table" then return false end
    local short = GMT.Short(name or (UnitName and UnitName("player")) or "")
    return short and wl[short] and true or false
end

function GMT.CanAccessTab(tabKey)
    local s = GMT.DB and GMT.DB.settings or nil
    local access = s and s.access or nil
    if not access then return true end
    if GMT.IsWhitelisted() then return true end
    local tabs = access.tabs or {}
    local maxRank = tonumber(tabs[tabKey]) or 99
    return GMT.PlayerGuildRankIndex() <= maxRank
end

function GMT.NormalizeWhitelist()
    local access = GMT.DB.settings.access
    access.whitelist = access.whitelist or {}
    local clean = {}
    for k,v in pairs(access.whitelist) do
        if v then clean[GMT.Short(k)] = true end
    end
    access.whitelist = clean
end


--    SavedVariables default schema                            
local DEFAULTS = {
    version  = GMT.VERSION,
    settings = {
        debug = false,
        defaultTab = "Home",
        autoCombatLog = false,
        minimap = { hide = false, angle = 220 },
        access = {
            whitelist = {},
            tabs = {
                ["Home"] = 99, ["Members"] = 99, ["Recruitment"] = 2, ["Raid Prep"] = 99,
                ["Crafting"] = 99, ["Logistics"] = 99, ["Economy"] = 2, ["Raid Perf"] = 2,
                ["Events"] = 99, ["Guild Sync"] = 1, ["Settings"] = 1,
            },
        },
    },
    recruits = {},
    logistics = { gatherers={}, crafters={}, supply={} },
    raidReadiness = { checks={} },
    economy = {
        bankLog     = {},
        goldLog     = {},
        contribs    = {},
        lastScan    = 0,
    },
}

local function ApplyDefaults(t, d)
    for k, v in pairs(d) do
        if t[k] == nil then
            t[k] = (type(v) == "table") and {} or v
        end
        if type(v) == "table" then ApplyDefaults(t[k], v) end
    end
end

--    Comm                                                     
local commCallbacks = {}

function GMT.RegComm(kind, fn)   commCallbacks[kind] = fn end
function GMT.SendComm(kind, data, channel, target)
    local msg = kind .. ":" .. (data or "")
    local ok
    if channel == "WHISPER" and target then
        ok = C_ChatInfo.SendAddonMessage(GMT.PREFIX, msg, "WHISPER", target)
    else
        ok = C_ChatInfo.SendAddonMessage(GMT.PREFIX, msg, channel or "GUILD")
    end
    if not ok then GMT.Debug("SendComm failed: " .. kind) end
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(_, _, pfx, msg, ch, sender)
    if pfx ~= GMT.PREFIX then return end
    local kind, payload = msg:match("^(%w+):(.*)$")
    if kind and commCallbacks[kind] then commCallbacks[kind](payload, sender, ch) end
end)

--    Main event frame                                         
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")

f:SetScript("OnEvent", function(_, event, arg1)

    if event == "ADDON_LOADED" and arg1 == addonName then
        -- SavedVars
        GMT_DB   = GMT_DB   or {}
        GMT_CharDB = GMT_CharDB or {}
        ApplyDefaults(GMT_DB, DEFAULTS)
        GMT.DB     = GMT_DB
        GMT.CharDB = GMT_CharDB
        GMT.DEBUG  = GMT.DB.settings.debug
        GMT.NormalizeWhitelist()
        GMT.DB.configVersion = GMT.DB.configVersion or GMT.CONFIG_VERSION
        GMT.Debug("SavedVars loaded v" .. GMT.DB.version)

    elseif event == "PLAYER_LOGIN" then
        -- Comm prefix
        C_ChatInfo.RegisterAddonMessagePrefix(GMT.PREFIX)

        -- Build UI then init every module
        if GMT_BuildUI then
            GMT_BuildUI()
        else
            GMT.Err("UI builder missing. Check UI.lua load order.")
            return
        end

        if GMT_Home_Init then GMT_Home_Init() end
        if GMT_Members_Init then GMT_Members_Init() end
        if GMT_Recruitment_Init then GMT_Recruitment_Init() end
        if GMT_RaidReadiness_Init then GMT_RaidReadiness_Init() end
        if GMT_TalentMap_Init then GMT_TalentMap_Init() end
        if GMT_Logistics_Init then GMT_Logistics_Init() end
        if GMT_Economy_Init then GMT_Economy_Init() end
        if GMT_RaidPerf_Init then GMT_RaidPerf_Init() end
        if GMT_Events_Init then GMT_Events_Init() end
        if GMT_GuildTools_Init then GMT_GuildTools_Init() end
        if GMT_GuildSync_Init then GMT_GuildSync_Init() end
        if GMT_CombatLog_Init then GMT_CombatLog_Init() end
        if GMT_Minimap_Init then GMT_Minimap_Init() end
        if GMT_Options_Init then GMT_Options_Init() end

        GMT.Print("v" .. GMT.VERSION .. " loaded.  |cffffffff/gmt|r to open.")
        if GMT.DB and GMT.DB.settings and GMT.DB.settings.openOnLogin and GMT_MainFrame then
            GMT_MainFrame:Show()
        end

    elseif event == "PLAYER_LOGOUT" then
        GMT.Debug("Logout   data saved.")
    end
end)

--    Slash commands                                           
SLASH_GMT1 = "/gmt"
SLASH_GMT2 = "/guildmaster"

SlashCmdList["GMT"] = function(raw)
    local cmd = (raw or ""):lower():match("^%s*(.-)%s*$")

    if cmd == "" or cmd == "show" then
        if not GMT_MainFrame and GMT_BuildUI then GMT_BuildUI() end
        if GMT_MainFrame then GMT_MainFrame:Show() end
    elseif cmd == "hide" then
        if GMT_MainFrame then GMT_MainFrame:Hide() end
    elseif cmd == "toggle" then
        if not GMT_MainFrame and GMT_BuildUI then GMT_BuildUI() end
        if GMT_MainFrame and GMT_MainFrame:IsShown() then GMT_MainFrame:Hide()
        elseif GMT_MainFrame then GMT_MainFrame:Show() end
    elseif cmd == "debug" then
        GMT.DEBUG = not GMT.DEBUG
        GMT.DB.settings.debug = GMT.DEBUG
        GMT.Print("Debug: " .. (GMT.DEBUG and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    elseif cmd == "reset" then
        GMT_DB = nil
        GMT.Print("Resetting in 1 second ")
        C_Timer.After(1, function() GMT.ReloadNow() end)
    elseif cmd == "version" then
        GMT.Print("Version " .. GMT.VERSION)
    elseif cmd == "reload" then
        GMT.ReloadNow("Reloading UI...")
    else
        GMT.Print("/gmt  |  /gmt toggle  |  /gmt debug  |  /gmt reset  |  /gmt reload")
    end
end
