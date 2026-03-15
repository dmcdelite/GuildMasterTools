-- GuildMasterTools Modules/Options.lua
-- Addon settings panel

local function buildOptionsPanel(panel)
    local C = GMT.C
    local L = GMT.L

    GMT_SectionHeader(panel, "Options", -4)

    local yOff = -36

    -- ── Helper: labelled checkbox ────────────────────────────────────
    local function checkboxRow(label, key, tip)
        local cb = CreateFrame("CheckButton", nil, panel,
                               "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, yOff)
        cb:SetChecked(GMT_DB.options[key])
        cb:SetScript("OnClick", function(self)
            GMT_DB.options[key] = self:GetChecked()
        end)

        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(label)

        if tip then
            local tipText = panel:CreateFontString(nil, "OVERLAY",
                                                   "GameFontNormalSmall")
            tipText:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
            tipText:SetText("|cff" .. C.grey .. tip .. "|r")
        end

        yOff = yOff - 30
        return cb
    end

    -- ── Options ───────────────────────────────────────────────────────
    local cbMinimap = checkboxRow(
        "Show Minimap Button",
        "showMinimapBtn",
        "(Requires reload)")

    local cbAlertRank = checkboxRow(
        "Alert on Rank Drop",
        "alertRankDrop",
        "Notify when a member's rank decreases")

    -- Theme selector
    yOff = yOff - 10
    local themeLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, yOff)
    themeLbl:SetText("|cff" .. C.gold .. "Theme:|r")
    yOff = yOff - 26

    local themes   = { "dark", "light", "classic" }
    local themeRadios = {}
    for _, t in ipairs(themes) do
        local rb = CreateFrame("CheckButton", nil, panel,
                               "UIRadioButtonTemplate")
        rb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, yOff)
        rb:SetChecked(GMT_DB.options.theme == t)
        rb._value = t

        local lbl2 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl2:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        lbl2:SetText(t:sub(1,1):upper() .. t:sub(2))

        rb:SetScript("OnClick", function(self)
            GMT_DB.options.theme = self._value
            for _, other in ipairs(themeRadios) do
                other:SetChecked(other._value == self._value)
            end
        end)

        table.insert(themeRadios, rb)
        yOff = yOff - 26
    end

    -- Divider
    yOff = yOff - 10
    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, yOff)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, yOff)
    div:SetHeight(1)
    GMT.SetBGColor(div, C.border)
    yOff = yOff - 20

    -- Version info
    local verLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, yOff)
    verLbl:SetText(
        "|cff" .. C.grey ..
        "GuildMasterTools v" .. GMT.VERSION ..
        "  |r|cff" .. C.gold .. "by dmcdelite|r")

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, L.btnH)
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, yOff - 30)
    resetBtn:SetText("Reset All Settings")
    resetBtn:SetScript("OnClick", function()
        GMT_DB.options = {
            theme           = "dark",
            showMinimapBtn  = true,
            alertRankDrop   = true,
        }
        cbMinimap:SetChecked(true)
        cbAlertRank:SetChecked(true)
        for _, rb in ipairs(themeRadios) do
            rb:SetChecked(rb._value == "dark")
        end
        GMT.Print("Options reset to defaults.")
    end)
end

function GMT_Options_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Options")
        if not panel or panel._optBuilt then return end
        panel._optBuilt = true
        buildOptionsPanel(panel)
    end)
    if not ok then GMT.Err("Options init: " .. tostring(err)) end
end

GMT.RegisterModule("Options", GMT_Options_Init)
