-- ============================================================
-- GuildMaster Tools  |  Modules/RaidPerf.lua  |  v3.2.0
-- Phase 9 -- Raid Performance Predictor
--
-- Recruit scoring . Baseline performance profiles
-- Role readiness . Predicted raid impact . Comparative analysis
-- Scoring breakdown . History tracking . Officer notes
-- ============================================================
local _, GMT = ...

GMT.PF = GMT.PF or {}
local PF = GMT.PF

local refs  = {}
local ROW_H = 20

-- ============================================================
-- SCORING WEIGHTS
-- Each check contributes points toward a 0 100 readiness score
-- ============================================================
local WEIGHTS = {
    online     = 20,   -- connected + alive
    flask      = 18,   -- flask / phial buff active
    food       = 18,   -- well fed buff active
    durability = 14,   -- gear durability   threshold
    rune       = 12,   -- augmentation rune
    weapon     = 10,   -- weapon buff (oil/sharpening)
    role       = 8,    -- has an assigned role
}
-- Max possible = sum of all weights = 100

local ROLE_LABEL = {
    TANK    = GMT.C and "|cff4499ffTank|r"   or "Tank",
    HEALER  = GMT.C and "|cff44ee88Healer|r" or "Healer",
    DAMAGER = GMT.C and "|cffff9944DPS|r"    or "DPS",
}

-- ============================================================
-- DB
-- ============================================================
local function EnsureDB()
    GMT.DB.raidPerf = GMT.DB.raidPerf or {}
    local db = GMT.DB.raidPerf
    db.profiles  = db.profiles  or {}   -- saved player performance snapshots
    db.recruits  = db.recruits  or {}   -- scored recruit entries
    db.baseline  = db.baseline  or {}   -- guild average per role
    db.notes     = db.notes     or {}   -- officer notes per player
    db.log       = db.log       or {}
    db.thresholds = db.thresholds or {
        minScore  = 60,    -- minimum score to flag as "raid ready"
        minDur    = 75,    -- durability %
    }
    return db
end

local function AddLog(msg)
    local db = EnsureDB()
    table.insert(db.log, 1, { t=time(), msg=msg })
    while #db.log > 50 do table.remove(db.log) end
end

local function SetStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Ready")
    if     kind=="green" then refs.status:SetTextColor(GMT.U(GMT.C.green))
    elseif kind=="red"   then refs.status:SetTextColor(GMT.U(GMT.C.red))
    else                      refs.status:SetTextColor(GMT.U(GMT.C.amber))
    end
end

-- ============================================================
-- SCORING ENGINE
-- ============================================================

-- Score a data row (from RP.rows OR a recruit profile dict)
-- Returns score 0-100, breakdown table
local function ScorePlayer(data, thresholds)
    thresholds = thresholds or EnsureDB().thresholds
    local score    = 0
    local breakdown = {}

    -- Online + alive
    local alive = data.online and not data.dead
    if alive then
        score = score + WEIGHTS.online
        breakdown.online = { pts=WEIGHTS.online, ok=true, label="Connected" }
    else
        breakdown.online = { pts=0, ok=false,
            label = not data.online and "Offline" or "Dead" }
    end

    -- Flask
    if data.flask then
        score = score + WEIGHTS.flask
        breakdown.flask = { pts=WEIGHTS.flask, ok=true, label="Flask/Phial" }
    else
        breakdown.flask = { pts=0, ok=false, label="No Flask" }
    end

    -- Food
    if data.food then
        score = score + WEIGHTS.food
        breakdown.food = { pts=WEIGHTS.food, ok=true, label="Well Fed" }
    else
        breakdown.food = { pts=0, ok=false, label="No Food" }
    end

    -- Durability (only if we have a real value)
    local minDur = thresholds.minDur or 75
    if data.durability and data.durability >= 0 then
        if data.durability >= minDur then
            score = score + WEIGHTS.durability
            breakdown.dur = { pts=WEIGHTS.durability, ok=true,
                label="Dur "..data.durability.."%" }
        else
            breakdown.dur = { pts=0, ok=false,
                label="Low Dur "..data.durability.."%" }
        end
    else
        -- Unknown durability (remote player): award partial
        score = score + math.floor(WEIGHTS.durability * 0.6)
        breakdown.dur = { pts=math.floor(WEIGHTS.durability * 0.6), ok=true,
            label="Dur N/A" }
    end

    -- Rune
    if data.rune then
        score = score + WEIGHTS.rune
        breakdown.rune = { pts=WEIGHTS.rune, ok=true, label="Rune" }
    else
        breakdown.rune = { pts=0, ok=false, label="No Rune" }
    end

    -- Weapon buff
    if data.weapon then
        score = score + WEIGHTS.weapon
        breakdown.weapon = { pts=WEIGHTS.weapon, ok=true, label="Weapon Buff" }
    else
        breakdown.weapon = { pts=0, ok=false, label="No Wep Buff" }
    end

    -- Role assigned
    local role = data.role or data.assignedRole or "-"
    if role ~= "-" and role ~= "" and role ~= "NONE" then
        score = score + WEIGHTS.role
        breakdown.role = { pts=WEIGHTS.role, ok=true, label=role }
    else
        breakdown.role = { pts=0, ok=false, label="No Role" }
    end

    return math.min(100, score), breakdown
end

-- Score color: 80+ green, 60-79 amber, <60 red
local function ScoreColor(score)
    if score >= 80 then return GMT.Green(tostring(score))
    elseif score >= 60 then return GMT.Amber(tostring(score))
    else return GMT.Red(tostring(score)) end
end

-- Impact rating based on score vs baseline
local function ImpactLabel(score, roleBaseline)
    if not roleBaseline or roleBaseline == 0 then return GMT.Dim("--") end
    local delta = score - roleBaseline
    if     delta >=  15 then return GMT.Green("Strong +")
    elseif delta >=   5 then return GMT.Green("Above avg")
    elseif delta >=  -5 then return GMT.Amber("Average")
    elseif delta >= -15 then return GMT.Amber("Below avg")
    else                     return GMT.Red("Weak --")
    end
end

-- Compute role averages from current raid roster (GMT.RP.rows)
local function ComputeBaseline()
    local db  = EnsureDB()
    local sums = { TANK={n=0,s=0}, HEALER={n=0,s=0}, DAMAGER={n=0,s=0} }
    if GMT.RP and GMT.RP.rows then
        for _, row in ipairs(GMT.RP.rows) do
            local role = row.role or "DAMAGER"
            if role == "-" or role == "" or role == "NONE" then role = "DAMAGER" end
            local score = ScorePlayer(row, db.thresholds)
            sums[role].n = sums[role].n + 1
            sums[role].s = sums[role].s + score
        end
    end
    db.baseline = {}
    for role, v in pairs(sums) do
        db.baseline[role] = v.n > 0 and math.floor(v.s / v.n) or 0
    end
    return db.baseline
end

-- ============================================================
-- LOCAL UI HELPERS
-- ============================================================
local function Sec(parent, title, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    box:SetBackdropColor(GMT.U(GMT.C.cardBg))
    box:SetBackdropBorderColor(GMT.U(GMT.C.copper))
    local head = box:CreateTexture(nil, "BACKGROUND")
    head:SetPoint("TOPLEFT",  box, "TOPLEFT",   3, -3)
    head:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -3)
    head:SetHeight(24)
    head:SetColorTexture(GMT.U(GMT.C.cardHead))
    local hdiv = box:CreateTexture(nil, "ARTWORK")
    hdiv:SetPoint("TOPLEFT",  box, "TOPLEFT",   3, -27)
    hdiv:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -27)
    hdiv:SetHeight(1)
    hdiv:SetColorTexture(GMT.U(GMT.C.copper))
    hdiv:SetAlpha(0.85)
    local tf = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tf:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    tf:SetTextColor(GMT.U(GMT.C.txtTitle))
    tf:SetText(title)
    GMT.Rivets(box, 6, 4)
    return box
end

local function Lbl(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(GMT.U(GMT.C.txtDim))
    fs:SetText(text)
    return fs
end

local function Inp(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    return eb
end

local function MultiInp(parent, x, y, w, h)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, h)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=10,insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(GMT.U(GMT.C.panelBg))
    bg:SetBackdropBorderColor(GMT.U(GMT.C.brass))
    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetMultiLine(true); eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextColor(GMT.U(GMT.C.txtBody))
    eb:SetPoint("TOPLEFT",     bg, "TOPLEFT",      6, -6)
    eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6,  6)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    return eb
end

local function ScrollList(parent, x, y, w, h, cols)
    local fr = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    fr:SetSize(w, h)
    fr:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fr:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=10,insets={left=3,right=3,top=3,bottom=3},
    })
    fr:SetBackdropColor(GMT.U(GMT.C.panelBg))
    fr:SetBackdropBorderColor(GMT.U(GMT.C.brass))
    local hdr = CreateFrame("Frame", nil, fr)
    hdr:SetPoint("TOPLEFT", fr, "TOPLEFT", 4, -4)
    hdr:SetSize(w-8, 18)
    local hb = hdr:CreateTexture(nil, "BACKGROUND"); hb:SetAllPoints()
    hb:SetColorTexture(GMT.U(GMT.C.cardHead))
    local cx = 4
    for _, col in ipairs(cols) do
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", hdr, "LEFT", cx, 0)
        fs:SetWidth(col.w); fs:SetJustifyH(col.j or "LEFT")
        fs:SetTextColor(GMT.U(GMT.C.txtTitle)); fs:SetText(col.label)
        cx = cx + col.w
    end
    local sf = CreateFrame("ScrollFrame", nil, fr, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", fr, "TOPLEFT", 4, -24)
    sf:SetSize(w-24, h-28)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w-24, 20)
    sf:SetScrollChild(content)
    return fr, content
end

local function MkRow(content, idx, w)
    local btn = CreateFrame("Button", nil, content)
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((idx-1)*ROW_H))
    btn:SetSize(w, ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND"); btn.bg:SetAllPoints()
    btn.cells = {}
    return btn
end

local function FillRow(row, cols, vals)
    local x = 4
    for i, col in ipairs(cols) do
        local fs = row.cells[i]
        if not fs then
            fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.cells[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(col.w); fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(vals[i] or "")
        x = x + col.w
    end
end

-- Score bar: a small horizontal bar inside a row showing score visually
-- Draws onto an existing row frame
local function DrawScoreBar(parent, x, y, w, h, score)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(w, h)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetColorTexture(0.10, 0.08, 0.05, 0.90)

    local fill = parent:CreateTexture(nil, "ARTWORK")
    local fillW = math.max(2, math.floor(w * score / 100))
    fill:SetSize(fillW, h)
    fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if     score >= 80 then fill:SetColorTexture(GMT.U(GMT.C.green))
    elseif score >= 60 then fill:SetColorTexture(GMT.U(GMT.C.amber))
    else                    fill:SetColorTexture(GMT.U(GMT.C.red)) end
    fill:SetAlpha(0.75)
    return fill
end

-- ============================================================
-- COLUMN DEFINITIONS
-- ============================================================
-- Roster scores list (PW - 16 = 944 content, left col 550)
local rosterCols = {
    { label="Name",    w=148, j="LEFT"   },
    { label="Role",    w=60,  j="LEFT"   },
    { label="Score",   w=48,  j="CENTER" },
    { label="Impact",  w=88,  j="LEFT"   },
    { label="Missing", w=168, j="LEFT"   },
}  -- total 512  (content ~510)

-- Recruit scoring list (right col 386)
local recruitCols = {
    { label="Name",    w=100, j="LEFT"   },
    { label="Score",   w=44,  j="CENTER" },
    { label="Role",    w=56,  j="LEFT"   },
    { label="Impact",  w=84,  j="LEFT"   },
}  -- total 284  (content ~346)

-- Breakdown list (reused for both roster detail + recruit detail)
local breakdownCols = {
    { label="Check",  w=96,  j="LEFT"   },
    { label="Pts",    w=36,  j="CENTER" },
    { label="Status", w=100, j="LEFT"   },
}  -- total 232

-- Log
local logCols = { { label="Activity", w=390, j="LEFT" } }

-- ============================================================
-- STATE
-- ============================================================
PF.rosterScores  = PF.rosterScores  or {}   -- computed each scan
PF.selectedRoster = nil                      -- selected player name
PF.selectedRecruit = nil

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
local function RefreshBaselinesDisplay()
    local db = EnsureDB()
    local bl = db.baseline or {}
    if refs.baseTank   then refs.baseTank:SetText(bl.TANK    and ScoreColor(bl.TANK)    or GMT.Dim("--")) end
    if refs.baseHeal   then refs.baseHeal:SetText(bl.HEALER  and ScoreColor(bl.HEALER)  or GMT.Dim("--")) end
    if refs.baseDPS    then refs.baseDPS:SetText(bl.DAMAGER  and ScoreColor(bl.DAMAGER) or GMT.Dim("--")) end
    if refs.baseCount  then
        local n = GMT.RP and GMT.RP.rows and #GMT.RP.rows or 0
        refs.baseCount:SetText(GMT.Amber(tostring(n)).." "..GMT.Dim("in roster"))
    end
    if refs.threshold  then
        refs.threshold:SetText(tostring(db.thresholds.minScore))
    end
    if refs.threshDur  then
        refs.threshDur:SetText(tostring(db.thresholds.minDur))
    end
end

local RefreshBreakdown  -- forward decl

local function RefreshRosterScores()
    if not refs.rosterContent then return end
    refs.rosterRows = refs.rosterRows or {}
    local rows = refs.rosterRows
    local db   = EnsureDB()
    local bl   = db.baseline or {}
    local data = PF.rosterScores

    for i, entry in ipairs(data) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.rosterContent, i, 512)
            rows[i] = row
        end
        local sel = (PF.selectedRoster == entry.short)
        row.bg:SetColorTexture(
            sel and 0.18 or 0.07,
            sel and 0.22 or 0.05, 0.04,
            sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()

        local roleKey = entry.role
        if roleKey == "-" or roleKey == "" or roleKey == "NONE" then roleKey = "DAMAGER" end
        local roleBase = bl[roleKey] or 0
        local impact   = ImpactLabel(entry.score, roleBase)
        local roleDisp = ROLE_LABEL[entry.role] or GMT.Dim(entry.role or "--")

        -- Build missing string
        local missing = {}
        for k, v in pairs(entry.breakdown) do
            if not v.ok then table.insert(missing, v.label) end
        end
        table.sort(missing)
        local missStr = #missing > 0 and GMT.Red(table.concat(missing, ", ")) or GMT.Green("Ready")

        FillRow(row, rosterCols, {
            GMT.ClassStr(entry.class or "", entry.short),
            roleDisp,
            ScoreColor(entry.score),
            impact,
            missStr,
        })

        row:SetScript("OnClick", function()
            PF.selectedRoster = entry.short
            RefreshRosterScores()
            if RefreshBreakdown then RefreshBreakdown(entry.breakdown, refs.breakContent, refs.breakRows) end
            if refs.detailName then refs.detailName:SetText(GMT.ClassStr(entry.class, entry.short) .. "  " .. ScoreColor(entry.score) .. GMT.Dim("/100")) end
            if refs.noteInput  then
                local note = (db.notes and db.notes[entry.short]) or ""
                refs.noteInput:SetText(note)
            end
        end)
    end
    for i = #data+1, #rows do rows[i]:Hide() end
    refs.rosterContent:SetHeight(math.max(ROW_H, #data * ROW_H))
    if refs.rosterCount then
        local ready = 0
        for _, e in ipairs(data) do if e.score >= (db.thresholds.minScore or 60) then ready=ready+1 end end
        refs.rosterCount:SetText(GMT.Green(tostring(ready)).." "..GMT.Dim("/"..#data.." ready"))
    end
end

local function RefreshRecruitScores()
    if not refs.recruitContent then return end
    refs.recruitRows = refs.recruitRows or {}
    local rows = refs.recruitRows
    local db   = EnsureDB()
    local bl   = db.baseline or {}
    local recs = db.recruits or {}

    for i, rec in ipairs(recs) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.recruitContent, i, 284)
            rows[i] = row
        end
        local sel = (PF.selectedRecruit == rec.name)
        row.bg:SetColorTexture(
            sel and 0.18 or 0.07,
            sel and 0.22 or 0.05, 0.04,
            sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()
        local roleKey  = rec.role or "DAMAGER"
        local roleBase = bl[roleKey] or 0
        local impact   = ImpactLabel(rec.score or 0, roleBase)
        FillRow(row, recruitCols, {
            GMT.ClassStr(rec.class or "", rec.name or "?"),
            ScoreColor(rec.score or 0),
            ROLE_LABEL[rec.role] or GMT.Dim("--"),
            impact,
        })
        row:SetScript("OnClick", function()
            PF.selectedRecruit = rec.name
            RefreshRecruitScores()
            if refs.recDetailName then
                refs.recDetailName:SetText(GMT.ClassStr(rec.class, rec.name)
                    .."  Score: "..ScoreColor(rec.score or 0)..GMT.Dim("/100")
                    .."  Added: "..date("%m/%d", rec.t or 0))
            end
            if refs.recNoteInput then
                refs.recNoteInput:SetText(rec.note or "")
            end
        end)
    end
    for i = #recs+1, #rows do rows[i]:Hide() end
    refs.recruitContent:SetHeight(math.max(ROW_H, #recs * ROW_H))
    if refs.recruitCount then
        refs.recruitCount:SetText(GMT.Amber(tostring(#recs)).." "..GMT.Dim("scored recruits"))
    end
end

RefreshBreakdown = function(breakdown, content, rowPool)
    if not content or not breakdown then return end
    rowPool = rowPool or {}
    local ORDER = {"online","flask","food","dur","rune","weapon","role"}
    local i = 0
    for _, key in ipairs(ORDER) do
        local item = breakdown[key]
        if item then
            i = i + 1
            local row = rowPool[i]
            if not row then
                row = MkRow(content, i, 232)
                rowPool[i] = row
            end
            row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
            row:Show()
            local ptsStr = item.ok and GMT.Green("+"..item.pts) or GMT.Dim("+0")
            local status = item.ok and GMT.Green(item.label or "OK") or GMT.Red(item.label or "Missing")
            FillRow(row, breakdownCols, { key:upper(), ptsStr, status })
        end
    end
    for j = i+1, #rowPool do rowPool[j]:Hide() end
    content:SetHeight(math.max(ROW_H, i * ROW_H))
end

local function RefreshLog()
    if not refs.logContent then return end
    refs.logRows = refs.logRows or {}
    local log = EnsureDB().log or {}
    for i, entry in ipairs(log) do
        local row = refs.logRows[i]
        if not row then row = MkRow(refs.logContent, i, 394); refs.logRows[i]=row end
        row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        FillRow(row, logCols, { GMT.Dim(date("%H:%M", entry.t or time())).."  "..(entry.msg or "") })
    end
    for i = #log+1, #refs.logRows do refs.logRows[i]:Hide() end
    refs.logContent:SetHeight(math.max(ROW_H, #log * ROW_H))
end

local function RefreshAll()
    RefreshBaselinesDisplay()
    RefreshRosterScores()
    RefreshRecruitScores()
    RefreshLog()
end

-- ============================================================
-- SCAN FUNCTIONS
-- ============================================================
local function ScanRoster()
    -- Pull current raid/party data from RaidReadiness module
    local db   = EnsureDB()
    PF.rosterScores = {}
    PF.selectedRoster = nil

    if not GMT.RP or not GMT.RP.rows or #GMT.RP.rows == 0 then
        SetStatus("No roster data.  Go to Raid Prep tab and click Scan Raid first.", "red")
        return
    end

    local baseline = ComputeBaseline()

    for _, row in ipairs(GMT.RP.rows) do
        local score, breakdown = ScorePlayer(row, db.thresholds)
        table.insert(PF.rosterScores, {
            short     = row.short,
            name      = row.name,
            class     = row.class,
            role      = row.role,
            score     = score,
            breakdown = breakdown,
        })
    end

    -- Sort: highest score first
    table.sort(PF.rosterScores, function(a,b) return a.score > b.score end)

    AddLog("Roster scan: "..#PF.rosterScores.." players scored")
    SetStatus("Roster scored: "..#PF.rosterScores.." players.  Baseline computed.", "green")
    RefreshAll()
end

-- Score a named recruit from the pipeline
local function ScoreRecruit(name, role, class)
    local db    = EnsureDB()
    name  = name  and name:match("^%s*(.-)%s*$")  or ""
    role  = role  and role:upper():match("^%s*(.-)%s*$") or "DAMAGER"
    class = class and class:upper():match("^%s*(.-)%s*$") or ""
    if name == "" then SetStatus("Enter a recruit name first.", "red"); return end

    -- Look for them in pipeline for any saved data
    local pipeData = nil
    if GMT.DB.recruitment and GMT.DB.recruitment.pipeline then
        for _, p in ipairs(GMT.DB.recruitment.pipeline) do
            if GMT.Short(p.name):lower() == name:lower() then
                pipeData = p; break
            end
        end
    end

    -- Build a synthetic data row (worst-case: no buffs, just role)
    local synthetic = {
        name    = name,
        short   = name,
        class   = (pipeData and pipeData.class) or class,
        role    = role,
        online  = true,   -- assume they were seen recently
        dead    = false,
        flask   = false,  -- unknown   conservative
        food    = false,
        rune    = false,
        weapon  = false,
        durability = -1,  -- unknown
    }

    local score, breakdown = ScorePlayer(synthetic, db.thresholds)

    -- Check if recruit already exists
    for _, rec in ipairs(db.recruits) do
        if rec.name:lower() == name:lower() then
            rec.score     = score
            rec.breakdown = breakdown
            rec.role      = role
            rec.class     = synthetic.class
            rec.t         = time()
            AddLog("Re-scored recruit: "..name.." = "..score)
            SetStatus("Recruit scored: "..name.." ("..score.."/100)", "green")
            RefreshAll()
            return
        end
    end

    table.insert(db.recruits, 1, {
        name      = name,
        class     = synthetic.class,
        role      = role,
        score     = score,
        breakdown = breakdown,
        note      = "",
        t         = time(),
    })
    while #db.recruits > 100 do table.remove(db.recruits) end
    AddLog("Scored recruit: "..name.." = "..score)
    SetStatus("Recruit scored: "..name.." ("..score.."/100)", "green")
    RefreshAll()
end

local function RemoveSelectedRecruit()
    local db = EnsureDB()
    if not PF.selectedRecruit then SetStatus("Select a recruit first.", "red"); return end
    local fresh = {}
    for _, rec in ipairs(db.recruits) do
        if rec.name ~= PF.selectedRecruit then table.insert(fresh, rec) end
    end
    local removed = #db.recruits - #fresh
    db.recruits = fresh
    PF.selectedRecruit = nil
    if refs.recDetailName then refs.recDetailName:SetText(GMT.Dim("No recruit selected")) end
    AddLog("Removed recruit: "..removed.." entr(y/ies)")
    SetStatus("Recruit removed.", "green")
    RefreshAll()
end

local function SaveNote()
    local db  = EnsureDB()
    local name = PF.selectedRoster
    if not name then SetStatus("Select a roster player first.", "red"); return end
    db.notes = db.notes or {}
    db.notes[name] = refs.noteInput and refs.noteInput:GetText() or ""
    AddLog("Note saved for "..name)
    SetStatus("Note saved for "..name..".", "green")
end

local function SaveRecNote()
    local db   = EnsureDB()
    local name = PF.selectedRecruit
    if not name then SetStatus("Select a recruit first.", "red"); return end
    for _, rec in ipairs(db.recruits) do
        if rec.name == name then
            rec.note = refs.recNoteInput and refs.recNoteInput:GetText() or ""
            break
        end
    end
    AddLog("Note saved for recruit "..name)
    SetStatus("Recruit note saved.", "green")
end

-- ============================================================
-- INIT
-- ============================================================
-- Layout (PH=528):
--   header:  58
--   summary: y=-66  h=58
--   mid row: y=-132 h=224 (roster left 550 | recruit right 386)
--   bot row: y=-364 h=108 (detail+notes left | log right)
--   status:  12
-- Total: 58+8+58+8+224+8+108+12 = 484  (44px spare -- log section gets it)
-- ============================================================
function GMT_RaidPerf_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Raid Perf")
        if not panel or panel._raidPerfBuilt then return end
        panel._raidPerfBuilt = true

        EnsureDB()

        GMT.Header(panel, "Raid Performance Predictor", 14, -10)
        GMT.Label(panel, "Score roster . Baseline by role . Predict recruit impact . Track officer notes", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local PAD = 8; local GAP = 8
        local W   = GMT.PW - PAD*2   -- 944
        local LW  = 550
        local RW  = W - LW - GAP     -- 386

        local sumY = -66;  local sumH = 58
        local midY = sumY - sumH  - GAP  -- -132
        local midH = 200
        local botY = midY - midH  - GAP  -- -340
        local botH = 146
        local logY = botY - botH  - GAP  -- -496
        local logH = 20

        -- +================================================ 
        -- |  SUMMARY / BASELINES BAR                      |
        -- +================================================ 
        local sumBox = Sec(panel, "Performance Baselines  &  Thresholds", PAD, sumY, W, sumH)

        local function SumStat(ltext, x)
            local l = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            l:SetPoint("TOPLEFT", sumBox, "TOPLEFT", x, -34)
            l:SetTextColor(GMT.U(GMT.C.txtDim)); l:SetText(ltext)
            local v = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            v:SetPoint("LEFT", l, "RIGHT", 6, 0)
            return v
        end

        refs.baseTank   = SumStat("Tank avg:",   14)
        refs.baseHeal   = SumStat("Healer avg:", 130)
        refs.baseDPS    = SumStat("DPS avg:",    250)
        refs.baseCount  = SumStat("Roster:",     360)

        -- Thresholds inline
        local tl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        tl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 500, -34)
        tl:SetTextColor(GMT.U(GMT.C.txtDim)); tl:SetText("Ready threshold:")
        refs.threshold = Inp(sumBox, 618, -32, 34, 18)

        local tdl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        tdl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 658, -34)
        tdl:SetTextColor(GMT.U(GMT.C.txtDim)); tdl:SetText("Min Dur %:")
        refs.threshDur = Inp(sumBox, 724, -32, 34, 18)

        local saveThresh = GMT.MBtn(sumBox, "Save", 56, 18)
        saveThresh:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 768, -31)
        saveThresh:SetScript("OnClick", function()
            local db = EnsureDB()
            db.thresholds.minScore = tonumber(refs.threshold:GetText()) or db.thresholds.minScore
            db.thresholds.minDur   = tonumber(refs.threshDur:GetText()) or db.thresholds.minDur
            SetStatus("Thresholds saved.", "green")
            RefreshAll()
        end)

        local scanBtn = GMT.MBtn(sumBox, "Score Roster", 102, 20)
        scanBtn:SetPoint("TOPRIGHT", sumBox, "TOPRIGHT", -12, -28)
        scanBtn:SetScript("OnClick", ScanRoster)

        -- +================================================ 
        -- |  MID ROW: Roster Scores (L) | Recruits (R)   |
        -- +================================================ 
        local rosterBox  = Sec(panel, "Raid Roster Scores", PAD, midY, LW, midH)
        local recruitBox = Sec(panel, "Recruit Scoring",    PAD+LW+GAP, midY, RW, midH)

        -- Roster count badge
        refs.rosterCount = rosterBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.rosterCount:SetPoint("TOPRIGHT", rosterBox, "TOPRIGHT", -14, -32)
        refs.rosterCount:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.rosterCount:SetText(GMT.Dim("No data -- scan Raid Prep first"))

        -- Roster score list (h = midH - 50 = 170)
        local _, rosterContent = ScrollList(rosterBox, 8, -48, LW-16, midH-56, rosterCols)
        refs.rosterContent = rosterContent

        -- Recruit score inputs
        Lbl(recruitBox, "Name:",  10, -32)
        refs.recName = Inp(recruitBox, 52, -30, 120, 18)
        Lbl(recruitBox, "Role:",  180, -32)
        refs.recRole = Inp(recruitBox, 218, -30, 58, 18)

        local scoreBtn = GMT.MBtn(recruitBox, "Score", 60, 18)
        scoreBtn:SetPoint("TOPLEFT", recruitBox, "TOPLEFT", 10, -58)
        scoreBtn:SetScript("OnClick", function()
            local name = refs.recName and refs.recName:GetText() or ""
            local role = refs.recRole and refs.recRole:GetText() or "DPS"
            ScoreRecruit(name, role, "")
        end)

        refs.recruitCount = recruitBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.recruitCount:SetPoint("TOPRIGHT", recruitBox, "TOPRIGHT", -14, -32)
        refs.recruitCount:SetTextColor(GMT.U(GMT.C.txtDim))

        -- Import from pipeline button
        local importBtn = GMT.MBtn(recruitBox, "Import Pipeline", 130, 18)
        importBtn:SetPoint("LEFT", scoreBtn, "RIGHT", 8, 0)
        importBtn:SetScript("OnClick", function()
            if not GMT.DB.recruitment or not GMT.DB.recruitment.pipeline then
                SetStatus("No pipeline data found.", "red"); return
            end
            local count = 0
            for _, p in ipairs(GMT.DB.recruitment.pipeline) do
                if p.status ~= "Blacklisted" then
                    local role = "DAMAGER"
                    ScoreRecruit(p.name, role, p.class or "")
                    count = count + 1
                end
            end
            SetStatus("Imported "..count.." recruit(s) from pipeline.", "green")
            RefreshAll()
        end)

        local remRecBtn = GMT.MBtn(recruitBox, "Remove", 72, 18)
        remRecBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
        remRecBtn:SetScript("OnClick", RemoveSelectedRecruit)

        -- Recruit list (h = midH - 82 = 138)
        local _, recruitContent = ScrollList(recruitBox, 8, -78, RW-16, midH-86, recruitCols)
        refs.recruitContent = recruitContent

        -- +================================================ 
        -- |  BOT ROW: Detail+Notes (L) | Breakdown (R)   |
        -- +================================================ 
        local detailBox    = Sec(panel, "Player Detail  &  Officer Notes", PAD, botY, LW, botH)
        local breakdownBox = Sec(panel, "Score Breakdown", PAD+LW+GAP, botY, RW, botH)

        -- Player detail name banner
        refs.detailName = detailBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.detailName:SetPoint("TOPLEFT", detailBox, "TOPLEFT", 10, -32)
        refs.detailName:SetTextColor(GMT.U(GMT.C.txtBody))
        refs.detailName:SetText(GMT.Dim("Click a roster row to view details"))

        Lbl(detailBox, "Note:", 10, -54)
        refs.noteInput = MultiInp(detailBox, 52, -52, LW-64, botH-68)

        local saveNoteBtn = GMT.MBtn(detailBox, "Save Note", 88, 18)
        saveNoteBtn:SetPoint("BOTTOMRIGHT", detailBox, "BOTTOMRIGHT", -10, 8)
        saveNoteBtn:SetScript("OnClick", SaveNote)

        -- Recruit detail name banner
        refs.recDetailName = breakdownBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.recDetailName:SetPoint("TOPLEFT", breakdownBox, "TOPLEFT", 10, -32)
        refs.recDetailName:SetTextColor(GMT.U(GMT.C.txtBody))
        refs.recDetailName:SetText(GMT.Dim("Click a recruit row to view breakdown"))

        refs.recNoteInput = Inp(breakdownBox, 10, -52, RW-86, 18)
        Lbl(breakdownBox, "Note:", 10, -36)

        local saveRecNote = GMT.MBtn(breakdownBox, "Save", 60, 18)
        saveRecNote:SetPoint("TOPLEFT", breakdownBox, "TOPLEFT", RW-70, -51)
        saveRecNote:SetScript("OnClick", SaveRecNote)

        -- Score breakdown list (h = botH - 76 = 44)
        local _, breakContent = ScrollList(breakdownBox, 8, -74, RW-16, botH-82, breakdownCols)
        refs.breakContent = breakContent
        refs.breakRows    = {}

        -- Activity Log removed to free vertical space for the main raid performance controls.

        --    Status bar                                     
        refs.status = panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 18)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Raid Perf ready.  Scan Raid Prep first, then click Score Roster.")

        panel:SetScript("OnShow", function()
            RefreshAll()
        end)

        RefreshAll()
    end)

    if not ok and GMT and GMT.Err then
        GMT.Err("RaidPerf init failed: " .. tostring(err))
    end
end
