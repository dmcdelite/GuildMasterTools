-- GuildMasterTools Modules/TalentMap.lua
-- Displays gathered talent / specialisation data for guild members.
-- Replaces the old Crafting.lua (removed in v4.2.0).

-- ── Constants ─────────────────────────────────────────────────────────────
local SPEC_COLORS = {
    ["Protection"]  = "ff4488ff",
    ["Holy"]        = "ffffffaa",
    ["Retribution"] = "ffcf9030",
    ["Frost"]       = "ff88ccff",
    ["Fire"]        = "ffff6622",
    ["Arcane"]      = "ffcc66ff",
    ["Restoration"] = "ff00ff98",
    ["Balance"]     = "ffccaa00",
    ["Feral"]       = "ffeebb44",
    ["Guardian"]    = "ffaa6622",
    ["Affliction"]  = "ff9955cc",
    ["Demonology"]  = "ff7744aa",
    ["Destruction"] = "ffff4422",
    ["Beast Mastery"]= "ff88cc44",
    ["Marksmanship"]= "ffaaddaa",
    ["Survival"]    = "ff667733",
    ["Arms"]        = "ffcc4422",
    ["Fury"]        = "ffdd6633",
}
local DEFAULT_SPEC_COLOR = "ffaaaaaa"

-- ── Module-level state ────────────────────────────────────────────────────
local selectedMember  = nil   -- name of currently selected member
local memberSpecCache = {}    -- name → { spec, talents = {} }

-- ── Helpers ───────────────────────────────────────────────────────────────
local function specColor(specName)
    return SPEC_COLORS[specName] or DEFAULT_SPEC_COLOR
end

-- Safely query the selected profession / recipe list using C_TradeSkillUI.
-- Returns a list of recipe IDs or an empty table on failure.
local function querySelectedRecipes()
    local recipes = {}
    if not C_TradeSkillUI then return recipes end

    local ok, result = pcall(function()
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if type(recipeIDs) ~= "table" then return end
        for _, id in ipairs(recipeIDs) do
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.name then
                table.insert(recipes, {
                    id       = id,
                    name     = info.name,
                    learned  = info.learned,
                    numSkillUps = info.numSkillUps or 0,
                })
            end
        end
    end)
    if not ok then
        GMT.Err("TalentMap.querySelectedRecipes: " .. tostring(result))
    end
    return recipes
end

-- Collect the current player's active specialisation.
local function queryPlayerSpec()
    if not GetSpecialization then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local _, name = GetSpecializationInfo(specIndex)
    return name
end

-- Build or refresh memberSpecCache from the guild roster.
local function refreshCache()
    memberSpecCache = {}
    local n = GetNumGuildMembers()
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            local shortName = name:match("([^%-]+)") or name
            memberSpecCache[shortName] = memberSpecCache[shortName] or {
                spec    = "Unknown",
                talents = {},
            }
        end
    end
end

-- ── UI builders ───────────────────────────────────────────────────────────
local function buildMemberList(panel, onSelect)
    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -28)
    listFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    listFrame:SetWidth(200)

    local bg = listFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.10, 0.60)

    listFrame._rows = {}

    local function populateList()
        for _, row in ipairs(listFrame._rows) do row:Hide() end
        listFrame._rows = {}

        local names = {}
        for name in pairs(memberSpecCache) do
            table.insert(names, name)
        end
        table.sort(names)

        for idx, name in ipairs(names) do
            local btn = CreateFrame("Button", nil, listFrame)
            btn:SetSize(200, 20)
            btn:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(idx-1)*20)

            local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
            hoverBg:SetAllPoints()
            hoverBg:SetColorTexture(1, 1, 1, 0)
            btn:SetHighlightTexture(hoverBg)
            hoverBg:SetColorTexture(0.25, 0.20, 0.10, 0.35)

            local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", btn, "LEFT", 6, 0)
            lbl:SetText(name)

            local btnName = name
            btn:SetScript("OnClick", function()
                onSelect(btnName)
            end)

            table.insert(listFrame._rows, btn)
        end
    end

    listFrame.populate = populateList
    populateList()
    return listFrame
end

local function buildDetailPane(panel)
    local detail = CreateFrame("Frame", nil, panel)
    detail:SetPoint("TOPLEFT",     panel, "TOPLEFT",  204, -28)
    detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0,  0)

    local bg = detail:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.08, 0.50)

    -- Member name heading
    detail._nameLabel = detail:CreateFontString(nil, "OVERLAY")
    detail._nameLabel:SetFont("Fonts/FRIZQT__.TTF", GMT.F.large, "OUTLINE")
    detail._nameLabel:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -8)
    detail._nameLabel:SetText("|cff" .. GMT.C.grey .. "Select a member…|r")

    -- Spec label
    detail._specLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail._specLabel:SetPoint("TOPLEFT", detail._nameLabel, "BOTTOMLEFT", 0, -6)
    detail._specLabel:SetText("")

    -- Talent list header
    detail._talentHdr = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detail._talentHdr:SetPoint("TOPLEFT", detail._specLabel, "BOTTOMLEFT", 0, -12)
    detail._talentHdr:SetText("")

    -- Talent rows
    detail._talentRows = {}

    local function clearTalentRows()
        for _, row in ipairs(detail._talentRows) do row:Hide() end
        detail._talentRows = {}
    end

    function detail:showMember(name)
        local data = memberSpecCache[name]
        if not data then
            self._nameLabel:SetText("|cff" .. GMT.C.red .. "Data unavailable|r")
            self._specLabel:SetText("")
            self._talentHdr:SetText("")
            clearTalentRows()
            return
        end

        self._nameLabel:SetText("|cff" .. GMT.C.white .. name .. "|r")

        local sc = specColor(data.spec)
        self._specLabel:SetText("Spec: |cff" .. sc .. (data.spec or "Unknown") .. "|r")

        local talents = data.talents or {}
        if #talents == 0 then
            self._talentHdr:SetText("|cff" .. GMT.C.grey .. "No talent data recorded.|r")
            clearTalentRows()
            return
        end

        self._talentHdr:SetText("|cff" .. GMT.C.gold ..
                                "Talents (" .. #talents .. ")|r")
        clearTalentRows()

        for i, talent in ipairs(talents) do
            local row = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row:SetPoint("TOPLEFT", self._talentHdr, "BOTTOMLEFT",
                         0, -(i-1) * 18 - 4)
            row:SetText("  • " .. tostring(talent))
            table.insert(detail._talentRows, row)
        end
    end

    return detail
end

-- ── Panel builder ─────────────────────────────────────────────────────────
local function buildTalentMapPanel(panel)
    local C = GMT.C

    GMT_SectionHeader(panel, "Talent Map", -4)

    -- Refresh / Scan button
    local scanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanBtn:SetSize(110, GMT.L.btnH)
    scanBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    scanBtn:SetText("Refresh Roster")

    -- Build detail pane first so the list can reference it
    local detail = buildDetailPane(panel)

    -- Build member list
    local memberList = buildMemberList(panel, function(name)
        selectedMember = name
        detail:showMember(name)
    end)

    scanBtn:SetScript("OnClick", function()
        local ok, err = pcall(function()
            GuildRoster()
            refreshCache()
            memberList.populate()
            if selectedMember then
                detail:showMember(selectedMember)
            end
        end)
        if not ok then GMT.Err("TalentMap scan: " .. tostring(err)) end
    end)

    -- Profession recipes sub-section (below the member list)
    local recipeHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    recipeHdr:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 100)
    recipeHdr:SetText("|cff" .. C.gold .. "Your Known Recipes|r")

    local recipeList = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recipeList:SetPoint("TOPLEFT",  recipeHdr, "BOTTOMLEFT", 0, -4)
    recipeList:SetWidth(190)
    recipeList:SetJustifyH("LEFT")
    recipeList:SetWordWrap(true)
    recipeList:SetText("|cff" .. C.grey .. "(open a profession to scan)|r")

    local scanRecipesBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scanRecipesBtn:SetSize(130, GMT.L.btnH)
    scanRecipesBtn:SetPoint("TOPLEFT", recipeHdr, "TOPRIGHT", 8, 0)
    scanRecipesBtn:SetText("Scan Recipes")
    scanRecipesBtn:SetScript("OnClick", function()
        local recipes = querySelectedRecipes()
        if #recipes == 0 then
            recipeList:SetText("|cff" .. C.grey .. "No recipes found (open a profession first).|r")
            return
        end
        local lines = {}
        for i = 1, math.min(#recipes, 20) do
            local r   = recipes[i]
            local col = r.learned and C.green or C.grey
            table.insert(lines, "|cff" .. col .. r.name .. "|r")
        end
        if #recipes > 20 then
            table.insert(lines, "|cff" .. C.grey ..
                         "(+" .. (#recipes - 20) .. " more…)|r")
        end
        recipeList:SetText(table.concat(lines, "\n"))
    end)

    panel._refresh = function()
        refreshCache()
        memberList.populate()
    end
end

-- ── Public init ───────────────────────────────────────────────────────────
function GMT_TalentMap_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("TalentMap")
        if not panel or panel._talentBuilt then return end
        panel._talentBuilt = true

        refreshCache()
        buildTalentMapPanel(panel)
    end)
    if not ok then GMT.Err("TalentMap init: " .. tostring(err)) end
end

GMT.RegisterModule("TalentMap", GMT_TalentMap_Init)
