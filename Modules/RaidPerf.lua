-- GuildMasterTools Modules/RaidPerf.lua
-- Raid performance log: DPS / HPS / deaths per encounter

local COL = { NAME=0, ROLE=160, DPS=260, HPS=340, DEATHS=430, SCORE=520 }

local function buildRaidPerfPanel(panel)
    local C = GMT.C

    GMT_SectionHeader(panel, "Raid Performance", -4)

    -- Column headers
    local function colHdr(text, x)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -28)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Name",   COL.NAME)
    colHdr("Role",   COL.ROLE)
    colHdr("DPS",    COL.DPS)
    colHdr("HPS",    COL.HPS)
    colHdr("Deaths", COL.DEATHS)
    colHdr("Score",  COL.SCORE)

    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -46)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -46)
    div:SetHeight(1)
    GMT.SetBGColor(div, C.border)

    -- Rows
    panel._rpRows = {}

    local function getRow(i)
        if not panel._rpRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(48 + (i-1) * GMT.L.rowH))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            local function addCell(x)
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", row, "LEFT", x, 0)
                return fs
            end

            row._name   = addCell(COL.NAME)
            row._role   = addCell(COL.ROLE)
            row._dps    = addCell(COL.DPS)
            row._hps    = addCell(COL.HPS)
            row._deaths = addCell(COL.DEATHS)
            row._score  = addCell(COL.SCORE)

            panel._rpRows[i] = row
        end
        return panel._rpRows[i]
    end

    -- Sample/stub data render from saved DB
    local function refresh()
        local log = GMT_DB.raidPerf or {}
        for i, entry in ipairs(log) do
            local row = getRow(i)
            row._name:SetText(entry.name   or "?")
            row._role:SetText(entry.role   or "?")
            row._dps:SetText(entry.dps    and string.format("%.0f", entry.dps)  or "—")
            row._hps:SetText(entry.hps    and string.format("%.0f", entry.hps)  or "—")
            row._deaths:SetText(tostring(entry.deaths or 0))

            -- Simple score: dps*0.6 + hps*0.3 - deaths*500
            local score = ((entry.dps or 0) * 0.6)
                        + ((entry.hps or 0) * 0.3)
                        - ((entry.deaths or 0) * 500)
            local scoreCol = score >= 0 and C.green or GMT.C.red
            row._score:SetText("|cff" .. scoreCol ..
                               string.format("%.0f", score) .. "|r")
            row:Show()
        end
        for i = #log + 1, #panel._rpRows do
            panel._rpRows[i]:Hide()
        end
    end

    -- Clear log button
    local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearBtn:SetSize(100, GMT.L.btnH)
    clearBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        GMT_DB.raidPerf = {}
        refresh()
    end)

    refresh()
    panel._refresh = refresh
end

function GMT_RaidPerf_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("RaidPerf")
        if not panel or panel._rpBuilt then return end
        panel._rpBuilt = true
        buildRaidPerfPanel(panel)
    end)
    if not ok then GMT.Err("RaidPerf init: " .. tostring(err)) end
end

GMT.RegisterModule("RaidPerf", GMT_RaidPerf_Init)
