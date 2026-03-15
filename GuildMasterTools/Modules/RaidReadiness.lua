-- ============================================================
-- GuildMaster Tools  |  Modules/RaidReadiness.lua  |  v2.4.0
-- Raid Prep Core
-- ============================================================
local _, GMT = ...

GMT.RP = GMT.RP or {}
local RP = GMT.RP

local refs = {}
local ROW_H = 20

RP.rows = RP.rows or {}
RP.selected = RP.selected or {}

local function EnsureDB()
    GMT.DB.raidReadiness = GMT.DB.raidReadiness or {}
    local db = GMT.DB.raidReadiness
    db.rules = db.rules or {}
    if db.rules.minDurability == nil then db.rules.minDurability = 75 end
    if db.rules.requireFood == nil then db.rules.requireFood = true end
    if db.rules.requireFlask == nil then db.rules.requireFlask = true end
    if db.rules.requireRune == nil then db.rules.requireRune = false end
    if db.rules.requireWeaponBuff == nil then db.rules.requireWeaponBuff = false end
    db.lastScan = db.lastScan or 0
    return db
end

local function SetStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Ready")
    if kind == "green" then
        refs.status:SetTextColor(GMT.U(GMT.C.green))
    elseif kind == "red" then
        refs.status:SetTextColor(GMT.U(GMT.C.red))
    else
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
    end
end

local function HasAnyBuff(unit, patterns)
    if not unit or not UnitExists(unit) then return false end
    for i = 1, 40 do
        local name = nil
        if AuraUtil and AuraUtil.FindAuraByIndex then
            local ok, aura = pcall(AuraUtil.FindAuraByIndex, i, unit, "HELPFUL")
            if ok and aura then
                if type(aura) == "table" then
                    name = aura.name
                elseif type(aura) == "string" then
                    name = aura
                end
            end
        end
        if not name and UnitBuff then
            local ok, buffName = pcall(UnitBuff, unit, i)
            if ok then name = buffName end
        end
        if not name then break end
        local lower = string.lower(tostring(name))
        for _, p in ipairs(patterns) do
            if string.find(lower, p, 1, true) then
                return true, name
            end
        end
    end
    return false, nil
end

local FOOD_PATTERNS = {
    "well fed", "fed", "feast", "banquet", "food"
}
local FLASK_PATTERNS = {
    "flask", "phial"
}
local RUNE_PATTERNS = {
    "rune", "augmentation"
}
local WEAPON_PATTERNS = {
    "sharpen", "weightstone", "oil", "poison", "weapon"
}

local function GetDurabilityPercent()
    local cur, max = 0, 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local c, m = GetInventoryItemDurability(slot)
            if c and m then
                cur = cur + c
                max = max + m
            end
        end
    end
    if max == 0 then return 100 end
    return math.floor((cur / max) * 100 + 0.5)
end

local function UnitTokenForRosterIndex(i)
    if IsInRaid() then
        return "raid" .. i
    end
    if GetNumSubgroupMembers() > 0 then
        if i == 1 then return "player" end
        return "party" .. (i - 1)
    end
    return i == 1 and "player" or nil
end

local function GetRosterSize()
    if IsInRaid() then
        return GetNumGroupMembers()
    end
    local party = GetNumSubgroupMembers()
    if party > 0 then return party + 1 end
    return 1
end

local function FlagText(ok)
    return ok and GMT.Green("OK") or GMT.Red("Missing")
end

local function BuildRow(unit)
    local name = GetUnitName(unit, true) or UnitName(unit) or "Unknown"
    local _, classFile = UnitClass(unit)
    local role = UnitGroupRolesAssigned(unit)
    if not role or role == "NONE" then role = "-" end
    local online = UnitIsConnected(unit)
    local dead = UnitIsDeadOrGhost(unit)

    local hasFood = HasAnyBuff(unit, FOOD_PATTERNS)
    local hasFlask = HasAnyBuff(unit, FLASK_PATTERNS)
    local hasRune = HasAnyBuff(unit, RUNE_PATTERNS)
    local hasWeapon = HasAnyBuff(unit, WEAPON_PATTERNS)

    local durability = unit == "player" and GetDurabilityPercent() or -1
    local problems = 0
    local db = EnsureDB()

    if db.rules.requireFood and not hasFood then problems = problems + 1 end
    if db.rules.requireFlask and not hasFlask then problems = problems + 1 end
    if db.rules.requireRune and not hasRune then problems = problems + 1 end
    if db.rules.requireWeaponBuff and not hasWeapon then problems = problems + 1 end
    if durability >= 0 and durability < (db.rules.minDurability or 75) then problems = problems + 1 end
    if not online or dead then problems = problems + 1 end

    return {
        unit = unit,
        name = name,
        short = GMT.Short(name),
        class = classFile or "",
        role = role,
        online = online,
        dead = dead,
        food = hasFood and true or false,
        flask = hasFlask and true or false,
        rune = hasRune and true or false,
        weapon = hasWeapon and true or false,
        durability = durability,
        problems = problems,
    }
end

local function SortRows()
    table.sort(RP.rows, function(a, b)
        if a.problems ~= b.problems then
            return a.problems > b.problems
        end
        if a.role ~= b.role then
            return a.role < b.role
        end
        return a.short < b.short
    end)
end

local function RefreshSummary()
    local total, ready, missingFood, missingFlask, lowDur = 0, 0, 0, 0, 0
    local db = EnsureDB()

    for _, row in ipairs(RP.rows) do
        total = total + 1
        local issues = 0
        if db.rules.requireFood and not row.food then missingFood = missingFood + 1; issues = issues + 1 end
        if db.rules.requireFlask and not row.flask then missingFlask = missingFlask + 1; issues = issues + 1 end
        if row.durability >= 0 and row.durability < (db.rules.minDurability or 75) then lowDur = lowDur + 1; issues = issues + 1 end
        if issues == 0 then ready = ready + 1 end
    end

    if refs.sumReady then refs.sumReady:SetText(GMT.Green(tostring(ready) .. "/" .. tostring(total))) end
    if refs.sumFood then refs.sumFood:SetText(missingFood > 0 and GMT.Red(tostring(missingFood)) or GMT.Green("0")) end
    if refs.sumFlask then refs.sumFlask:SetText(missingFlask > 0 and GMT.Red(tostring(missingFlask)) or GMT.Green("0")) end
    if refs.sumDur then refs.sumDur:SetText(lowDur > 0 and GMT.Amber(tostring(lowDur)) or GMT.Green("0")) end
end

local cols = {
    { label="",        w=20,  j="CENTER" },
    { label="Name",    w=150, j="LEFT"   },
    { label="Role",    w=56,  j="LEFT"   },
    { label="Food",    w=62,  j="LEFT"   },
    { label="Flask",   w=62,  j="LEFT"   },
    { label="Rune",    w=62,  j="LEFT"   },
    { label="Weapon",  w=72,  j="LEFT"   },
    { label="Dur %",   w=56,  j="CENTER" },
    { label="State",   w=96,  j="LEFT"   },
}

local function MakeScrollList(parent, x, y, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    frame:SetBackdropColor(GMT.U(GMT.C.panelBg))
    frame:SetBackdropBorderColor(GMT.U(GMT.C.brass))

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetSize(w - 8, 18)
    local hb = header:CreateTexture(nil, "BACKGROUND")
    hb:SetAllPoints()
    hb:SetColorTexture(GMT.U(GMT.C.cardHead))

    local cx = 4
    for _, col in ipairs(cols) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", header, "LEFT", cx, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetTextColor(GMT.U(GMT.C.txtTitle))
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

local function Row(content, y, w)
    local btn = CreateFrame("Button", nil, content)
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    btn:SetSize(w, ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.texts = {}
    return btn
end

local function SetRow(row, values)
    local x = 4
    for i, col in ipairs(cols) do
        local fs = row.texts[i]
        if not fs then
            fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.texts[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(values[i] or "")
        x = x + col.w
    end
end

local function RefreshRows()
    if not refs.content then return end
    refs.rowFrames = refs.rowFrames or {}
    local frames = refs.rowFrames

    for i, data in ipairs(RP.rows) do
        local row = frames[i]
        if not row then
            row = Row(refs.content, -((i - 1) * ROW_H), 650)
            frames[i] = row
        end
        local selected = RP.selected[data.short]
        row.bg:SetColorTexture(selected and 0.18 or 0.08, selected and 0.22 or 0.06, 0.05, selected and 0.70 or ((i % 2 == 0) and 0.34 or 0.14))
        row:Show()

        local state
        if not data.online then
            state = GMT.Red("Offline")
        elseif data.dead then
            state = GMT.Red("Dead")
        elseif data.problems == 0 then
            state = GMT.Green("Ready")
        else
            state = GMT.Amber(tostring(data.problems) .. " issue")
        end

        local durText = data.durability >= 0 and tostring(data.durability) or "-"
        if data.durability >= 0 and data.durability < (EnsureDB().rules.minDurability or 75) then
            durText = GMT.Amber(durText)
        end

        SetRow(row, {
            selected and GMT.Green("x") or "",
            GMT.ClassStr(data.class or "", data.short),
            data.role or "-",
            FlagText(data.food),
            FlagText(data.flask),
            FlagText(data.rune),
            FlagText(data.weapon),
            durText,
            state,
        })

        row:SetScript("OnClick", function()
            RP.selected[data.short] = not RP.selected[data.short]
            RefreshRows()
        end)
    end

    for i = #RP.rows + 1, #frames do
        frames[i]:Hide()
    end

    refs.content:SetHeight(math.max(30, #RP.rows * ROW_H))
end

local function RunScan()
    RP.rows = {}
    RP.selected = {}

    local size = GetRosterSize()
    for i = 1, size do
        local unit = UnitTokenForRosterIndex(i)
        if unit and UnitExists(unit) then
            table.insert(RP.rows, BuildRow(unit))
        end
    end

    SortRows()
    EnsureDB().lastScan = time()
    RefreshSummary()
    RefreshRows()
    SetStatus("Raid Prep scan complete: " .. tostring(#RP.rows) .. " player(s).", "green")
end

local function BuildMissingText(targetRow)
    local db = EnsureDB()
    local missing = {}
    if db.rules.requireFood and not targetRow.food then table.insert(missing, "Food") end
    if db.rules.requireFlask and not targetRow.flask then table.insert(missing, "Flask") end
    if db.rules.requireRune and not targetRow.rune then table.insert(missing, "Rune") end
    if db.rules.requireWeaponBuff and not targetRow.weapon then table.insert(missing, "Weapon Buff") end
    if targetRow.durability >= 0 and targetRow.durability < (db.rules.minDurability or 75) then
        table.insert(missing, "Repair")
    end
    if #missing == 0 then
        return "You look raid ready."
    end
    return "Raid Prep check: missing " .. table.concat(missing, ", ") .. "."
end

local function GetSelectedRows()
    local out = {}
    for _, row in ipairs(RP.rows) do
        if RP.selected[row.short] then
            table.insert(out, row)
        end
    end
    return out
end

local function WhisperSelected()
    local picked = GetSelectedRows()
    if #picked == 0 then
        SetStatus("Select at least one player first.", "red")
        return
    end
    for _, row in ipairs(picked) do
        if row.unit ~= "player" then
            local msg = BuildMissingText(row)
            SendChatMessage(msg, "WHISPER", nil, row.name)
        end
    end
    SetStatus("Whispered " .. tostring(#picked) .. " player(s).", "green")
end

local function AnnounceMissing()
    local chan = IsInRaid() and "RAID" or ((GetNumSubgroupMembers() > 0) and "PARTY" or "SAY")
    local lines = {}
    for _, row in ipairs(RP.rows) do
        if row.problems > 0 then
            table.insert(lines, row.short .. ": " .. BuildMissingText(row):gsub("Raid Prep check: missing ", ""))
        end
    end
    if #lines == 0 then
        SendChatMessage("Raid Prep: everyone currently scanned looks ready.", chan)
        SetStatus("Announced ready state.", "green")
        return
    end
    SendChatMessage("Raid Prep missing checks:", chan)
    for i = 1, math.min(#lines, 5) do
        SendChatMessage(lines[i], chan)
    end
    SetStatus("Announced missing prep items.", "green")
end

local function MakeSection(parent, title, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    box:SetBackdropColor(GMT.U(GMT.C.cardBg))
    box:SetBackdropBorderColor(GMT.U(GMT.C.copper))

    local head = box:CreateTexture(nil, "BACKGROUND")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    head:SetSize(w - 6, 22)
    head:SetColorTexture(GMT.U(GMT.C.cardHead))

    local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -7)
    fs:SetTextColor(GMT.U(GMT.C.txtTitle))
    fs:SetText(title)

    GMT.Rivets(box, 6, 4)
    return box
end

function GMT_RaidReadiness_Init()
    local ok, err = pcall(function()
    local panel = GMT_GetPanel("Raid Prep")
    if not panel or panel._raidPrepBuilt then return end
    panel._raidPrepBuilt = true

    EnsureDB()

    GMT.Header(panel, "Raid Prep Core", 14, -10)
    GMT.Label(panel, "Roster scan, consumable checks, durability, and leader actions", 16, -34)
    GMT.HLine(panel, 8, -48, GMT.PW - 16)

    local summary = MakeSection(panel, "Raid Summary", 8, -58, 936, 70)
    local actions = MakeSection(panel, "Leader Actions", 8, -136, 936, 62)
    local tableBox = MakeSection(panel, "Raid Prep Roster", 8, -206, 936, 200)

    local s1 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s1:SetPoint("TOPLEFT", summary, "TOPLEFT", 14, -34)
    s1:SetText("Ready")
    refs.sumReady = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refs.sumReady:SetPoint("LEFT", s1, "RIGHT", 12, 0)

    local s2 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s2:SetPoint("LEFT", refs.sumReady, "RIGHT", 48, 0)
    s2:SetText("Missing Food")
    refs.sumFood = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refs.sumFood:SetPoint("LEFT", s2, "RIGHT", 12, 0)

    local s3 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s3:SetPoint("LEFT", refs.sumFood, "RIGHT", 48, 0)
    s3:SetText("Missing Flask")
    refs.sumFlask = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refs.sumFlask:SetPoint("LEFT", s3, "RIGHT", 12, 0)

    local s4 = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s4:SetPoint("LEFT", refs.sumFlask, "RIGHT", 48, 0)
    s4:SetText("Low Durability")
    refs.sumDur = summary:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refs.sumDur:SetPoint("LEFT", s4, "RIGHT", 12, 0)

    local scanBtn = GMT.MBtn(actions, "Scan Raid", 110, 24)
    scanBtn:SetPoint("TOPLEFT", actions, "TOPLEFT", 14, -28)
    scanBtn:SetScript("OnClick", RunScan)

    local refreshBtn = GMT.MBtn(actions, "Refresh", 110, 24)
    refreshBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
    refreshBtn:SetScript("OnClick", RunScan)

    local announceBtn = GMT.MBtn(actions, "Announce Missing", 130, 24)
    announceBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
    announceBtn:SetScript("OnClick", AnnounceMissing)

    local whisperBtn = GMT.MBtn(actions, "Whisper Selected", 130, 24)
    whisperBtn:SetPoint("LEFT", announceBtn, "RIGHT", 8, 0)
    whisperBtn:SetScript("OnClick", WhisperSelected)

    local note = actions:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("LEFT", whisperBtn, "RIGHT", 16, 0)
    note:SetTextColor(GMT.U(GMT.C.txtDim))
    note:SetText("Select names in the roster, then whisper reminders.")

    local _, content = MakeScrollList(tableBox, 8, -28, 920, 164)
    refs.content = content

    refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
    refs.status:SetTextColor(GMT.U(GMT.C.amber))
    refs.status:SetText("Raid Prep ready.")

    panel:SetScript("OnShow", function()
        RefreshSummary()
        RefreshRows()
    end)

    local ok2, err2 = pcall(RunScan)
    if not ok2 then
        SetStatus("Raid Prep loaded, but scan failed. Use Scan Raid.", "red")
        if GMT and GMT.Err then
            GMT.Err("Raid Prep scan failed: " .. tostring(err2))
        end
    end
    end)
    if not ok and GMT and GMT.Err then
        GMT.Err("Raid Prep init failed: " .. tostring(err))
    end
end

-- ============================================================
-- PHASE 11 -- Raid Leader Tools
-- Appended to GMT_RaidReadiness_Init post-build via panel:SetScript
-- broadcast alerts . pull timer . role check . status monitor
-- ============================================================
local function Phase11_Build(panel)
    -- Shrink tableBox to 220 to free space (already built at 260, we add BELOW it)
    -- Phase 11 section sits at y=-(58+70+8+62+8+220+8) = -434, h=80
    local leaderBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    leaderBox:SetSize(936, 82)
    leaderBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -414)
    leaderBox:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=32,edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    leaderBox:SetBackdropColor(GMT.U(GMT.C.cardBg))
    leaderBox:SetBackdropBorderColor(GMT.U(GMT.C.copper))

    local head = leaderBox:CreateTexture(nil,"BACKGROUND")
    head:SetPoint("TOPLEFT",  leaderBox,"TOPLEFT",   3,-3)
    head:SetPoint("TOPRIGHT", leaderBox,"TOPRIGHT", -3,-3)
    head:SetHeight(24)
    head:SetColorTexture(GMT.U(GMT.C.cardHead))

    local hdiv = leaderBox:CreateTexture(nil,"ARTWORK")
    hdiv:SetPoint("TOPLEFT",  leaderBox,"TOPLEFT",   3,-27)
    hdiv:SetPoint("TOPRIGHT", leaderBox,"TOPRIGHT", -3,-27)
    hdiv:SetHeight(1)
    hdiv:SetColorTexture(GMT.U(GMT.C.copper))
    hdiv:SetAlpha(0.85)

    local tf = leaderBox:CreateFontString(nil,"OVERLAY","GameFontNormal")
    tf:SetPoint("TOPLEFT",leaderBox,"TOPLEFT",10,-8)
    tf:SetTextColor(GMT.U(GMT.C.txtTitle))
    tf:SetText("Raid Leader Tools")
    GMT.Rivets(leaderBox,6,4)

    -- Pull countdown timer (5-second pull timer, sends /ra message)
    local pullCountdown = 5
    local pullTimer = nil
    local pullBtn = GMT.MBtn(leaderBox, "Pull Timer (5s)", 130, 22)
    pullBtn:SetPoint("TOPLEFT", leaderBox, "TOPLEFT", 14, -38)
    pullBtn:SetScript("OnClick", function()
        if pullTimer then return end
        local count = pullCountdown
        local chan = IsInRaid() and "RAID" or (GetNumSubgroupMembers()>0 and "PARTY" or "SAY")
        local function tick()
            if count > 0 then
                SendChatMessage("Pull in "..count.."...", chan)
                count = count - 1
                pullTimer = C_Timer.After(1, tick)
            else
                SendChatMessage("PULL!", chan)
                pullTimer = nil
                pullBtn:SetText("Pull Timer (5s)")
            end
        end
        pullBtn:SetText("Pulling...")
        tick()
    end)

    -- Role check broadcast
    local roleBtn = GMT.MBtn(leaderBox, "Role Check", 110, 22)
    roleBtn:SetPoint("LEFT", pullBtn, "RIGHT", 8, 0)
    roleBtn:SetScript("OnClick", function()
        local chan = IsInRaid() and "RAID" or (GetNumSubgroupMembers()>0 and "PARTY" or "SAY")
        SendChatMessage("Role check -- please confirm your role assignment.", chan)
        if InitiateRolePoll then pcall(InitiateRolePoll) end
        GMT.Print("Role check initiated.")
    end)

    -- Ready check
    local rcBtn = GMT.MBtn(leaderBox, "Ready Check", 110, 22)
    rcBtn:SetPoint("LEFT", roleBtn, "RIGHT", 8, 0)
    rcBtn:SetScript("OnClick", function()
        if DoReadyCheck then pcall(DoReadyCheck) end
        GMT.Print("Ready check sent.")
    end)

    -- Alert: announce all missing prep to raid
    local alertBtn = GMT.MBtn(leaderBox, "Alert Missing", 120, 22)
    alertBtn:SetPoint("LEFT", rcBtn, "RIGHT", 8, 0)
    alertBtn:SetScript("OnClick", function()
        if AnnounceMissing then pcall(AnnounceMissing)
        else GMT.Warn("Run a Raid Scan first.") end
    end)

    -- Status monitor badge
    local monLabel = leaderBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    monLabel:SetPoint("LEFT", alertBtn, "RIGHT", 16, 0)
    monLabel:SetTextColor(GMT.U(GMT.C.txtDim))
    local function UpdateMonitor()
        local inRaid = IsInRaid()
        local size   = inRaid and GetNumGroupMembers() or (GetNumSubgroupMembers()>0 and GetNumSubgroupMembers()+1 or 0)
        local leader = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
        local status = inRaid and GMT.Green("Raid") or (size>0 and GMT.Amber("Party") or GMT.Dim("Solo"))
        local role   = leader and GMT.Amber("Leader/Assist") or GMT.Dim("Member")
        monLabel:SetText(status.."  "..GMT.Dim(tostring(size).." players").."  "..role)
    end
    UpdateMonitor()
    local monFrame = CreateFrame("Frame")
    monFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    monFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    monFrame:SetScript("OnEvent", UpdateMonitor)
end

-- Hook Phase 11 onto the existing panel after it's built
local _origRaidInit = GMT_RaidReadiness_Init
GMT_RaidReadiness_Init = function()
    _origRaidInit()
    local panel = GMT_GetPanel("Raid Prep")
    if panel and not panel._phase11Built then
        panel._phase11Built = true
        Phase11_Build(panel)
    end
end
