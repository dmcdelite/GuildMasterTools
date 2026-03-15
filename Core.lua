-- GuildMasterTools Core.lua
-- Version: 4.2.0

GMT = GMT or {}
GMT.VERSION = "4.2.0"
GMT.PREFIX  = "GMTWA"

-- ── Saved-variable defaults ────────────────────────────────────────────────
local DB_DEFAULTS = {
    members     = {},
    applicants  = {},
    raidRoster  = {},
    economy     = { log = {}, bankGold = 0 },
    events      = {},
    logistics   = { supplies = {}, requests = {} },
    sync        = { lastSync = 0 },
    options     = {
        theme           = "dark",
        showMinimapBtn  = true,
        alertRankDrop   = true,
    },
}

-- ── Utility helpers ────────────────────────────────────────────────────────
function GMT.Print(msg)
    print("|cffcf9030GMT|r " .. tostring(msg))
end

function GMT.Err(msg)
    print("|cffff4444GMT ERROR|r " .. tostring(msg))
end

-- Deep-copy a table (used for defaults)
local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = deepCopy(v) end
    return copy
end

-- Merge defaults into dst without overwriting existing keys
local function applyDefaults(dst, defaults)
    for k, v in pairs(defaults) do
        if dst[k] == nil then
            dst[k] = deepCopy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" then
            applyDefaults(dst[k], v)
        end
    end
end

-- ── Database accessor ──────────────────────────────────────────────────────
function GMT.DB(path)
    if type(path) ~= "string" then return GMT_DB end
    local node = GMT_DB
    for key in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

-- ── Module registry ────────────────────────────────────────────────────────
GMT.modules = {}

function GMT.RegisterModule(name, initFn)
    if type(name) ~= "string" or type(initFn) ~= "function" then
        GMT.Err("RegisterModule: invalid arguments for '" .. tostring(name) .. "'")
        return
    end
    GMT.modules[name] = initFn
end

-- ── Event frame ───────────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame", "GMT_EventFrame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= "GuildMasterTools" then return end

        -- Initialise / migrate saved variables
        if type(GMT_DB) ~= "table" then GMT_DB = {} end
        applyDefaults(GMT_DB, DB_DEFAULTS)

    elseif event == "PLAYER_LOGIN" then
        -- Register comm prefix
        local ok, err = pcall(C_ChatInfo.RegisterAddonMessagePrefix, GMT.PREFIX)
        if not ok then
            GMT.Err("Failed to register addon prefix: " .. tostring(err))
        end

        -- Build main UI
        if type(GMT_BuildUI) == "function" then
            local uiOk, uiErr = pcall(GMT_BuildUI)
            if not uiOk then
                GMT.Err("UI build failed: " .. tostring(uiErr))
                return
            end
        else
            GMT.Err("GMT_BuildUI not found — check UI.lua load order.")
            return
        end

        -- Initialise modules in dependency order
        local initOrder = {
            "Home", "Members", "Recruitment",
            "RaidReadiness", "RaidPerf", "TalentMap",
            "Logistics", "Economy", "Events",
            "GuildSync", "Options",
        }
        for _, name in ipairs(initOrder) do
            local fn = GMT.modules[name]
            if type(fn) == "function" then
                local mOk, mErr = pcall(fn)
                if not mOk then
                    GMT.Err(name .. " init failed: " .. tostring(mErr))
                end
            end
        end

        GMT.Print("v" .. GMT.VERSION .. " loaded.  |cffffffff/gmt|r to open.")
    end
end)

-- ── Slash commands ─────────────────────────────────────────────────────────
SLASH_GMT1 = "/gmt"
SlashCmdList["GMT"] = function(raw)
    local cmd = (raw or ""):lower():match("^%s*(.-)%s*$")

    if not GMT_MainFrame then
        GMT.Err("UI not ready yet.")
        return
    end

    if cmd == "" or cmd == "show" then
        GMT_MainFrame:Show()
    elseif cmd == "hide" then
        GMT_MainFrame:Hide()
    elseif cmd == "toggle" then
        if GMT_MainFrame:IsShown() then
            GMT_MainFrame:Hide()
        else
            GMT_MainFrame:Show()
        end
    elseif cmd == "version" then
        GMT.Print("Version " .. GMT.VERSION)
    elseif cmd == "reset" then
        GMT_DB = {}
        GMT.Print("Saved variables reset. |cffffffffReload UI to apply.|r")
    elseif cmd == "help" then
        GMT.Print("Commands: show | hide | toggle | version | reset | help")
    else
        GMT.Print("Unknown command '" .. cmd .. "'. Type |cffffffff/gmt help|r.")
    end
end
