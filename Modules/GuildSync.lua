-- GuildMasterTools Modules/GuildSync.lua
-- Sync guild data across online officer characters via addon messages

local SYNC_VERSION = 1
local SYNC_CHANNEL = "GUILD"

-- ── Outgoing ──────────────────────────────────────────────────────────────
local function sendSync(dataType, payload)
    if not C_ChatInfo then
        GMT.Err("GuildSync: C_ChatInfo unavailable.")
        return
    end
    local msg = string.format("GMTSYNC:%d:%s:%s",
        SYNC_VERSION, dataType, tostring(payload or ""))
    local ok, err = pcall(C_ChatInfo.SendAddonMessage,
                          GMT.PREFIX, msg, SYNC_CHANNEL)
    if not ok then
        GMT.Err("GuildSync send failed: " .. tostring(err))
    end
end

-- ── Incoming ──────────────────────────────────────────────────────────────
local function handleSyncMessage(prefix, message, channel, sender)
    if prefix ~= GMT.PREFIX then return end
    local ver, dtype, payload = message:match("^GMTSYNC:(%d+):([^:]+):(.*)")
    if not ver then return end
    if tonumber(ver) ~= SYNC_VERSION then
        GMT.Err("GuildSync: version mismatch from " .. tostring(sender))
        return
    end
    -- Basic ack / logging — extend per data type as needed
    GMT.Print("GuildSync received '" .. dtype .. "' from " ..
              (sender or "?") .. ".")
    GMT_DB.sync.lastSync = time()
end

-- ── Panel ─────────────────────────────────────────────────────────────────
local function buildGuildSyncPanel(panel)
    local C = GMT.C

    GMT_SectionHeader(panel, "Guild Sync", -4)

    -- Status
    local statusLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
    statusLbl:SetText("|cff" .. C.gold .. "Status:|r")

    local statusVal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusVal:SetPoint("LEFT", statusLbl, "RIGHT", 8, 0)

    local function refreshStatus()
        local last = GMT_DB.sync.lastSync or 0
        if last == 0 then
            statusVal:SetText("|cff" .. C.grey .. "Never synced.|r")
        else
            statusVal:SetText("|cff" .. C.green ..
                              "Last sync: " .. date("%Y-%m-%d %H:%M", last) .. "|r")
        end
    end
    refreshStatus()

    -- Broadcast button
    local broadcastBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    broadcastBtn:SetSize(130, GMT.L.btnH)
    broadcastBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -60)
    broadcastBtn:SetText("Broadcast Status")
    broadcastBtn:SetScript("OnClick", function()
        local ok, err = pcall(function()
            sendSync("STATUS", "online:" .. (UnitName("player") or "?"))
            refreshStatus()
        end)
        if not ok then GMT.Err("GuildSync broadcast: " .. tostring(err)) end
    end)

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -100)
    desc:SetWidth(panel:GetWidth() - 16)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetText(
        "|cff" .. C.grey ..
        "Guild Sync uses addon messages to keep officer data in sync across " ..
        "online characters. Press 'Broadcast Status' to announce your presence " ..
        "and trigger a sync handshake with other GMT users in the guild.|r")

    -- Register for incoming messages
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
        local ok, err = pcall(handleSyncMessage, prefix, message, channel, sender)
        if not ok then
            GMT.Err("GuildSync message handler: " .. tostring(err))
        end
        refreshStatus()
    end)

    panel._refresh = refreshStatus
end

function GMT_GuildSync_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("GuildSync")
        if not panel or panel._syncBuilt then return end
        panel._syncBuilt = true
        buildGuildSyncPanel(panel)
    end)
    if not ok then GMT.Err("GuildSync init: " .. tostring(err)) end
end

GMT.RegisterModule("GuildSync", GMT_GuildSync_Init)
