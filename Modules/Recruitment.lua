-- GuildMasterTools Modules/Recruitment.lua
-- Track and manage guild applicants

local STATUS_COLORS = {
    Pending  = "ffcf9030",
    Approved = "ff00ff98",
    Declined = "ffff4444",
    Review   = "ff4488ff",
}

local function buildRecruitmentPanel(panel)
    local C = GMT.C
    local db = GMT_DB.applicants

    -- Section header
    GMT_SectionHeader(panel, "Applicant Tracker", -4)

    -- Add applicant form
    local addHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    addHdr:SetText("|cff" .. C.gold .. "Add Applicant|r")

    local nameLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -56)
    nameLbl:SetText("Name:")

    local nameBox = CreateFrame("EditBox", "GMT_Recruit_NameBox", panel,
                                "InputBoxTemplate")
    nameBox:SetSize(160, 20)
    nameBox:SetPoint("LEFT", nameLbl, "RIGHT", 8, 0)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(64)

    local classLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLbl:SetPoint("LEFT", nameBox, "RIGHT", 16, 0)
    classLbl:SetText("Class:")

    local classBox = CreateFrame("EditBox", "GMT_Recruit_ClassBox", panel,
                                 "InputBoxTemplate")
    classBox:SetSize(120, 20)
    classBox:SetPoint("LEFT", classLbl, "RIGHT", 8, 0)
    classBox:SetAutoFocus(false)
    classBox:SetMaxLetters(32)

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, GMT.L.btnH)
    addBtn:SetPoint("LEFT", classBox, "RIGHT", 12, 0)
    addBtn:SetText("Add")

    -- List header
    local function colHdr(text, x, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        fs:SetText("|cff" .. C.gold .. text .. "|r")
    end
    colHdr("Name",   8,  -90)
    colHdr("Class",  180, -90)
    colHdr("Status", 310, -90)
    colHdr("Date",   420, -90)

    local divider = panel:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -108)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -108)
    divider:SetHeight(1)
    GMT.SetBGColor(divider, C.border)

    -- Row rendering
    panel._appRows = {}

    local function renderRow(i, applicant)
        if not panel._appRows[i] then
            local row = CreateFrame("Frame", nil, panel)
            row:SetSize(panel:GetWidth(), GMT.L.rowH)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(110 + (i-1) * GMT.L.rowH))

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetColorTexture(0.10, 0.10, 0.14, 0.40)
            else
                bg:SetColorTexture(0.07, 0.07, 0.10, 0.25)
            end

            row._name   = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row._name:SetPoint("LEFT", row, "LEFT", 8, 0)

            row._class  = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._class:SetPoint("LEFT", row, "LEFT", 180, 0)

            row._status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._status:SetPoint("LEFT", row, "LEFT", 310, 0)

            row._date   = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row._date:SetPoint("LEFT", row, "LEFT", 420, 0)

            panel._appRows[i] = row
        end
        local row = panel._appRows[i]
        local sc = STATUS_COLORS[applicant.status] or C.grey
        row._name:SetText(applicant.name   or "?")
        row._class:SetText(applicant.class  or "?")
        row._status:SetText("|cff" .. sc .. (applicant.status or "Pending") .. "|r")
        row._date:SetText(applicant.date   or "")
        row:Show()
    end

    local function refreshList()
        db = GMT_DB.applicants
        for i, app in ipairs(db) do
            renderRow(i, app)
        end
        for i = #db + 1, #panel._appRows do
            panel._appRows[i]:Hide()
        end
    end

    addBtn:SetScript("OnClick", function()
        local name  = nameBox:GetText():match("^%s*(.-)%s*$")
        local class = classBox:GetText():match("^%s*(.-)%s*$")
        if name == "" then
            GMT.Err("Please enter an applicant name.")
            return
        end
        table.insert(GMT_DB.applicants, {
            name   = name,
            class  = class ~= "" and class or "Unknown",
            status = "Pending",
            date   = date("%Y-%m-%d", time()),
        })
        nameBox:SetText("")
        classBox:SetText("")
        refreshList()
    end)

    refreshList()
    panel._refresh = refreshList
end

function GMT_Recruitment_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Recruitment")
        if not panel or panel._recruitBuilt then return end
        panel._recruitBuilt = true
        buildRecruitmentPanel(panel)
    end)
    if not ok then GMT.Err("Recruitment init: " .. tostring(err)) end
end

GMT.RegisterModule("Recruitment", GMT_Recruitment_Init)
