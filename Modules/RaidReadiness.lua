-- GuildMasterTools Modules/RaidReadiness.lua
-- Tracks which guild members are ready for raid (gear, consumables, etc.)

local READY_COLOR   = "ff00ff98"
local UNREADY_COLOR = "ffff4444"
local WARN_COLOR    = "ffcf9030"

local ILVL_THRESHOLDS = {
    Heroic  = 610,
    Normal  = 580,
    LFR     = 545,
}

local function buildRaidReadinessPanel(panel)
    local C = GMT.C

    GMT_SectionHeader(panel, "Raid Readiness", -4)

    -- Threshold display
    local thHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    thHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    thHdr:SetText("|cff" .. C.gold .. "iLvl Thresholds|r")

    local yOff = -56
    for tier, ilvl in pairs(ILVL_THRESHOLDS) do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, yOff)
        fs:SetText(tier .. ":  |cff" .. C.white .. tostring(ilvl) .. "+|r")
        yOff = yOff - 18
    end

    -- Column headers
    local function colHdr(text, x, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Name",  8,   yOff - 10)
    colHdr("iLvl",  200, yOff - 10)
    colHdr("Ready", 300, yOff - 10)

    local listTopY = yOff - 28

    local divider = panel:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, listTopY + 2)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, listTopY + 2)
    divider:SetHeight(1)
    GMT.SetBGColor(divider, C.border)

    -- Rows
    panel._rrRows = {}

    local function getRow(i)
        if not panel._rrRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0,
                         listTopY - (i-1) * GMT.L.rowH)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            row._name  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._name:SetPoint("LEFT", row, "LEFT", 8, 0)

            row._ilvl  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._ilvl:SetPoint("LEFT", row, "LEFT", 200, 0)

            row._ready = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._ready:SetPoint("LEFT", row, "LEFT", 300, 0)

            panel._rrRows[i] = row
        end
        return panel._rrRows[i]
    end

    local function refresh()
        local roster = GMT_DB.raidRoster or {}
        local n = #roster
        for i, member in ipairs(roster) do
            local row  = getRow(i)
            local ilvl = member.ilvl or 0
            local ready = ilvl >= ILVL_THRESHOLDS.Normal
            local col   = ready and READY_COLOR or UNREADY_COLOR

            row._name:SetText(member.name or "?")
            row._ilvl:SetText(tostring(ilvl))
            row._ready:SetText("|cff" .. col .. (ready and "Ready" or "Not Ready") .. "|r")
            row:Show()
        end
        for i = n+1, #panel._rrRows do
            panel._rrRows[i]:Hide()
        end
    end

    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(100, GMT.L.btnH)
    refreshBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        local ok, err = pcall(refresh)
        if not ok then GMT.Err("RaidReadiness refresh: " .. tostring(err)) end
    end)

    refresh()
    panel._refresh = refresh
end

function GMT_RaidReadiness_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("RaidReadiness")
        if not panel or panel._rrBuilt then return end
        panel._rrBuilt = true
        buildRaidReadinessPanel(panel)
    end)
    if not ok then GMT.Err("RaidReadiness init: " .. tostring(err)) end
end

GMT.RegisterModule("RaidReadiness", GMT_RaidReadiness_Init)
