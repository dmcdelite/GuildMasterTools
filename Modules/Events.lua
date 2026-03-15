-- GuildMasterTools Modules/Events.lua
-- Guild event scheduler

local function buildEventsPanel(panel)
    local C  = GMT.C
    local db = GMT_DB.events

    GMT_SectionHeader(panel, "Events", -4)

    -- Column headers
    local function colHdr(text, x, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Title",       8,   -32)
    colHdr("Date",        280, -32)
    colHdr("Type",        380, -32)
    colHdr("Organiser",   470, -32)

    local div = panel:CreateTexture(nil, "BACKGROUND")
    div:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -50)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -50)
    div:SetHeight(1)
    GMT.SetBGColor(div, C.border)

    -- Event rows
    panel._evtRows = {}

    local function getRow(i)
        if not panel._evtRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(52 + (i-1)*GMT.L.rowH))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            local function cell(x, width)
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", row, "LEFT", x, 0)
                if width then
                    fs:SetWidth(width)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)
                end
                return fs
            end
            row._title = cell(8, 260)
            row._date  = cell(280)
            row._type  = cell(380)
            row._org   = cell(470)

            panel._evtRows[i] = row
        end
        return panel._evtRows[i]
    end

    local function refresh()
        db = GMT_DB.events
        for i, evt in ipairs(db) do
            local row = getRow(i)
            row._title:SetText(evt.title     or "Untitled")
            row._date:SetText(evt.date       or "")
            row._type:SetText(evt.type       or "General")
            row._org:SetText(evt.organiser   or "")
            row:Show()
        end
        for i = #db + 1, #panel._evtRows do
            panel._evtRows[i]:Hide()
        end
    end

    -- Add event form
    local titleLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleLbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 80)
    titleLbl:SetText("Title:")

    local titleBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    titleBox:SetSize(200, 20)
    titleBox:SetPoint("LEFT", titleLbl, "RIGHT", 6, 0)
    titleBox:SetAutoFocus(false)
    titleBox:SetMaxLetters(80)

    local dateLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dateLbl:SetPoint("LEFT", titleBox, "RIGHT", 10, 0)
    dateLbl:SetText("Date (YYYY-MM-DD):")

    local dateBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    dateBox:SetSize(110, 20)
    dateBox:SetPoint("LEFT", dateLbl, "RIGHT", 6, 0)
    dateBox:SetAutoFocus(false)
    dateBox:SetMaxLetters(10)

    local typeLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLbl:SetPoint("LEFT", dateBox, "RIGHT", 10, 0)
    typeLbl:SetText("Type:")

    local typeBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    typeBox:SetSize(100, 20)
    typeBox:SetPoint("LEFT", typeLbl, "RIGHT", 6, 0)
    typeBox:SetAutoFocus(false)
    typeBox:SetMaxLetters(32)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(70, GMT.L.btnH)
    addBtn:SetPoint("LEFT", typeBox, "RIGHT", 10, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local title = titleBox:GetText():match("^%s*(.-)%s*$")
        local eDate = dateBox:GetText():match("^%s*(.-)%s*$")
        local eType = typeBox:GetText():match("^%s*(.-)%s*$")
        if title == "" then
            GMT.Err("Event title is required.")
            return
        end
        table.insert(GMT_DB.events, {
            title     = title,
            date      = eDate ~= "" and eDate or date("%Y-%m-%d", time()),
            type      = eType ~= "" and eType or "General",
            organiser = UnitName("player") or "Unknown",
        })
        titleBox:SetText("")
        dateBox:SetText("")
        typeBox:SetText("")
        refresh()
    end)

    refresh()
    panel._refresh = refresh
end

function GMT_Events_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Events")
        if not panel or panel._evtBuilt then return end
        panel._evtBuilt = true
        buildEventsPanel(panel)
    end)
    if not ok then GMT.Err("Events init: " .. tostring(err)) end
end

GMT.RegisterModule("Events", GMT_Events_Init)
