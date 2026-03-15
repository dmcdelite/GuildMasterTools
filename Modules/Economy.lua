-- GuildMasterTools Modules/Economy.lua
-- Guild bank gold tracking and transaction log

local TX_TYPES = { "Deposit", "Withdrawal", "Fee", "Donation", "Other" }

local function buildEconomyPanel(panel)
    local C = GMT.C

    GMT_SectionHeader(panel, "Economy", -4)

    -- Bank balance display
    local balLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    balLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
    balLbl:SetText("|cff" .. C.gold .. "Bank Balance:|r")

    local balVal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    balVal:SetPoint("LEFT", balLbl, "RIGHT", 8, 0)

    local function updateBalance()
        local g = GMT_DB.economy.bankGold or 0
        local gold   = math.floor(g / 10000)
        local silver = math.floor((g % 10000) / 100)
        local copper = g % 100
        balVal:SetText(
            "|cffffcc00" .. gold   .. "g|r " ..
            "|cffc0c0c0" .. silver .. "s|r " ..
            "|cffb87333" .. copper .. "c|r")
    end
    updateBalance()

    -- Transaction log headers
    local function colHdr(text, x, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Date",        8,   -60)
    colHdr("Type",        120, -60)
    colHdr("Amount (g)",  220, -60)
    colHdr("By",          340, -60)
    colHdr("Note",        450, -60)

    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -78)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -78)
    div:SetHeight(1)
    GMT.SetBGColor(div, C.border)

    -- Log rows
    panel._txRows = {}

    local function getRow(i)
        if not panel._txRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(80 + (i-1)*GMT.L.rowH))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            local function cell(x)
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", row, "LEFT", x, 0)
                return fs
            end
            row._date   = cell(8)
            row._type   = cell(120)
            row._amount = cell(220)
            row._by     = cell(340)
            row._note   = cell(450)

            panel._txRows[i] = row
        end
        return panel._txRows[i]
    end

    local function refreshLog()
        local log = GMT_DB.economy.log or {}
        for i, tx in ipairs(log) do
            local row = getRow(i)
            local amtCol = (tx.amount or 0) >= 0 and C.green or GMT.C.red
            row._date:SetText(tx.date   or "")
            row._type:SetText(tx.type   or "")
            row._amount:SetText("|cff" .. amtCol ..
                                tostring(tx.amount or 0) .. "g|r")
            row._by:SetText(tx.by     or "")
            row._note:SetText(tx.note  or "")
            row:Show()
        end
        for i = #(GMT_DB.economy.log or {}) + 1, #panel._txRows do
            panel._txRows[i]:Hide()
        end
    end

    -- Add transaction form
    local formY = -82

    local typeLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 80)
    typeLbl:SetText("Type:")

    local typeDD = CreateFrame("Frame", "GMT_Econ_TypeDD", panel,
                               "UIDropDownMenuTemplate")
    typeDD:SetPoint("LEFT", typeLbl, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(typeDD, 100)
    UIDropDownMenu_Initialize(typeDD, function(self, level)
        for _, t in ipairs(TX_TYPES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = t
            info.func  = function()
                UIDropDownMenu_SetSelectedValue(typeDD, t)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(typeDD, TX_TYPES[1])

    local amtLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amtLbl:SetPoint("LEFT", typeDD, "RIGHT", 6, 0)
    amtLbl:SetText("Amount (g):")

    local amtBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    amtBox:SetSize(80, 20)
    amtBox:SetPoint("LEFT", amtLbl, "RIGHT", 6, 0)
    amtBox:SetAutoFocus(false)

    local noteLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLbl:SetPoint("LEFT", amtBox, "RIGHT", 10, 0)
    noteLbl:SetText("Note:")

    local noteBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    noteBox:SetSize(140, 20)
    noteBox:SetPoint("LEFT", noteLbl, "RIGHT", 6, 0)
    noteBox:SetAutoFocus(false)
    noteBox:SetMaxLetters(128)

    local logBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    logBtn:SetSize(80, GMT.L.btnH)
    logBtn:SetPoint("LEFT", noteBox, "RIGHT", 10, 0)
    logBtn:SetText("Log")
    logBtn:SetScript("OnClick", function()
        local txType = UIDropDownMenu_GetSelectedValue(typeDD) or TX_TYPES[1]
        local amt    = tonumber(amtBox:GetText()) or 0
        local note   = noteBox:GetText():match("^%s*(.-)%s*$")
        table.insert(GMT_DB.economy.log, {
            date   = date("%Y-%m-%d", time()),
            type   = txType,
            amount = amt,
            by     = UnitName("player") or "Unknown",
            note   = note,
        })
        -- update bank balance
        if txType == "Deposit" or txType == "Donation" then
            GMT_DB.economy.bankGold = (GMT_DB.economy.bankGold or 0) + (amt * 10000)
        elseif txType == "Withdrawal" or txType == "Fee" then
            GMT_DB.economy.bankGold = (GMT_DB.economy.bankGold or 0) - (amt * 10000)
        end
        amtBox:SetText("")
        noteBox:SetText("")
        updateBalance()
        refreshLog()
    end)

    refreshLog()
    panel._refresh = refreshLog
end

function GMT_Economy_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Economy")
        if not panel or panel._econBuilt then return end
        panel._econBuilt = true
        buildEconomyPanel(panel)
    end)
    if not ok then GMT.Err("Economy init: " .. tostring(err)) end
end

GMT.RegisterModule("Economy", GMT_Economy_Init)
