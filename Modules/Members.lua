-- GuildMasterTools Modules/Members.lua
-- Guild member roster with rank, class and note display

local COL = { NAME=0, RANK=180, CLASS=310, LEVEL=430, NOTE=490 }
local ROW_H = GMT.L.rowH

local function classColor(className)
    local info = RAID_CLASS_COLORS and RAID_CLASS_COLORS[className:upper()]
    if info then
        return string.format("%02x%02x%02x",
            math.floor(info.r * 255),
            math.floor(info.g * 255),
            math.floor(info.b * 255))
    end
    return GMT.C.white
end

local function buildMembersPanel(panel)
    local C = GMT.C

    -- Column headers
    local function hdr(label, x)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
        fs:SetText("|cff" .. C.gold .. label .. "|r")
    end
    hdr("Name",   COL.NAME)
    hdr("Rank",   COL.RANK)
    hdr("Class",  COL.CLASS)
    hdr("Level",  COL.LEVEL)
    hdr("Note",   COL.NOTE)

    -- Divider
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -18)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -18)
    div:SetHeight(1)
    GMT.SetBGColor(div, GMT.C.border)

    -- Row pool
    panel._rows    = {}
    panel._rowPool = {}

    local function getRow(idx)
        if not panel._rows[idx] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), ROW_H)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(20 + (idx-1) * ROW_H))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if idx % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            row._name  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._name:SetPoint("LEFT", row, "LEFT", COL.NAME, 0)

            row._rank  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._rank:SetPoint("LEFT", row, "LEFT", COL.RANK, 0)

            row._class = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._class:SetPoint("LEFT", row, "LEFT", COL.CLASS, 0)

            row._level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._level:SetPoint("LEFT", row, "LEFT", COL.LEVEL, 0)

            row._note  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._note:SetPoint("LEFT", row, "LEFT", COL.NOTE, 0)
            row._note:SetWidth(panel:GetWidth() - COL.NOTE - 10)
            row._note:SetJustifyH("LEFT")
            row._note:SetWordWrap(false)

            panel._rows[idx] = row
        end
        return panel._rows[idx]
    end

    -- Populate roster
    local function refresh()
        local n = GetNumGuildMembers()
        for i = 1, n do
            local name, rankName, _, level, _, _, note, _, _, className =
                GetGuildRosterInfo(i)
            if name then
                local row = getRow(i)
                local cc  = classColor(className or "")
                row._name:SetText("|cff" .. cc .. (name:match("([^%-]+)") or name) .. "|r")
                row._rank:SetText(rankName  or "")
                row._class:SetText(className or "")
                row._level:SetText(tostring(level or ""))
                row._note:SetText(note or "")
                row:Show()
            end
        end
        -- hide leftover rows
        for i = n+1, #panel._rows do
            panel._rows[i]:Hide()
        end
    end

    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(100, GMT.L.btnH)
    refreshBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        local ok, err = pcall(function() GuildRoster(); refresh() end)
        if not ok then GMT.Err("Members refresh: " .. tostring(err)) end
    end)

    panel._refresh = refresh
    refresh()
end

function GMT_Members_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Members")
        if not panel or panel._membersBuilt then return end
        panel._membersBuilt = true
        buildMembersPanel(panel)
    end)
    if not ok then GMT.Err("Members init: " .. tostring(err)) end
end

GMT.RegisterModule("Members", GMT_Members_Init)
