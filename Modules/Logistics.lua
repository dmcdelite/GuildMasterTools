-- GuildMasterTools Modules/Logistics.lua
-- Track supply inventory and member supply requests

local function buildLogisticsPanel(panel)
    local C = GMT.C
    local db = GMT_DB.logistics

    GMT_SectionHeader(panel, "Logistics", -4)

    -- ── Supplies section ─────────────────────────────────────────────
    local supHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -32)
    supHdr:SetText("|cff" .. C.gold .. "Supply Inventory|r")

    local function colHdr(text, x, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Item",     8,   -50)
    colHdr("Quantity", 280, -50)
    colHdr("Notes",    370, -50)

    local supDiv = panel:CreateTexture(nil, "BACKGROUND")
    supDiv:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -66)
    supDiv:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -66)
    supDiv:SetHeight(1)
    GMT.SetBGColor(supDiv, C.border)

    -- Supply rows
    panel._supRows = {}

    local function renderSupplyRow(i, item)
        if not panel._supRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(68 + (i-1)*GMT.L.rowH))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            row._item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._item:SetPoint("LEFT", row, "LEFT", 8, 0)
            row._item:SetWidth(260)
            row._item:SetJustifyH("LEFT")

            row._qty  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._qty:SetPoint("LEFT", row, "LEFT", 280, 0)

            row._note = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._note:SetPoint("LEFT", row, "LEFT", 370, 0)

            panel._supRows[i] = row
        end
        local row = panel._supRows[i]
        row._item:SetText(item.name or "?")
        row._qty:SetText(tostring(item.quantity or 0))
        row._note:SetText(item.note or "")
        row:Show()
    end

    local function refreshSupplies()
        db = GMT_DB.logistics
        local supplies = db.supplies or {}
        for i, s in ipairs(supplies) do renderSupplyRow(i, s) end
        for i = #supplies + 1, #panel._supRows do panel._supRows[i]:Hide() end
    end

    -- Add supply form
    local baseY = -(68 + 15 * GMT.L.rowH + 20)

    local addSupHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addSupHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, baseY)
    addSupHdr:SetText("|cff" .. C.gold .. "Add Supply Item|r")

    local itemLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, baseY - 22)
    itemLbl:SetText("Item:")

    local itemBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    itemBox:SetSize(180, 20)
    itemBox:SetPoint("LEFT", itemLbl, "RIGHT", 6, 0)
    itemBox:SetAutoFocus(false)
    itemBox:SetMaxLetters(64)

    local qtyLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("LEFT", itemBox, "RIGHT", 14, 0)
    qtyLbl:SetText("Qty:")

    local qtyBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    qtyBox:SetSize(60, 20)
    qtyBox:SetPoint("LEFT", qtyLbl, "RIGHT", 6, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetMaxLetters(10)
    qtyBox:SetNumeric(true)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(70, GMT.L.btnH)
    addBtn:SetPoint("LEFT", qtyBox, "RIGHT", 10, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = itemBox:GetText():match("^%s*(.-)%s*$")
        local qty  = tonumber(qtyBox:GetText()) or 0
        if name == "" then GMT.Err("Supply item name required.") return end
        table.insert(GMT_DB.logistics.supplies, { name=name, quantity=qty })
        itemBox:SetText("")
        qtyBox:SetText("")
        refreshSupplies()
    end)

    refreshSupplies()
    panel._refresh = refreshSupplies
end

function GMT_Logistics_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Logistics")
        if not panel or panel._logBuilt then return end
        panel._logBuilt = true
        buildLogisticsPanel(panel)
    end)
    if not ok then GMT.Err("Logistics init: " .. tostring(err)) end
end

GMT.RegisterModule("Logistics", GMT_Logistics_Init)
