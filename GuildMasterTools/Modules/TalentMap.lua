-- ============================================================
-- GuildMaster Tools  |  Modules/TalentMap.lua  |  v4.2.0
-- Guild Professions v2 rebuilt around synced profession profiles
-- ============================================================
local _, GMT = ...

GMT.TM = GMT.TM or {}
local TM = GMT.TM

local refs = {}
local ROW_H = 20
local eventFrame
local refreshAll

local SEP_F = string.char(31)
local SEP_R = string.char(30)
local SEP_I = string.char(29)

local function U(c) return GMT.U(c) end
local function now() return time and time() or 0 end

local function clip(text, n)
    text = tostring(text or "")
    if #text <= n then return text end
    return text:sub(1, math.max(1, n - 3)) .. "..."
end

local function fmtAgo(ts)
    if not ts or ts <= 0 then return "Never" end
    local d = now() - ts
    if d < 60 then return "Now" end
    if d < 3600 then return tostring(math.floor(d/60)) .. "m" end
    if d < 86400 then return tostring(math.floor(d/3600)) .. "h" end
    return tostring(math.floor(d/86400)) .. "d"
end

local function ensureDB()
    GMT.DB.talentMap = GMT.DB.talentMap or {}
    local db = GMT.DB.talentMap

    if GMT.DB.crafting and not db._migratedFromCrafting then
        local old = GMT.DB.crafting
        if next(db) == nil then
            for k, v in pairs(old) do db[k] = v end
        else
            db.tracked = db.tracked or old.tracked
            db.notes = db.notes or old.notes
            db.guildCache = db.guildCache or old.guildCache
            db.materials = db.materials or old.materials
            db.log = db.log or old.log
            db.syncProfiles = db.syncProfiles or old.syncProfiles
            db.lastGuildMapScan = db.lastGuildMapScan or old.lastGuildMapScan
            db.lastMaterialScan = db.lastMaterialScan or old.lastMaterialScan
            db.lastRecipeScan = db.lastRecipeScan or old.lastRecipeScan
            db.lastSyncSent = db.lastSyncSent or old.lastSyncSent
        end
        db._migratedFromCrafting = true
    end

    db.tracked = db.tracked or {}
    db.notes = db.notes or ""
    db.guildCache = db.guildCache or {}
    db.materials = db.materials or {}
    db.log = db.log or {}
    db.syncProfiles = db.syncProfiles or {}
    db.lastGuildMapScan = db.lastGuildMapScan or 0
    db.lastMaterialScan = db.lastMaterialScan or 0
    db.lastRecipeScan = db.lastRecipeScan or 0
    db.lastSyncSent = db.lastSyncSent or 0
    db.syncCoverage = db.syncCoverage or {}
    return db
end

local function addLog(msg)
    local log = ensureDB().log
    table.insert(log, 1, {t = now(), msg = tostring(msg or "")})
    while #log > 60 do table.remove(log) end
end

local function setStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Ready")
    if kind == "green" then
        refs.status:SetTextColor(U(GMT.C.green))
    elseif kind == "red" then
        refs.status:SetTextColor(U(GMT.C.red))
    else
        refs.status:SetTextColor(U(GMT.C.amber))
    end
end

local function normalizeName(name)
    if not name then return nil end
    name = tostring(name)
    local short = name:match("^([^%-]+)")
    return short or name
end

local function myNameRealm()
    local name = UnitName and UnitName("player") or "Player"
    local realm = GetRealmName and GetRealmName() or "Realm"
    realm = tostring(realm):gsub("%s+", "")
    return tostring(name) .. "-" .. tostring(realm)
end

local function myShortName()
    return normalizeName(myNameRealm())
end

local function professionIsOpen()
    if TradeSkillFrame and TradeSkillFrame.IsShown and TradeSkillFrame:IsShown() then return true end
    if ProfessionsFrame and ProfessionsFrame.IsShown and ProfessionsFrame:IsShown() then return true end
    if CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown() then return true end
    return false
end

local function section(parent, title, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    box:SetBackdropColor(U(GMT.C.cardBg))
    box:SetBackdropBorderColor(U(GMT.C.copper))
    local head = box:CreateTexture(nil, "BACKGROUND")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    head:SetSize(w - 6, 22)
    head:SetColorTexture(U(GMT.C.cardHead))
    local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -7)
    fs:SetTextColor(U(GMT.C.txtTitle))
    fs:SetText(title)
    if GMT.Rivets then GMT.Rivets(box, 6, 4) end
    return box
end

local function label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(U(GMT.C.txtDim))
    fs:SetText(text)
    return fs
end

local function input(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function multiInput(parent, x, y, w, h)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, h)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(U(GMT.C.panelBg))
    bg:SetBackdropBorderColor(U(GMT.C.brass))
    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextColor(U(GMT.C.txtBody))
    eb:SetPoint("TOPLEFT", bg, "TOPLEFT", 6, -6)
    eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6, 6)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function makeScrollList(parent, x, y, w, h, cols)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    frame:SetBackdropColor(U(GMT.C.panelBg))
    frame:SetBackdropBorderColor(U(GMT.C.brass))

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetSize(w - 8, 18)
    local hb = header:CreateTexture(nil, "BACKGROUND")
    hb:SetAllPoints()
    hb:SetColorTexture(U(GMT.C.cardHead))

    local cx = 4
    for _, col in ipairs(cols) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", header, "LEFT", cx, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetTextColor(U(GMT.C.txtTitle))
        fs:SetText(col.label)
        cx = cx + col.w
    end

    local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -24)
    sf:SetSize(w - 24, h - 28)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - 24, 20)
    sf:SetScrollChild(content)
    return frame, content
end

local function row(content, y, w)
    local btn = CreateFrame("Button", nil, content)
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    btn:SetSize(w, ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.texts = {}
    return btn
end

local function setRow(r, cols, values)
    local x = 4
    for i, col in ipairs(cols) do
        local fs = r.texts[i]
        if not fs then
            fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.texts[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", r, "LEFT", x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(values[i] or "")
        x = x + col.w
    end
end

TM.state = TM.state or {
    guildMap = {},
    guildRecipes = {},
    materials = {},
    selectedCrafter = nil,
    roster = {},
    pendingGuildMap = false,
    pendingMaterialItems = {},
    pendingMaterialRefresh = false,
    debug = {profiles = 0, professions = 0, recipes = 0, built = 0},
    incomingChunks = {},
    lastHello = 0,
}

local guildCols = {
    {label="Member", w=112}, {label="Profession", w=116}, {label="Recipes", w=52, j="RIGHT"},
    {label="Status", w=54}, {label="Zone", w=64},
}
local recipeCols = {
    {label="Recipe", w=312}, {label="Source", w=84}, {label="Ready", w=70},
}
local matCols = {
    {label="Material", w=126}, {label="Bag", w=44, j="RIGHT"}, {label="Bucket", w=94},
}
local trackedCols = {
    {label="Craft", w=126}, {label="Need", w=44, j="RIGHT"}, {label="Have", w=44, j="RIGHT"}, {label="State", w=58},
}
local logCols = {{label="Update", w=274}}

local MATERIAL_KEYWORDS = {
    { label="Ore / Stone", patterns={" ore", "stone", "shard", "pebble"} },
    { label="Herbs", patterns={" herb", "flower", "leaf", "petal", "bloom"} },
    { label="Cloth", patterns={" cloth", "bolt"} },
    { label="Leather", patterns={" leather", "hide", "scale"} },
    { label="Enchanting", patterns={" dust", "essence", "crystal"} },
    { label="Gems", patterns={" gem", "ruby", "emerald", "sapphire", "diamond"} },
    { label="Cooking", patterns={" meat", "fish", "flour", "egg", "spice"} },
}

local function normalizeMaterialBucket(bucket)
    bucket = tostring(bucket or "")
    local map = {
        bagbucket = "Bag Materials",
        bag = "Bag Materials",
        materials = "Bag Materials",
        mat = "Bag Materials",
        other = "Uncategorized",
        uncategorized = "Uncategorized",
    }
    local key = string.lower(bucket):gsub("[%s_%-]", "")
    return map[key] or bucket
end

local function materialBucket(name)
    local lower = string.lower(name or "")
    for _, cat in ipairs(MATERIAL_KEYWORDS) do
        for _, pat in ipairs(cat.patterns) do
            if string.find(lower, pat, 1, true) then return cat.label end
        end
    end
    return "Uncategorized"
end

local function buildRoster()
    TM.state.roster = {}
    local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, total do
        local name, rankName, rankIndex, level, classDisplayName, zone, _, _, isOnline, _, classFileName, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if name then
            local short = normalizeName(name)
            local entry = {
                name = short,
                fullName = name,
                rankName = rankName,
                rankIndex = rankIndex,
                level = level or 0,
                class = classDisplayName or classFileName or "",
                classFileName = classFileName,
                zone = zone or "",
                online = not not isOnline,
                isMobile = not not isMobile,
                guid = guid,
            }
            TM.state.roster[name] = entry
            if short and not TM.state.roster[short] then TM.state.roster[short] = entry end
        end
    end
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

local function sortArray(arr)
    table.sort(arr, function(a, b) return tostring(a) < tostring(b) end)
    return arr
end

local function splitString(str, size)
    local out = {}
    str = tostring(str or "")
    for i = 1, #str, size do table.insert(out, str:sub(i, i + size - 1)) end
    if #out == 0 then out[1] = "" end
    return out
end

local function serializeProfile(player, profile)
    if not player or type(profile) ~= "table" then return nil end
    local lines = { table.concat({ player, tostring(profile.lastSeen or 0) }, SEP_F) }
    local profs = profile.professions or {}
    for _, profName in ipairs(sortedKeys(profs)) do
        local prof = profs[profName] or {}
        local recipes = {}
        for _, recipeName in ipairs(prof.recipes or {}) do
            if recipeName and recipeName ~= "" then table.insert(recipes, recipeName) end
        end
        sortArray(recipes)
        table.insert(lines, table.concat({
            profName,
            tostring(prof.skillLineID or 0),
            tostring(prof.scannedAt or 0),
            table.concat(recipes, SEP_I)
        }, SEP_F))
    end
    return table.concat(lines, SEP_R)
end

local function deserializeProfile(payload)
    if type(payload) ~= "string" or payload == "" then return nil end
    local profile = { professions = {}, lastSeen = 0 }
    local idx = 0
    for line in payload:gmatch("([^" .. SEP_R .. "]+)") do
        idx = idx + 1
        local parts = {}
        for part in string.gmatch(line .. SEP_F, "(.-)" .. SEP_F) do table.insert(parts, part) end
        if idx == 1 then
            profile.player = parts[1]
            profile.lastSeen = tonumber(parts[2] or 0) or 0
        else
            local profName = parts[1]
            if profName and profName ~= "" then
                local recipes = {}
                local rawRecipes = parts[4] or ""
                if rawRecipes ~= "" then
                    for recipe in string.gmatch(rawRecipes .. SEP_I, "(.-)" .. SEP_I) do
                        if recipe ~= "" then table.insert(recipes, recipe) end
                    end
                end
                profile.professions[profName] = {
                    skillLineID = tonumber(parts[2] or 0) or 0,
                    scannedAt = tonumber(parts[3] or 0) or 0,
                    recipes = recipes,
                }
            end
        end
    end
    if not profile.player then return nil end
    return profile.player, profile
end

local function mergeProfile(player, incoming)
    if not player or type(incoming) ~= "table" then return false end
    local db = ensureDB()
    local existing = db.syncProfiles[player] or { professions = {}, lastSeen = 0 }
    local changed = false

    if (incoming.lastSeen or 0) >= (existing.lastSeen or 0) then
        existing.lastSeen = incoming.lastSeen or existing.lastSeen
    end

    existing.professions = existing.professions or {}
    for profName, profData in pairs(incoming.professions or {}) do
        local prev = existing.professions[profName]
        local prevCount = prev and #(prev.recipes or {}) or -1
        local newCount = #(profData.recipes or {})
        local prevTime = prev and (prev.scannedAt or 0) or 0
        local newTime = profData.scannedAt or 0
        if (not prev) or (newTime >= prevTime) or (newCount > prevCount) then
            existing.professions[profName] = {
                skillLineID = profData.skillLineID or 0,
                scannedAt = newTime,
                recipes = profData.recipes or {},
            }
            changed = true
        end
    end

    db.syncProfiles[player] = existing
    db.syncCoverage[player] = now()
    return changed
end

local function sendOwnProfile()
    local db = ensureDB()
    local player = myNameRealm()
    local profile = db.syncProfiles[player]
    if not profile or not profile.professions then return end

    local profCount = 0
    for _ in pairs(profile.professions) do profCount = profCount + 1 end
    if profCount == 0 then return end

    local serialized = serializeProfile(player, profile)
    if not serialized or serialized == "" then return end

    local syncID = tostring(now()) .. tostring(math.random(1000, 9999))
    local chunks = splitString(serialized, 220)
    for i, chunk in ipairs(chunks) do
        local payload = table.concat({ syncID, tostring(i), tostring(#chunks), chunk }, SEP_F)
        GMT.SendComm("TMCHUNK", payload, "GUILD")
    end
    db.lastSyncSent = now()
    db.syncCoverage[player] = now()
end

local function requestGuildSync()
    GMT.SendComm("TMREQ", myNameRealm(), "GUILD")
    TM.state.lastHello = now()
    addLog("Requested guild profession sync")
end

local function buildGuildMapFromSync()
    buildRoster()
    local db = ensureDB()
    local results, profiles, professions, recipes = {}, 0, 0, 0

    for player, profile in pairs(db.syncProfiles or {}) do
        local profBucket = profile.professions or {}
        local hasAny = false
        for _, prof in pairs(profBucket) do
            if prof and #(prof.recipes or {}) > 0 then hasAny = true break end
        end
        if hasAny then profiles = profiles + 1 end

        for profName, prof in pairs(profBucket) do
            professions = professions + 1
            local roster = TM.state.roster[player] or TM.state.roster[normalizeName(player)]
            local recipeCount = #(prof.recipes or {})
            recipes = recipes + recipeCount
            table.insert(results, {
                name = normalizeName(player),
                fullName = roster and roster.fullName or player,
                profession = profName,
                skillLineID = prof.skillLineID or 0,
                skill = recipeCount,
                recipeCount = recipeCount,
                online = roster and roster.online or false,
                zone = roster and roster.zone or "",
                guid = roster and roster.guid or nil,
                class = roster and roster.class or "",
                rankName = roster and roster.rankName or "",
                level = roster and roster.level or 0,
                scannedAt = profile.lastSeen or prof.scannedAt or 0,
            })
        end
    end

    table.sort(results, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.profession ~= b.profession then return a.profession < b.profession end
        return (a.name or "") < (b.name or "")
    end)

    TM.state.guildMap = results
    TM.state.debug = { profiles = profiles, professions = professions, recipes = recipes, built = #results }
    if #results > 0 and (not TM.state.selectedCrafter) then TM.state.selectedCrafter = results[1] end
    if TM.state.selectedCrafter then
        local keepName = TM.state.selectedCrafter.fullName or TM.state.selectedCrafter.name
        local keepProf = TM.state.selectedCrafter.profession
        for _, entry in ipairs(results) do
            if (entry.fullName == keepName or entry.name == keepName) and entry.profession == keepProf then
                TM.state.selectedCrafter = entry
                break
            end
        end
    end

    db.lastGuildMapScan = now()
    if #results > 0 then
        setStatus("Guild talent map ready - profiles:" .. profiles .. " professions:" .. professions .. " recipes:" .. recipes .. " built:" .. #results, "green")
    else
        setStatus("No synced profession data yet. Open one of your profession windows and click Scan Selected Recipes.", nil)
    end
    return #results
end

local function getSelectedRecipeNames()
    local entry = TM.state.selectedCrafter
    if not entry then return {} end
    local profs = ensureDB().syncProfiles[(entry.fullName or entry.name)]
    profs = profs and profs.professions or nil
    local prof = profs and profs[entry.profession] or nil
    return (prof and prof.recipes) or {}
end

local function captureTradeSkillRecipes()
    local professionName, skillLineID
    local recipes = {}
    local seen = {}

    if GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        if ok and type(name) == "string" and name ~= "UNKNOWN" and name ~= "" then professionName = name end
    end

    if type(C_TradeSkillUI) == "table" and type(C_TradeSkillUI.GetAllRecipeIDs) == "function" and professionIsOpen() then
        local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
        if ok and type(ids) == "table" then
            for _, recipeID in ipairs(ids) do
                local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
                if info and info.name and info.name ~= "" and not info.isHeader then
                    if not seen[info.name] then
                        seen[info.name] = true
                        table.insert(recipes, info.name)
                    end
                end
            end
        end
    end

    if #recipes == 0 and TradeSkillFrame and TradeSkillFrame:IsShown() and GetNumTradeSkills and GetTradeSkillInfo then
        local num = GetNumTradeSkills() or 0
        for i = 1, num do
            local recipeName, recipeType = GetTradeSkillInfo(i)
            if recipeName and recipeType ~= "header" and recipeType ~= "subheader" and not seen[recipeName] then
                seen[recipeName] = true
                table.insert(recipes, recipeName)
            end
        end
    elseif #recipes == 0 and CraftFrame and CraftFrame:IsShown() and GetNumCrafts and GetCraftInfo then
        professionName = professionName or "Enchanting"
        local num = GetNumCrafts() or 0
        for i = 1, num do
            local recipeName, recipeType = GetCraftInfo(i)
            if recipeName and recipeType ~= "header" and recipeType ~= "subheader" and not seen[recipeName] then
                seen[recipeName] = true
                table.insert(recipes, recipeName)
            end
        end
    end

    if #recipes == 0 then return nil end
    table.sort(recipes)
    professionName = professionName or "Profession"
    return professionName, skillLineID or 0, recipes
end

local function scanOwnProfessionWindow(reason)
    local professionName, skillLineID, recipes = captureTradeSkillRecipes()
    if not recipes then
        setStatus("Open one of your profession windows first.", "red")
        return false
    end

    local db = ensureDB()
    local player = myNameRealm()
    db.syncProfiles[player] = db.syncProfiles[player] or { professions = {}, lastSeen = 0 }
    db.syncProfiles[player].professions = db.syncProfiles[player].professions or {}
    db.syncProfiles[player].professions[professionName] = {
        skillLineID = skillLineID or 0,
        scannedAt = now(),
        recipes = recipes,
    }
    db.syncProfiles[player].lastSeen = now()
    db.lastRecipeScan = now()

    addLog((reason or "Profession") .. " scan complete: " .. professionName .. " (" .. tostring(#recipes) .. ")")
    setStatus("Scanned " .. professionName .. " and synced to guild.", "green")
    db.syncCoverage[player] = now()
    sendOwnProfile()
    buildGuildMapFromSync()
    if refreshAll then refreshAll() end
    return true
end

local function querySelectedRecipes()
    local scanned = false
    if professionIsOpen() then scanned = scanOwnProfessionWindow("Recipe") or false end

    buildGuildMapFromSync()
    local entry = TM.state.selectedCrafter or TM.state.guildMap[1]
    if not entry then
        if scanned then
            entry = TM.state.guildMap[1]
            TM.state.selectedCrafter = entry
        end
    end

    if not entry then
        setStatus("No synced guild recipes yet. Open a profession window, then click Scan Selected Recipes.", "red")
    else
        TM.state.selectedCrafter = entry
        setStatus("Loaded synced recipes for " .. (entry.name or "selected crafter") .. ".", "green")
    end
    if refreshAll then refreshAll() end
end

local function scanMaterials()
    TM.state.materials = {}
    TM.state.pendingMaterialItems = {}
    TM.state.pendingMaterialRefresh = false
    local counts = {}
    local missing = 0

    for bag = 0, 4 do
        local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local itemID, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then itemID, count = info.itemID, info.stackCount end
            else
                itemID = GetContainerItemID and GetContainerItemID(bag, slot)
                local _, c = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
                count = c
            end
            if itemID then
                local name = GetItemInfo(itemID)
                if not name then
                    TM.state.pendingMaterialItems[itemID] = true
                    TM.state.pendingMaterialRefresh = true
                    missing = missing + 1
                else
                    counts[name] = (counts[name] or 0) + (tonumber(count or 1) or 1)
                end
            end
        end
    end

    for name, total in pairs(counts) do
        table.insert(TM.state.materials, {name = name, total = total, bucket = normalizeMaterialBucket(materialBucket(name))})
    end
    table.sort(TM.state.materials, function(a, b) return a.total > b.total end)
    ensureDB().materials = TM.state.materials
    ensureDB().lastMaterialScan = now()
    addLog("Material scan complete: " .. tostring(#TM.state.materials) .. " distinct items")
    if missing > 0 then
        setStatus("Material scan waiting on item data: " .. tostring(missing), nil)
    else
        setStatus("Material scan complete.", "green")
    end
    if refreshAll then refreshAll() end
end

local function saveTracked()
    local name = refs.trackName and refs.trackName:GetText() or ""
    local need = tonumber(refs.trackNeed and refs.trackNeed:GetText() or 0) or 0
    local have = tonumber(refs.trackHave and refs.trackHave:GetText() or 0) or 0
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        setStatus("Enter a craft name first.", "red")
        return
    end
    table.insert(ensureDB().tracked, 1, {name = name, target = need, have = have})
    if refs.trackName then refs.trackName:SetText("") end
    if refs.trackNeed then refs.trackNeed:SetText("") end
    if refs.trackHave then refs.trackHave:SetText("") end
    addLog("Tracked craft saved: " .. name)
    setStatus("Tracked craft saved.", "green")
    if refreshAll then refreshAll() end
end

local function removeTrackedSelected()
    if not refs.trackedSelected then
        setStatus("Select a tracked craft first.", "red")
        return
    end
    table.remove(ensureDB().tracked, refs.trackedSelected)
    refs.trackedSelected = nil
    addLog("Tracked craft removed")
    setStatus("Tracked craft removed.", "green")
    if refreshAll then refreshAll() end
end

local function saveNotes()
    ensureDB().notes = refs.notes and refs.notes:GetText() or ""
    addLog("Talent map notes saved")
    setStatus("Notes saved.", "green")
end

local function countCacheEntries()
    local count = 0
    for _, profile in pairs(ensureDB().syncProfiles or {}) do
        for _, prof in pairs(profile.professions or {}) do
            count = count + 1
        end
    end
    return count
end

local function renderSummary()
    local state = TM.state
    local profs, online = {}, 0
    for _, e in ipairs(state.guildMap) do
        profs[e.profession] = true
        if e.online then online = online + 1 end
    end
    local profCount = 0 for _ in pairs(profs) do profCount = profCount + 1 end
    local ready = 0
    for _, t in ipairs(ensureDB().tracked) do if (t.have or 0) >= (t.target or 0) and (t.target or 0) > 0 then ready = ready + 1 end end

    refs.sumProf:SetText(tostring(profCount))
    refs.sumCrafters:SetText(tostring(#state.guildMap))
    refs.sumOnline:SetText(tostring(online))
    refs.sumRecipes:SetText(tostring(countCacheEntries()))
    refs.sumMats:SetText(tostring(#state.materials))
    refs.sumTracked:SetText(tostring(#ensureDB().tracked))
    refs.sumReady:SetText(tostring(ready))
    local coverage = 0
    for _, _ in pairs(ensureDB().syncProfiles or {}) do coverage = coverage + 1 end
    refs.lastMapScan:SetText("Guild Scan: " .. fmtAgo(ensureDB().lastGuildMapScan) .. "  Coverage: " .. tostring(coverage))
    refs.lastRecipeScan:SetText("Recipe Scan: " .. fmtAgo(ensureDB().lastRecipeScan) .. "  Sync: " .. fmtAgo(ensureDB().lastSyncSent))
end

local function renderGuildMap()
    local content = refs.guildContent
    if not content then return end
    local width = content:GetWidth()
    local rows = refs.guildRows or {}
    refs.guildRows = rows
    for i, entry in ipairs(TM.state.guildMap) do
        local r = rows[i] or row(content, 0, width)
        rows[i] = r
        r:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * ROW_H))
        local selected = TM.state.selectedCrafter == entry
        if selected then
            r.bg:SetColorTexture(U(GMT.C.rowSel))
        else
            r.bg:SetColorTexture((i % 2 == 0 and 0.12 or 0.08), 0.10, 0.10, 0.16)
        end
        setRow(r, guildCols, {
            clip(entry.name, 18), clip(entry.profession, 18), tostring(entry.recipeCount or 0),
            entry.online and "Online" or "Offline", clip(entry.zone, 12),
        })
        r:SetScript("OnClick", function()
            TM.state.selectedCrafter = entry
            if refreshAll then refreshAll() end
        end)
    end
    for i = #TM.state.guildMap + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(20, #TM.state.guildMap * ROW_H + 4))
end

local function renderRecipes()
    local content = refs.recipeContent
    if not content then return end
    local width = content:GetWidth()
    local rows = refs.recipeRows or {}
    refs.recipeRows = rows
    local entry = TM.state.selectedCrafter
    refs.recipeTitle:SetText("Selected: " .. (entry and (entry.name .. " - " .. entry.profession) or "none"))
    local list = {}
    if entry then
        for _, name in ipairs(getSelectedRecipeNames()) do
            table.insert(list, {name = name, source = "Guild", ready = "Known"})
        end
    end
    for i, info in ipairs(list) do
        local r = rows[i] or row(content, 0, width)
        rows[i] = r
        r:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * ROW_H))
        r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.10, 0.10, 0.16)
        setRow(r, recipeCols, {clip(info.name, 46), info.source, info.ready})
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(20, #list * ROW_H + 4))
end

local function renderMaterials()
    local content = refs.matContent
    if not content then return end
    local width = content:GetWidth()
    local rows = refs.matRows or {}
    refs.matRows = rows
    for i, item in ipairs(TM.state.materials) do
        local r = rows[i] or row(content, 0, width)
        rows[i] = r
        r:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * ROW_H))
        r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.10, 0.10, 0.16)
        setRow(r, matCols, {clip(item.name, 22), tostring(item.total), clip(normalizeMaterialBucket(item.bucket), 14)})
    end
    for i = #TM.state.materials + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(20, #TM.state.materials * ROW_H + 4))
end

local function renderTracked()
    local content = refs.trackedContent
    if not content then return end
    local data = ensureDB().tracked
    local width = content:GetWidth()
    local rows = refs.trackedRows or {}
    refs.trackedRows = rows
    for i, item in ipairs(data) do
        local r = rows[i] or row(content, 0, width)
        rows[i] = r
        r:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * ROW_H))
        local selected = refs.trackedSelected == i
        if selected then
            r.bg:SetColorTexture(U(GMT.C.rowSel))
        else
            r.bg:SetColorTexture((i % 2 == 0 and 0.12 or 0.08), 0.10, 0.10, 0.16)
        end
        local ready = (item.target or 0) > 0 and (item.have or 0) >= (item.target or 0)
        setRow(r, trackedCols, {clip(item.name, 22), tostring(item.target or 0), tostring(item.have or 0), ready and "Ready" or "Build"})
        r:SetScript("OnClick", function() refs.trackedSelected = i; if refreshAll then refreshAll() end end)
    end
    for i = #data + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(20, #data * ROW_H + 4))
end

local function renderLogs()
    local content = refs.logContent
    if not content then return end
    local width = content:GetWidth()
    local rows = refs.logRows or {}
    refs.logRows = rows
    local log = ensureDB().log
    for i = 1, math.min(#log, 20) do
        local item = log[i]
        local r = rows[i] or row(content, 0, width)
        rows[i] = r
        r:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1) * ROW_H))
        r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.10, 0.10, 0.16)
        setRow(r, logCols, {clip(item.msg, 48)})
    end
    for i = math.min(#log, 20) + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(20, math.min(#log, 20) * ROW_H + 4))
end

refreshAll = function()
    renderSummary()
    renderGuildMap()
    renderRecipes()
    renderMaterials()
    renderTracked()
    renderLogs()
    if refs.notes and not refs.notes:HasFocus() then refs.notes:SetText(ensureDB().notes or "") end
end

local function onCommRequest(_, sender)
    if sender == myNameRealm() then return end
    C_Timer.After(0.6 + (math.random() * 0.8), sendOwnProfile)
end

local function onCommChunk(payload, sender)
    if sender == myNameRealm() then return end
    local parts = {}
    for part in string.gmatch((payload or "") .. SEP_F, "(.-)" .. SEP_F) do table.insert(parts, part) end
    local syncID, idx, total, chunk = parts[1], tonumber(parts[2]), tonumber(parts[3]), parts[4]
    if not syncID or not idx or not total then return end
    local inc = TM.state.incomingChunks[syncID] or { total = total, parts = {}, started = now(), sender = sender }
    inc.parts[idx] = chunk or ""
    inc.total = total
    TM.state.incomingChunks[syncID] = inc

    local complete = true
    for i = 1, total do if inc.parts[i] == nil then complete = false break end end
    if complete then
        local raw = table.concat(inc.parts)
        local player, profile = deserializeProfile(raw)
        if player and profile then
            if mergeProfile(player, profile) then
                addLog("Synced profession profile: " .. normalizeName(player))
            end
            buildGuildMapFromSync()
            if refreshAll then refreshAll() end
        end
        TM.state.incomingChunks[syncID] = nil
    end

    for id, info in pairs(TM.state.incomingChunks) do
        if (now() - (info.started or 0)) > 30 then TM.state.incomingChunks[id] = nil end
    end
end

local function onEvent(_, event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success ~= false and itemID and TM.state.pendingMaterialItems[itemID] then
            TM.state.pendingMaterialItems[itemID] = nil
            local stillPending = false
            for _ in pairs(TM.state.pendingMaterialItems) do stillPending = true break end
            if not stillPending and TM.state.pendingMaterialRefresh then
                TM.state.pendingMaterialRefresh = false
                scanMaterials()
            end
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "CRAFT_SHOW" then
        C_Timer.After(0.5, function() scanOwnProfessionWindow("Profession") end)
    elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
        buildGuildMapFromSync()
        if refreshAll then refreshAll() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(4.0, function()
            requestGuildSync()
            buildGuildMapFromSync()
            if refreshAll then refreshAll() end
        end)
    end
end

function GMT_TalentMap_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel and GMT_GetPanel("Crafting")
        if not panel or panel._talentMapBuilt then return end
        panel._talentMapBuilt = true
        ensureDB()
        buildRoster()

        GMT.RegComm("TMREQ", onCommRequest)
        GMT.RegComm("TMCHUNK", onCommChunk)

        GMT.Header(panel, "Guild Professions", 14, -12)
        GMT.Label(panel, "Guild profession intelligence . scan your profession window . sync recipes to guild . view who crafts what", 16, -36)
        GMT.HLine(panel, 8, -50, GMT.PW - 16)

        local summary = section(panel, "Guild Profession Intelligence", 8, -64, 936, 76)
        local guildBox = section(panel, "Guild Crafter Coverage", 8, -148, 414, 174)
        local recipeBox = section(panel, "Selected Crafter Recipes", 430, -148, 514, 174)
        local matsBox = section(panel, "Material Snapshot", 8, -330, 300, 180)
        local trackBox = section(panel, "Tracked Crafts", 316, -330, 312, 180)
        local notesBox = section(panel, "Guild Profession Notes", 636, -330, 308, 86)
        local logBox = section(panel, "Activity Log", 636, -424, 308, 86)

        local s1 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s1:SetPoint("TOPLEFT", summary, "TOPLEFT", 14, -31) s1:SetText("Professions")
        refs.sumProf = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumProf:SetPoint("LEFT", s1, "RIGHT", 8, 0)
        local s2 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s2:SetPoint("LEFT", refs.sumProf, "RIGHT", 26, 0) s2:SetText("Crafters")
        refs.sumCrafters = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumCrafters:SetPoint("LEFT", s2, "RIGHT", 8, 0)
        local s3 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s3:SetPoint("LEFT", refs.sumCrafters, "RIGHT", 26, 0) s3:SetText("Online")
        refs.sumOnline = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumOnline:SetPoint("LEFT", s3, "RIGHT", 8, 0)
        local s4 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s4:SetPoint("LEFT", refs.sumOnline, "RIGHT", 26, 0) s4:SetText("Recipe Cache")
        refs.sumRecipes = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumRecipes:SetPoint("LEFT", s4, "RIGHT", 8, 0)

        local s5 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s5:SetPoint("TOPLEFT", summary, "TOPLEFT", 14, -52) s5:SetText("Material Buckets")
        refs.sumMats = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumMats:SetPoint("LEFT", s5, "RIGHT", 8, 0)
        local s6 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s6:SetPoint("LEFT", refs.sumMats, "RIGHT", 26, 0) s6:SetText("Tracked")
        refs.sumTracked = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumTracked:SetPoint("LEFT", s6, "RIGHT", 8, 0)
        local s7 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s7:SetPoint("LEFT", refs.sumTracked, "RIGHT", 26, 0) s7:SetText("Ready")
        refs.sumReady = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight") refs.sumReady:SetPoint("LEFT", s7, "RIGHT", 8, 0)

        refs.lastMapScan = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        refs.lastMapScan:SetPoint("TOPRIGHT", summary, "TOPRIGHT", -150, -12)
        refs.lastMapScan:SetTextColor(U(GMT.C.txtDim))
        refs.lastRecipeScan = summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        refs.lastRecipeScan:SetPoint("TOPRIGHT", summary, "TOPRIGHT", -18, -12)
        refs.lastRecipeScan:SetTextColor(U(GMT.C.txtDim))

        local scanMat = GMT.MBtn(summary, "Scan Materials", 110, 22)
        scanMat:SetPoint("TOPRIGHT", summary, "TOPRIGHT", -18, -40)
        scanMat:SetScript("OnClick", scanMaterials)
        local scanRecipe = GMT.MBtn(summary, "Scan Selected Recipes", 138, 22)
        scanRecipe:SetPoint("RIGHT", scanMat, "LEFT", -8, 0)
        scanRecipe:SetScript("OnClick", querySelectedRecipes)
        local scanGuild = GMT.MBtn(summary, "Refresh Guild Map", 132, 22)
        scanGuild:SetPoint("RIGHT", scanRecipe, "LEFT", -8, 0)
        scanGuild:SetScript("OnClick", function()
            if professionIsOpen() then scanOwnProfessionWindow("Map") end
            buildGuildMapFromSync()
            requestGuildSync()
            setStatus("Guild sync requested. Profiles will populate as guild replies arrive.", nil)
            if refreshAll then refreshAll() end
            C_Timer.After(2.0, function() buildGuildMapFromSync(); if refreshAll then refreshAll() end end)
            C_Timer.After(5.0, function() buildGuildMapFromSync(); if refreshAll then refreshAll() end end)
        end)

        local _, guildContent = makeScrollList(guildBox, 8, -28, 398, 138, guildCols)
        refs.guildContent = guildContent
        refs.recipeTitle = recipeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.recipeTitle:SetPoint("TOPLEFT", recipeBox, "TOPLEFT", 12, -30)
        refs.recipeTitle:SetTextColor(U(GMT.C.txtDim))
        refs.recipeTitle:SetText("Selected: none")
        local _, recipeContent = makeScrollList(recipeBox, 8, -46, 498, 120, recipeCols)
        refs.recipeContent = recipeContent
        local _, matContent = makeScrollList(matsBox, 8, -28, 284, 144, matCols)
        refs.matContent = matContent

        label(trackBox, "Craft", 10, -30)
        refs.trackName = input(trackBox, 10, -46, 134, 20)
        label(trackBox, "Need", 152, -30)
        refs.trackNeed = input(trackBox, 152, -46, 46, 20)
        label(trackBox, "Have", 206, -30)
        refs.trackHave = input(trackBox, 206, -46, 46, 20)
        local addBtn = GMT.MBtn(trackBox, "Save", 52, 20)
        addBtn:SetPoint("TOPLEFT", trackBox, "TOPLEFT", 258, -45)
        addBtn:SetScript("OnClick", saveTracked)
        local _, trackedContent = makeScrollList(trackBox, 8, -72, 296, 98, trackedCols)
        refs.trackedContent = trackedContent
        local removeBtn = GMT.MBtn(trackBox, "Remove Selected", 116, 20)
        removeBtn:SetPoint("BOTTOMLEFT", trackBox, "BOTTOMLEFT", 10, 8)
        removeBtn:SetScript("OnClick", removeTrackedSelected)

        refs.notes = multiInput(notesBox, 10, -30, 288, 26)
        refs.notes:SetText(ensureDB().notes or "")
        local saveNotesBtn = GMT.MBtn(notesBox, "Save Notes", 90, 20)
        saveNotesBtn:SetPoint("BOTTOMRIGHT", notesBox, "BOTTOMRIGHT", -10, 8)
        saveNotesBtn:SetScript("OnClick", saveNotes)
        local _, logContent = makeScrollList(logBox, 8, -28, 292, 50, logCols)
        refs.logContent = logContent

        refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 8)
        refs.status:SetTextColor(U(GMT.C.amber))
        refs.status:SetText("Open a profession window, then click Scan Selected Recipes.")

        eventFrame = eventFrame or CreateFrame("Frame")
        eventFrame:UnregisterAllEvents()
        for _, evt in ipairs({"GET_ITEM_INFO_RECEIVED", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD"}) do
            eventFrame:RegisterEvent(evt)
        end
        eventFrame:SetScript("OnEvent", onEvent)

        TM.state.materials = ensureDB().materials or {}
        for _, item in ipairs(TM.state.materials) do
            item.bucket = normalizeMaterialBucket(item.bucket)
        end
        ensureDB().materials = TM.state.materials
        buildGuildMapFromSync()
        refreshAll()
        C_Timer.After(2.0, function() requestGuildSync() end)
    end)

    if not ok and GMT and GMT.Err then GMT.Err("TalentMap init failed: " .. tostring(err)) end
end
