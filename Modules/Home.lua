-- GuildMasterTools Modules/Home.lua
-- Dashboard / welcome panel

local LOGO_PATH = "Interface/AddOns/GuildMasterTools/Media/logo"

local function buildHomePanel(panel)
    local C = GMT.C
    local F = GMT.F

    -- Logo (optional – silently skipped if texture missing)
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    logo:SetTexture(LOGO_PATH)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts/FRIZQT__.TTF", F.header, "OUTLINE")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -4)
    title:SetText(
        "|cff" .. C.gold  .. "Guild" ..
        "|cff" .. C.green .. "Master" ..
        "|r Tools")

    local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    ver:SetText("|cff" .. C.grey .. "v" .. GMT.VERSION .. "  — Rustbolt Goblin Engineering Division|r")

    -- Divider
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -82)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -82)
    div:SetHeight(1)
    GMT.SetBGColor(div, GMT.C.border)

    -- Quick-stats section
    local statsHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -96)
    statsHdr:SetText("|cff" .. C.gold .. "Guild at a Glance|r")

    local function statRow(label, valueFn, yOff)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, yOff)
        lbl:SetText(label .. ":")
        lbl:SetTextColor(0.8, 0.7, 0.4)

        local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        val:SetText("—")

        -- store refresh function on the panel for later update
        panel._statRefresh = panel._statRefresh or {}
        table.insert(panel._statRefresh, function()
            local ok, result = pcall(valueFn)
            val:SetText(ok and tostring(result) or "—")
        end)
    end

    statRow("Total Members",   function()
        return GetNumGuildMembers() or 0
    end, -120)

    statRow("Online Now", function()
        local _, online = GetNumGuildMembers()
        return online or 0
    end, -140)

    statRow("Applicants Pending", function()
        return #(GMT.DB("applicants") or {})
    end, -160)

    statRow("Events Scheduled", function()
        return #(GMT.DB("events") or {})
    end, -180)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(100, GMT.L.btnH)
    refreshBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -210)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        if panel._statRefresh then
            for _, fn in ipairs(panel._statRefresh) do fn() end
        end
    end)
end

function GMT_Home_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Home")
        if not panel or panel._homeBuilt then return end
        panel._homeBuilt = true
        buildHomePanel(panel)
    end)
    if not ok then GMT.Err("Home init: " .. tostring(err)) end
end

GMT.RegisterModule("Home", GMT_Home_Init)
