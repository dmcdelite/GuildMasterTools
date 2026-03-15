-- ============================================================
-- GuildMaster Tools  |  Modules/Logistics.lua  |  v3.0.0
-- Phase 7 -- Guild Logistics Engine
-- Supply scan . Restock planner . Distribution queue
-- Gatherer registry . Crafter registry . Activity log
-- ============================================================
local _, GMT = ...

GMT.LX = GMT.LX or {}
local LX = GMT.LX

local refs  = {}
local ROW_H = 20

LX.supplies         = LX.supplies         or {}
LX.selectedSupplies = LX.selectedSupplies or {}
LX.selectedQueue    = LX.selectedQueue    or {}
LX.selGatherer      = LX.selGatherer      or {}
LX.selCrafter       = LX.selCrafter       or {}

-- ============================================================
-- SUPPLY CATEGORIES
-- ============================================================
local SUPPLY_RULES = {
    { key="flask",    label="Flasks / Phials",    patterns={"flask","phial"} },
    { key="food",     label="Raid Food",           patterns={"feast","banquet","well fed","ration","food"} },
    { key="rune",     label="Runes",               patterns={"augmentation rune","rune"} },
    { key="potion",   label="Potions",             patterns={"potion","healing potion","mana potion","vial"} },
    { key="repair",   label="Repair / Utility",    patterns={"repair","hammer","anvil"} },
    { key="cauldron", label="Cauldrons",            patterns={"cauldron"} },
    { key="vantus",   label="Boss Buff / Vantus",  patterns={"vantus"} },
    { key="gem",      label="Gems / Enchants",     patterns={"gem","diamond","ruby","emerald","enchant"} },
    { key="other",    label="Other Logistics",     patterns={} },
}

-- ============================================================
-- DB
-- ============================================================
local function EnsureDB()
    GMT.DB.logistics = GMT.DB.logistics or {}
    local db = GMT.DB.logistics
    db.stockPlan  = db.stockPlan  or { flask=40, food=40, rune=20, potion=40, repair=5, cauldron=4, vantus=10, gem=10, other=0 }
    db.queue      = db.queue      or {}
    db.gatherers  = db.gatherers  or {}
    db.crafters   = db.crafters   or {}
    db.notes      = db.notes      or ""
    db.lastScan   = db.lastScan   or 0
    db.log        = db.log        or {}
    return db
end

local function AddLog(msg)
    local db = EnsureDB()
    table.insert(db.log, 1, { t=time(), msg=msg })
    while #db.log > 60 do table.remove(db.log) end
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
-- LOCAL UI HELPERS  (same Rustbolt style as other modules)
-- ============================================================
local function Sec(parent, title, x, y, w, h)
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
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function MultiInp(parent, x, y, w, h)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, h)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10, insets={left=3,right=3,top=3,bottom=3},
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
        tile=true, tileSize=16, edgeSize=10, insets={left=3,right=3,top=3,bottom=3},
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

-- ============================================================
-- SUPPLY SCANNER
-- ============================================================
local function MatchSupply(name)
    local lower = (name or ""):lower()
    for _, rule in ipairs(SUPPLY_RULES) do
        if rule.key ~= "other" then
            for _, pat in ipairs(rule.patterns) do
                if lower:find(pat, 1, true) then return rule.key, rule.label end
            end
        end
    end
    return "other", "Other Logistics"
end

local function ScanSupplies()
    LX.supplies = {}
    local bucket = {}
    for _, rule in ipairs(SUPPLY_RULES) do
        bucket[rule.key] = {
            key=rule.key, label=rule.label,
            total=0, stacks=0,
            need=EnsureDB().stockPlan[rule.key] or 0,
        }
    end
    for bag = 0, 4 do
        local slots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
                   or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, slots do
            local info  = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            local iid   = (info and info.itemID) or (GetContainerItemID and GetContainerItemID(bag, slot))
            local count = (info and info.stackCount) or 0
            if iid then
                local iname = GetItemInfo(iid) or ("Item "..iid)
                local key   = MatchSupply(iname)
                bucket[key].total  = bucket[key].total  + count
                bucket[key].stacks = bucket[key].stacks + 1
            end
        end
    end
    for _, rule in ipairs(SUPPLY_RULES) do
        local e    = bucket[rule.key]
        local need = tonumber(e.need) or 0
        e.status = need<=0 and GMT.Dim("No Plan")
            or (e.total >= need) and GMT.Green("Stocked")
            or (e.total >  0)   and GMT.Amber(tostring(need-e.total).." short")
            or GMT.Red("Empty")
        table.insert(LX.supplies, e)
    end
    table.sort(LX.supplies, function(a,b)
        return (tonumber(a.need or 0)-tonumber(a.total or 0)) > (tonumber(b.need or 0)-tonumber(b.total or 0))
    end)
    EnsureDB().lastScan = time()
    AddLog("Supply scan complete")
    SetStatus("Supply scan complete.", "green")
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
local supplyCols = {
    { label="",        w=16,  j="CENTER" },
    { label="Category",w=120, j="LEFT"   },
    { label="Need",    w=42,  j="CENTER" },
    { label="Have",    w=42,  j="CENTER" },
    { label="Stacks",  w=40,  j="CENTER" },
    { label="Status",  w=80,  j="LEFT"   },
}

local function RefreshSupplies()
    if not refs.supContent then return end
    refs.supRows = refs.supRows or {}
    for i, e in ipairs(LX.supplies) do
        local row = refs.supRows[i]
        if not row then row = MkRow(refs.supContent, i, 340); refs.supRows[i]=row end
        local sel = LX.selectedSupplies[e.key]
        row.bg:SetColorTexture(sel and 0.18 or 0.07, sel and 0.22 or 0.05, 0.04, sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()
        FillRow(row, supplyCols, { sel and GMT.Green("x") or "", e.label, tostring(e.need or 0), tostring(e.total or 0), tostring(e.stacks or 0), e.status })
        row:SetScript("OnClick", function()
            LX.selectedSupplies[e.key] = not LX.selectedSupplies[e.key]
            if refs.planKey  then refs.planKey:SetText(e.key) end
            if refs.planNeed then refs.planNeed:SetText(tostring(EnsureDB().stockPlan[e.key] or 0)) end
            RefreshSupplies()
        end)
    end
    for i = #LX.supplies+1, #refs.supRows do refs.supRows[i]:Hide() end
    refs.supContent:SetHeight(math.max(ROW_H, #LX.supplies*ROW_H))
end

local queueCols = {
    { label="",     w=16,  j="CENTER" },
    { label="Task", w=120, j="LEFT"   },
    { label="Owner",w=66,  j="LEFT"   },
    { label="State",w=66,  j="LEFT"   },
}

local function RefreshQueue()
    local db = EnsureDB()
    if not refs.queueContent then return end
    refs.queueRows = refs.queueRows or {}
    for i, item in ipairs(db.queue) do
        local row = refs.queueRows[i]
        if not row then row = MkRow(refs.queueContent, i, 268); refs.queueRows[i]=row end
        local sel = LX.selectedQueue[item.task]
        row.bg:SetColorTexture(sel and 0.18 or 0.07, sel and 0.22 or 0.05, 0.04, sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()
        FillRow(row, queueCols, { sel and GMT.Green("x") or "", GMT.Clip(item.task or "Task", 18), GMT.Clip(item.owner or "--", 10), item.state or "Open" })
        row:SetScript("OnClick", function()
            LX.selectedQueue[item.task] = not LX.selectedQueue[item.task]
            if refs.qTask  then refs.qTask:SetText(item.task  or "") end
            if refs.qOwner then refs.qOwner:SetText(item.owner or "") end
            RefreshQueue()
        end)
    end
    for i = #db.queue+1, #refs.queueRows do refs.queueRows[i]:Hide() end
    refs.queueContent:SetHeight(math.max(ROW_H, #db.queue*ROW_H))
end

-- Phase 7: Gatherer registry
local gatherCols = {
    { label="Name",     w=120, j="LEFT" },
    { label="Materials",w=130, j="LEFT" },
    { label="Notes",    w=120, j="LEFT" },
}

local function RefreshGatherers()
    local db = EnsureDB()
    if not refs.gatherContent then return end
    refs.gatherRows = refs.gatherRows or {}
    for i, g in ipairs(db.gatherers) do
        local row = refs.gatherRows[i]
        if not row then row = MkRow(refs.gatherContent, i, 370); refs.gatherRows[i]=row end
        local sel = LX.selGatherer[g.name]
        row.bg:SetColorTexture(sel and 0.18 or 0.07, sel and 0.22 or 0.05, 0.04, sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()
        FillRow(row, gatherCols, {
            GMT.ClassStr(g.class or "", g.name or "?"),
            GMT.Clip(g.materials or "--", 20),
            GMT.Clip(g.notes or "", 18),
        })
        row:SetScript("OnClick", function()
            LX.selGatherer[g.name] = not LX.selGatherer[g.name]
            if refs.gName  then refs.gName:SetText(g.name or "")      end
            if refs.gMats  then refs.gMats:SetText(g.materials or "")  end
            if refs.gNotes then refs.gNotes:SetText(g.notes or "")     end
            RefreshGatherers()
        end)
    end
    for i = #db.gatherers+1, #refs.gatherRows do refs.gatherRows[i]:Hide() end
    refs.gatherContent:SetHeight(math.max(ROW_H, #db.gatherers*ROW_H))
    if refs.gCount then refs.gCount:SetText(GMT.Green(tostring(#db.gatherers)).." "..GMT.Dim("registered")) end
end

-- Phase 7: Crafter registry
local crafterCols = {
    { label="Name",      w=120, j="LEFT" },
    { label="Profession",w=100, j="LEFT" },
    { label="Recipes",   w=150, j="LEFT" },
}

local function RefreshCrafters()
    local db = EnsureDB()
    if not refs.crafterContent then return end
    refs.crafterRows = refs.crafterRows or {}
    for i, c in ipairs(db.crafters) do
        local row = refs.crafterRows[i]
        if not row then row = MkRow(refs.crafterContent, i, 370); refs.crafterRows[i]=row end
        local sel = LX.selCrafter[c.name]
        row.bg:SetColorTexture(sel and 0.18 or 0.07, sel and 0.22 or 0.05, 0.04, sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()
        FillRow(row, crafterCols, {
            GMT.ClassStr(c.class or "", c.name or "?"),
            GMT.Clip(c.profession or "--", 16),
            GMT.Clip(c.recipes or "--", 22),
        })
        row:SetScript("OnClick", function()
            LX.selCrafter[c.name] = not LX.selCrafter[c.name]
            if refs.cName then refs.cName:SetText(c.name       or "") end
            if refs.cProf then refs.cProf:SetText(c.profession or "") end
            if refs.cRec  then refs.cRec:SetText(c.recipes     or "") end
            RefreshCrafters()
        end)
    end
    for i = #db.crafters+1, #refs.crafterRows do refs.crafterRows[i]:Hide() end
    refs.crafterContent:SetHeight(math.max(ROW_H, #db.crafters*ROW_H))
    if refs.cCount then refs.cCount:SetText(GMT.Green(tostring(#db.crafters)).." "..GMT.Dim("registered")) end
end

local logCols = { { label="Activity", w=390, j="LEFT" } }

local function RefreshLog()
    local log = EnsureDB().log or {}
    if not refs.logContent then return end
    refs.logRows = refs.logRows or {}
    for i, entry in ipairs(log) do
        local row = refs.logRows[i]
        if not row then row = MkRow(refs.logContent, i, 394); refs.logRows[i]=row end
        row.bg:SetColorTexture(0.07, 0.05, 0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        FillRow(row, logCols, { GMT.Dim(date("%H:%M", entry.t or time())).."  "..(entry.msg or "") })
    end
    for i = #log+1, #refs.logRows do refs.logRows[i]:Hide() end
    refs.logContent:SetHeight(math.max(ROW_H, #log*ROW_H))
end

local function RefreshSummary()
    local db  = EnsureDB()
    local short, stocked = 0, 0
    for _, e in ipairs(LX.supplies) do
        local n = tonumber(e.need or 0) or 0
        if n > 0 then
            if e.total >= n then stocked = stocked + 1 else short = short + 1 end
        end
    end
    if refs.sumBuckets  then refs.sumBuckets:SetText(GMT.Amber(tostring(#LX.supplies))) end
    if refs.sumShort    then refs.sumShort:SetText(short>0 and GMT.Red(tostring(short)) or GMT.Green("0")) end
    if refs.sumQueue    then refs.sumQueue:SetText(GMT.Green(tostring(#db.queue))) end
    if refs.sumStocked  then refs.sumStocked:SetText(stocked>0 and GMT.Green(tostring(stocked)) or GMT.Dim("0")) end
    if refs.sumGath     then refs.sumGath:SetText(GMT.Green(tostring(#db.gatherers))) end
    if refs.sumCraft    then refs.sumCraft:SetText(GMT.Green(tostring(#db.crafters))) end
end

local function RefreshAll()
    RefreshSummary()
    RefreshSupplies()
    RefreshQueue()
    RefreshGatherers()
    RefreshCrafters()
    RefreshLog()
    if refs.notes then refs.notes:SetText(EnsureDB().notes or "") end
end

-- ============================================================
-- ACTIONS
-- ============================================================
local function SaveStockPlan()
    local db  = EnsureDB()
    local key = (refs.planKey and refs.planKey:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local need = tonumber(refs.planNeed and refs.planNeed:GetText() or "0") or 0
    if key == "" then SetStatus("Select a supply row or enter a category key.", "red"); return end
    db.stockPlan[key] = need
    for _, e in ipairs(LX.supplies) do if e.key==key then e.need=need end end
    AddLog("Stock plan: "..key.." = "..need)
    SetStatus("Stock plan saved.", "green")
    RefreshAll()
end

local function AddQueueTask()
    local db    = EnsureDB()
    local task  = ((refs.qTask  and refs.qTask:GetText()  or "")):match("^%s*(.-)%s*$")
    local owner = ((refs.qOwner and refs.qOwner:GetText() or "")):match("^%s*(.-)%s*$")
    if task == "" then SetStatus("Enter a task first.", "red"); return end
    for _, item in ipairs(db.queue) do
        if item.task == task then
            item.owner = owner ~= "" and owner or item.owner
            SetStatus("Task updated.", "green"); AddLog("Updated task: "..task); RefreshAll(); return
        end
    end
    table.insert(db.queue, 1, { task=task, owner=owner, state="Open" })
    AddLog("Added task: "..task)
    SetStatus("Task added.", "green")
    RefreshAll()
end

local function MarkQueueState(state)
    local db, count = EnsureDB(), 0
    for _, item in ipairs(db.queue) do
        if LX.selectedQueue[item.task] then item.state=state; count=count+1 end
    end
    AddLog("Marked "..count.." task(s) "..state)
    SetStatus("Updated "..count.." task(s) to "..state..".", count>0 and "green" or "red")
    RefreshAll()
end

local function RemoveQueueSelected()
    local db, fresh, removed = EnsureDB(), {}, 0
    for _, item in ipairs(db.queue) do
        if LX.selectedQueue[item.task] then removed=removed+1 else table.insert(fresh, item) end
    end
    db.queue = fresh; LX.selectedQueue = {}
    AddLog("Removed "..removed.." task(s)")
    SetStatus("Removed "..removed.." task(s).", removed>0 and "green" or "red")
    RefreshAll()
end

-- Phase 7: Gatherer CRUD
local function AddGatherer()
    local db   = EnsureDB()
    local name = ((refs.gName and refs.gName:GetText() or "")):match("^%s*(.-)%s*$")
    if name == "" then SetStatus("Enter a player name.", "red"); return end
    for _, g in ipairs(db.gatherers) do
        if g.name:lower() == name:lower() then
            g.materials = refs.gMats  and refs.gMats:GetText()  or g.materials
            g.notes     = refs.gNotes and refs.gNotes:GetText() or g.notes
            AddLog("Updated gatherer: "..name)
            SetStatus("Gatherer updated.", "green"); RefreshAll(); return
        end
    end
    local _, cf = UnitClass(name)
    table.insert(db.gatherers, 1, {
        name      = name,
        class     = cf or "",
        materials = refs.gMats  and refs.gMats:GetText()  or "",
        notes     = refs.gNotes and refs.gNotes:GetText() or "",
    })
    AddLog("Added gatherer: "..name)
    SetStatus("Gatherer added.", "green")
    RefreshAll()
end

local function RemoveGathererSelected()
    local db, fresh, n = EnsureDB(), {}, 0
    for _, g in ipairs(db.gatherers) do
        if LX.selGatherer[g.name] then n=n+1 else table.insert(fresh, g) end
    end
    db.gatherers = fresh; LX.selGatherer = {}
    AddLog("Removed "..n.." gatherer(s)")
    SetStatus("Removed "..n.." gatherer(s).", n>0 and "green" or "red")
    RefreshAll()
end

-- Phase 7: Crafter CRUD
local function AddCrafter()
    local db   = EnsureDB()
    local name = ((refs.cName and refs.cName:GetText() or "")):match("^%s*(.-)%s*$")
    if name == "" then SetStatus("Enter a player name.", "red"); return end
    for _, c in ipairs(db.crafters) do
        if c.name:lower() == name:lower() then
            c.profession = refs.cProf and refs.cProf:GetText() or c.profession
            c.recipes    = refs.cRec  and refs.cRec:GetText()  or c.recipes
            AddLog("Updated crafter: "..name)
            SetStatus("Crafter updated.", "green"); RefreshAll(); return
        end
    end
    local _, cf = UnitClass(name)
    table.insert(db.crafters, 1, {
        name       = name,
        class      = cf or "",
        profession = refs.cProf and refs.cProf:GetText() or "",
        recipes    = refs.cRec  and refs.cRec:GetText()  or "",
    })
    AddLog("Added crafter: "..name)
    SetStatus("Crafter added.", "green")
    RefreshAll()
end

local function RemoveCrafterSelected()
    local db, fresh, n = EnsureDB(), {}, 0
    for _, c in ipairs(db.crafters) do
        if LX.selCrafter[c.name] then n=n+1 else table.insert(fresh, c) end
    end
    db.crafters = fresh; LX.selCrafter = {}
    AddLog("Removed "..n.." crafter(s)")
    SetStatus("Removed "..n.." crafter(s).", n>0 and "green" or "red")
    RefreshAll()
end

-- ============================================================
-- INIT  -- Phase 7 Layout
-- PH=528. Math:
--   header:  58
--   summary: y=-66  h=58   (+8 gap)
--   mid row: y=-132 h=156  (+8 gap)
--   reg row: y=-296 h=136  (+8 gap)
--   bot row: y=-440 h=76   (+8 gap from above)
--   status: bottom 12px
-- Total used: 440+76 = 516  margin 12px (Y)
-- ============================================================
function GMT_Logistics_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Logistics")
        if not panel or panel._logisticsBuilt then return end
        panel._logisticsBuilt = true

        EnsureDB()

        GMT.Header(panel, "Guild Logistics Engine", 14, -10)
        GMT.Label(panel, "Supply tracking  .  Restock plans  .  Distribution queue  .  Gatherer & Crafter registries", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local PAD = 8
        local GAP = 8
        local W   = GMT.PW - PAD*2   -- 944

        --    Row Y positions                                
        local sumY  = -58 - GAP                       -- -66
        local sumH  = 58
        local midY  = sumY  - sumH  - GAP             -- -132
        local midH  = 156
        local regY  = midY  - midH  - GAP             -- -296
        local regH  = 136
        local botY  = regY  - regH  - GAP             -- -440
        local botH  = 72

        --    Section widths                                
        -- Mid row: Supply(380) + Planner(230) + Queue(320) + 2 GAP = 944
        local supW  = 380
        local planW = 230
        local queW  = W - supW - planW - GAP*2        -- 318

        -- Registry row: Gatherer(468) + Crafter(468) + GAP = 944
        local regW  = math.floor((W - GAP) / 2)       -- 468

        -- Bottom row: Notes(520) + Log(416) + GAP = 944
        local notW  = 520
        local logW  = W - notW - GAP                  -- 416

        -- +================================================ 
        -- |  SUMMARY BAR (full width)                     |
        -- +================================================ 
        local sumBox = Sec(panel, "Logistics Summary", PAD, sumY, W, sumH)

        local function SumStat(prevRef, labelText, x)
            local lbl = sumBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetTextColor(GMT.U(GMT.C.txtDim))
            lbl:SetText(labelText)
            if prevRef then lbl:SetPoint("LEFT", prevRef, "RIGHT", 28, 0)
            else lbl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 14, -34) end
            local val = sumBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            val:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            return lbl, val
        end

        local _, v = SumStat(nil,  "Buckets")   ; refs.sumBuckets = v
        local _, v2= SumStat(refs.sumBuckets, "Shortages");  refs.sumShort   = v2
        local _, v3= SumStat(refs.sumShort,   "Queue");      refs.sumQueue   = v3
        local _, v4= SumStat(refs.sumQueue,   "Stocked");    refs.sumStocked = v4
        local _, v5= SumStat(refs.sumStocked, "Gatherers");  refs.sumGath    = v5
        local _, v6= SumStat(refs.sumGath,    "Crafters");   refs.sumCraft   = v6

        local scanBtn = GMT.MBtn(sumBox, "Scan Supplies", 116, 24)
        scanBtn:SetPoint("TOPRIGHT", sumBox, "TOPRIGHT", -12, -28)
        scanBtn:SetScript("OnClick", function() ScanSupplies(); RefreshAll() end)

        -- +================================================ 
        -- |  MID ROW: Supply | Planner | Queue            |
        -- +================================================ 
        local supBox  = Sec(panel, "Supply Snapshot",    PAD,              midY, supW,  midH)
        local planBox = Sec(panel, "Restock Planner",    PAD+supW+GAP,     midY, planW, midH)
        local queBox  = Sec(panel, "Distribution Queue", PAD+supW+planW+GAP*2, midY, queW, midH)

        -- Supply list (h = midH-36=120)
        local _, supContent = ScrollList(supBox, 8, -30, supW-16, midH-38, supplyCols)
        refs.supContent = supContent

        -- Planner
        Lbl(planBox, "Category Key:", 10, -32)
        refs.planKey  = Inp(planBox, 10,  -48, 100, 20)
        Lbl(planBox, "Target Stock:", 10, -74)
        refs.planNeed = Inp(planBox, 10,  -90, 60, 20)
        local savePlan = GMT.MBtn(planBox, "Save Plan", 80, 22)
        savePlan:SetPoint("TOPLEFT", planBox, "TOPLEFT", 80, -89)
        savePlan:SetScript("OnClick", SaveStockPlan)
        local planHint = planBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        planHint:SetPoint("TOPLEFT", planBox, "TOPLEFT", 10, -118)
        planHint:SetWidth(210); planHint:SetJustifyH("LEFT")
        planHint:SetTextColor(GMT.U(GMT.C.txtDim))
        planHint:SetText("Keys: flask, food, rune, potion, repair, cauldron, vantus, gem, other")

        -- Queue
        Lbl(queBox, "Task:", 10, -32)
        refs.qTask  = Inp(queBox, 10,  -48, 140, 20)
        Lbl(queBox, "Owner:", 158, -32)
        refs.qOwner = Inp(queBox, 158, -48, 72, 20)
        local addQ = GMT.MBtn(queBox, "Add", 54, 20)
        addQ:SetPoint("TOPLEFT", queBox, "TOPLEFT", 238, -47)
        addQ:SetScript("OnClick", AddQueueTask)
        -- Queue list (h = midH - 80 - 34 = 42   use 54)
        local _, queueContent = ScrollList(queBox, 8, -74, queW-16, midH-108, queueCols)
        refs.queueContent = queueContent
        -- State buttons
        local qo = GMT.MBtn(queBox, "Open",   54, 20); qo:SetPoint("BOTTOMLEFT", queBox, "BOTTOMLEFT", 8, 8); qo:SetScript("OnClick", function() MarkQueueState("Open") end)
        local qi = GMT.MBtn(queBox, "In Prog", 60, 20); qi:SetPoint("LEFT", qo, "RIGHT", 4, 0); qi:SetScript("OnClick", function() MarkQueueState("In Progress") end)
        local qd = GMT.MBtn(queBox, "Done",   54, 20); qd:SetPoint("LEFT", qi, "RIGHT", 4, 0); qd:SetScript("OnClick", function() MarkQueueState("Done") end)
        local qr = GMT.MBtn(queBox, "Remove", 62, 20); qr:SetPoint("LEFT", qd, "RIGHT", 4, 0); qr:SetScript("OnClick", RemoveQueueSelected)

        -- +================================================ 
        -- |  REGISTRY ROW: Gatherers | Crafters           |
        -- +================================================ 
        local gathBox  = Sec(panel, "Gatherer Registry",  PAD,          regY, regW, regH)
        local craftBox = Sec(panel, "Crafter Registry",   PAD+regW+GAP, regY, regW, regH)

        -- GATHERER
        refs.gCount = gathBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.gCount:SetPoint("TOPRIGHT", gathBox, "TOPRIGHT", -12, -32)
        refs.gCount:SetTextColor(GMT.U(GMT.C.txtDim))

        Lbl(gathBox, "Name:", 10, -32);      refs.gName  = Inp(gathBox, 52,  -30, 100, 18)
        Lbl(gathBox, "Materials:", 10, -54); refs.gMats  = Inp(gathBox, 74,  -52, 140, 18)
        Lbl(gathBox, "Notes:", 10, -76);     refs.gNotes = Inp(gathBox, 52,  -74, 180, 18)

        local gAdd = GMT.MBtn(gathBox, "Save",   58, 18); gAdd:SetPoint("TOPLEFT", gathBox, "TOPLEFT", 240, -52); gAdd:SetScript("OnClick", AddGatherer)
        local gRem = GMT.MBtn(gathBox, "Remove", 70, 18); gRem:SetPoint("TOPLEFT", gathBox, "TOPLEFT", 240, -74); gRem:SetScript("OnClick", RemoveGathererSelected)

        -- Scroll list h = regH - 96 - 8 = 32   use 36
        local _, gatherContent = ScrollList(gathBox, 8, -96, regW-16, regH-104, gatherCols)
        refs.gatherContent = gatherContent

        -- CRAFTER
        refs.cCount = craftBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.cCount:SetPoint("TOPRIGHT", craftBox, "TOPRIGHT", -12, -32)
        refs.cCount:SetTextColor(GMT.U(GMT.C.txtDim))

        Lbl(craftBox, "Name:", 10, -32);       refs.cName = Inp(craftBox, 52,  -30, 100, 18)
        Lbl(craftBox, "Profession:", 10, -54); refs.cProf = Inp(craftBox, 78,  -52, 116, 18)
        Lbl(craftBox, "Recipes:", 10, -76);    refs.cRec  = Inp(craftBox, 60,  -74, 200, 18)

        local cAdd = GMT.MBtn(craftBox, "Save",   58, 18); cAdd:SetPoint("TOPLEFT", craftBox, "TOPLEFT", 204, -52); cAdd:SetScript("OnClick", AddCrafter)
        local cRem = GMT.MBtn(craftBox, "Remove", 70, 18); cRem:SetPoint("TOPLEFT", craftBox, "TOPLEFT", 204, -74); cRem:SetScript("OnClick", RemoveCrafterSelected)

        local _, crafterContent = ScrollList(craftBox, 8, -96, regW-16, regH-104, crafterCols)
        refs.crafterContent = crafterContent

        -- +================================================ 
        -- |  BOTTOM ROW: Notes | Activity Log             |
        -- +================================================ 
        local notBox = Sec(panel, "Operations Notes", PAD,          botY, notW, botH)
        local logBox = Sec(panel, "Activity Log",     PAD+notW+GAP, botY, logW, botH)

        refs.notes = MultiInp(notBox, 10, -30, notW-20, botH-42)
        local saveN = GMT.MBtn(notBox, "Save Notes", 96, 20)
        saveN:SetPoint("BOTTOMRIGHT", notBox, "BOTTOMRIGHT", -10, 8)
        saveN:SetScript("OnClick", function()
            EnsureDB().notes = refs.notes and refs.notes:GetText() or ""
            AddLog("Saved operations notes")
            SetStatus("Notes saved.", "green")
        end)

        local _, logContent = ScrollList(logBox, 8, -30, logW-16, botH-38, logCols)
        refs.logContent = logContent

        --    Status bar                                     
        refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Logistics Engine ready.")

        panel:SetScript("OnShow", function()
            if #LX.supplies == 0 then ScanSupplies() end
            RefreshAll()
        end)

        ScanSupplies()
        RefreshAll()
    end)

    if not ok and GMT and GMT.Err then
        GMT.Err("Logistics init failed: " .. tostring(err))
    end
end
