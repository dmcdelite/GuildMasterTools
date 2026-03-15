-- ============================================================
-- GuildMaster Tools  |  Modules/Economy.lua  |  v2.9.0
-- Phase 8 -- Guild Economy Dashboard
--
-- Guild Bank Scanner  .  Transaction Log  .  Gold Tracker
-- Contribution Ranking  .  Material Flow  .  Activity Log
-- ============================================================
local _, GMT = ...

GMT.EC = GMT.EC or {}
local EC = GMT.EC

--    Module state                                              
local refs       = {}
local ROW_H      = 20
local bankOpen   = false   -- true only while GUILDBANKFRAME is open
local scanQueue  = {}      -- tabs waiting to be queried
local scanTimer  = nil
local pendingBankTab = nil
local scanInProgress = false
local scannedStacks = 0
local scannedItemsTotal = 0
local pendingScanAttempts = 0
local maxScanAttempts = 6
local logScanPending = false
local logScanTimer = nil
local pendingLogQueries = 0
local receivedLogUpdates = 0
local lastLogQueryAt = 0
local logQueryQueue = {}
local currentLogQuery = nil
local logQueryAttempts = 0
local maxLogQueryAttempts = 4
local AttemptPendingBankTab, QueryNextBankTab
local AttemptPendingLogQuery, QueryNextLogTarget
local RefreshAll

EC.bankItems   = EC.bankItems   or {}   -- [{tab,name,count,quality}, ...]
EC.transactions= EC.transactions or {}  -- [{type,name,link,count,timeOff}, ...]
EC.contribs    = EC.contribs    or {}   -- [{name,deposits,items,gold}, ...]
local scanTransactionsBuffer = {}
local scanContribMap = {}

local _pack = table and table.pack or function(...)
    return { n = select("#", ...), ... }
end

-- ============================================================
-- DB HELPERS
-- ============================================================
local function EnsureDB()
    GMT.DB.economy = GMT.DB.economy or {}
    local db = GMT.DB.economy
    db.bankLog   = db.bankLog   or {}
    db.goldLog   = db.goldLog   or {}
    db.contribs  = db.contribs  or {}
    db.lastScan  = db.lastScan  or 0
    db.notes     = db.notes     or ""
    db.goldGoal  = db.goldGoal  or 0
    return db
end

local function AddLog(msg)
    local db = EnsureDB()
    table.insert(db.bankLog, 1, { t = time(), msg = msg })
    while #db.bankLog > 60 do table.remove(db.bankLog) end
end

-- ============================================================
-- STATUS BAR
-- ============================================================
local function IsGuildBankOpen()
    if bankOpen then return true end
    if GuildBankFrame and GuildBankFrame.IsShown and GuildBankFrame:IsShown() then
        return true
    end
    return false
end

local function SetStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Ready")
    if     kind == "green" then refs.status:SetTextColor(GMT.U(GMT.C.green))
    elseif kind == "red"   then refs.status:SetTextColor(GMT.U(GMT.C.red))
    else                        refs.status:SetTextColor(GMT.U(GMT.C.amber))
    end
end

-- ============================================================
-- UTILITY
-- ============================================================
local function CopperToGold(c)
    c = math.abs(c or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local co= c % 100
    if g > 0 then
        return string.format("|cffffd700%dg|r |cffaaaaaa%ds %dc|r", g, s, co)
    elseif s > 0 then
        return string.format("|cffaaaaaa%ds %dc|r", s, co)
    else
        return string.format("|cffaaaaaa%dc|r", co)
    end
end

local function FormatAgo(ts)
    if not ts or ts <= 0 then return GMT.Dim("--") end
    local d = time() - ts
    if d < 60    then return GMT.Green("Just now") end
    if d < 3600  then return math.floor(d/60) .. "m ago" end
    if d < 86400 then return math.floor(d/3600) .. "h ago" end
    return math.floor(d/86400) .. "d ago"
end

local QUALITY_COLOR = {
    [0] = "|cff9d9d9d",   -- Poor
    [1] = "|cffffffff",   -- Common
    [2] = "|cff1eff00",   -- Uncommon
    [3] = "|cff0070dd",   -- Rare
    [4] = "|cffa335ee",   -- Epic
    [5] = "|cffff8000",   -- Legendary
}
local QUALITY_LABEL = {
    [0] = "Poor",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
}
local function QColor(q)
    return QUALITY_COLOR[q or 1] or "|cffffffff"
end

local function QualityText(q)
    q = tonumber(q) or 1
    return (QColor(q) .. (QUALITY_LABEL[q] or "Common") .. "|r")
end

local TX_TYPE_SET = {
    deposit=true, withdraw=true, withdrawal=true, move=true, repair=true,
}

local function NormalizeGuildMemberName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+",""):gsub("%s+$","")
    if name == "" then return nil end
    return name
end

local function BuildGuildNameMap()
    local map = {}
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, total do
        local fullName = GetGuildRosterInfo and GetGuildRosterInfo(i)
        fullName = NormalizeGuildMemberName(fullName)
        if fullName then
            map[fullName:lower()] = fullName
            local short = fullName:match("^[^-]+") or fullName
            map[short:lower()] = short
        end
    end
    return map
end

local function ResolveTransactionActor(primaryName, itemLink, ...)
    local guildNames = BuildGuildNameMap()
    local function scoreCandidate(v)
        if type(v) ~= "string" then return nil, -1 end
        local s = NormalizeGuildMemberName(v)
        if not s then return nil, -1 end
        local lower = s:lower()
        if lower == "unknown" then return nil, -1 end
        if TX_TYPE_SET[lower] then return nil, -1 end
        if itemLink and s == itemLink then return nil, -1 end
        if s:find("|Hitem:") or s:find("^item:") or s:find("^|c") then return nil, -1 end
        if s:find("^Tab %d+") then return nil, -1 end
        if guildNames[lower] then
            return guildNames[lower], 100
        end
        local base = s:match("^[^-]+")
        if base and guildNames[base:lower()] then
            return guildNames[base:lower()], 90
        end
        if s:match("^[%a][%a'%-]+$") then return s, 50 end
        if s:match("^[%a][%a'%-]+%-%a[%a'%-]+$") then return s, 60 end
        return nil, -1
    end

    local bestName, bestScore = nil, -1
    local function consider(v)
        local cand, score = scoreCandidate(v)
        if cand and score > bestScore then
            bestName, bestScore = cand, score
        end
    end

    consider(primaryName)
    local n = select('#', ...)
    for i = 1, n do
        consider(select(i, ...))
    end
    return bestName or "Unknown"
end

-- ============================================================
-- UI HELPERS (local -- same pattern as other modules)
-- ============================================================
local function MkSection(parent, title, x, y, w, h)
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
    hdiv:SetHeight(2)
    hdiv:SetColorTexture(GMT.U(GMT.C.copper))
    hdiv:SetAlpha(0.85)
    local tf = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tf:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -7)
    tf:SetTextColor(GMT.U(GMT.C.txtTitle))
    tf:SetText(title)
    GMT.Rivets(box, 6, 4)
    return box
end

local function MkLabel(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(GMT.U(GMT.C.txtDim))
    fs:SetText(text or "")
    return fs
end

local function MkInput(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function MkScrollList(parent, x, y, w, h, cols)
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
    local hdr = CreateFrame("Frame", nil, frame)
    hdr:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    hdr:SetSize(w - 8, 18)
    local hb = hdr:CreateTexture(nil, "BACKGROUND")
    hb:SetAllPoints()
    hb:SetColorTexture(GMT.U(GMT.C.cardHead))
    local cx = 4
    for _, col in ipairs(cols) do
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", hdr, "LEFT", cx, 0)
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
    content:SetSize(w - 24, ROW_H)
    sf:SetScrollChild(content)
    return frame, content
end

local function MkRow(content, y, w)
    local btn = CreateFrame("Button", nil, content)
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    btn:SetSize(w, ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
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
        fs:SetWidth(col.w - 6)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(vals[i] or "")
        x = x + col.w
    end
end

-- ============================================================
-- GUILD BANK SCANNER
-- ============================================================
local function GetNumBankTabs()
    if C_GuildBank and C_GuildBank.GetNumGuildBankTabs then
        return C_GuildBank.GetNumGuildBankTabs() or 0
    end
    return GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
end

local function GetBankTabInfo(tab)
    if C_GuildBank and C_GuildBank.GetGuildBankTabInfo then
        local info = C_GuildBank.GetGuildBankTabInfo(tab)
        if info then return info.name, info.icon, info.isViewable end
    end
    if GetGuildBankTabInfo then
        local name, icon, isViewable = GetGuildBankTabInfo(tab)
        return name, icon, isViewable
    end
    return "Tab "..tab, nil, false
end

local function GetBankNumSlots(tab)
    local slots = 0
    if C_GuildBank and C_GuildBank.GetNumGuildBankSlots then
        slots = C_GuildBank.GetNumGuildBankSlots(tab) or 0
    elseif GetNumGuildBankSlots then
        slots = GetNumGuildBankSlots(tab) or 0
    end
    if (slots or 0) <= 0 then
        -- Default guild bank tabs are 98 slots when tab data has not populated yet.
        slots = 98
    end
    return slots
end

local scanTip
local function GetScanTooltip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "GuildMasterToolsGuildBankScanTooltip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

local function GetTooltipItemName(tab, slot)
    local tip = GetScanTooltip()
    tip:ClearLines()

    if C_TooltipInfo and C_TooltipInfo.GetGuildBankItem then
        local data = C_TooltipInfo.GetGuildBankItem(tab, slot)
        if data then
            if data.hyperlink then
                local name = data.hyperlink:match("%[(.-)%]")
                if name and name ~= "" then return name, data.hyperlink end
            end
            if data.lines then
                for _, line in ipairs(data.lines) do
                    local left = line.leftText or (line.leftTextData and line.leftTextData.text)
                    if left and left ~= "" then
                        return left, data.hyperlink
                    end
                end
            end
        end
    end

    if tip.SetGuildBankItem then
        pcall(function() tip:SetGuildBankItem(tab, slot) end)
        local name = _G[tip:GetName() .. "TextLeft1"]
        local txt = name and name:GetText()
        local _, link = tip:GetItem()
        tip:Hide()
        if txt and txt ~= "" then
            return txt, link
        end
        if link then
            local lname = link:match("%[(.-)%]")
            if lname and lname ~= "" then return lname, link end
        end
    end

    return nil, nil
end

local function ScanBankTab(tab)
    local items = {}
    local slots = GetBankNumSlots(tab)
    local occupiedSlots = 0
    local currentTab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or tab

    for slot = 1, slots do
        local readTab = currentTab or tab
        local link = GetGuildBankItemLink and GetGuildBankItemLink(readTab, slot)
        local icon, count, _, _, quality
        if GetGuildBankItemInfo then
            icon, count, _, _, quality = GetGuildBankItemInfo(readTab, slot)
        end

        local tipName, tipLink
        if not link and not icon and (count or 0) <= 0 then
            tipName, tipLink = GetTooltipItemName(readTab, slot)
            link = link or tipLink
        end

        local hasItem = (link ~= nil) or (icon ~= nil) or ((count or 0) > 0) or (tipName ~= nil)
        if hasItem then
            occupiedSlots = occupiedSlots + 1
            local name = tipName or (link and (link:match("%[(.-)%]") or "Unknown")) or "Unknown Item"
            count   = tonumber(count) or 1
            if count < 1 then count = 1 end
            quality = quality or 1
            table.insert(items, {
                tab     = tab,
                name    = name,
                link    = link,
                count   = count,
                quality = quality,
            })
        end
    end
    return items, occupiedSlots, slots
end

local function CommitScannedTab(tab, items, occupiedSlots, totalSlots)
    occupiedSlots = occupiedSlots or 0
    totalSlots = totalSlots or GetBankNumSlots(tab)
    local tabStacks = 0
    local tabItems = 0
    for _, item in ipairs(items or {}) do
        table.insert(EC.bankItems, item)
        scannedItemsTotal = scannedItemsTotal + (item.count or 0)
        scannedStacks = scannedStacks + 1
        tabStacks = tabStacks + 1
        tabItems = tabItems + (item.count or 0)
    end
    AddLog(string.format("Tab %d: %d/%d occupied slots, %d stacks, ~%d items", tab or 0, occupiedSlots, totalSlots, tabStacks, tabItems))
end

local function FinishBankScan()
    scanInProgress = false
    pendingBankTab = nil
    EnsureDB().lastScan = time()
    AddLog("Bank scan: " .. #EC.bankItems .. " stacks, ~" .. scannedItemsTotal .. " total items")
    SetStatus("Bank scan complete: " .. #EC.bankItems .. " stacks found.", "green")
    if RefreshAll then RefreshAll() end
end

AttemptPendingBankTab = function(finalAttempt)
    local tab = pendingBankTab
    if not tab then return end

    local items, occupiedSlots, totalSlots = ScanBankTab(tab)
    local gotData = occupiedSlots > 0 or #items > 0

    if not gotData then
        AddLog(string.format("Tab %d read returned empty (slots=%d).", tab, totalSlots or 0))
    end

    if gotData or finalAttempt then
        CommitScannedTab(tab, items, occupiedSlots, totalSlots)
        pendingBankTab = nil
        pendingScanAttempts = 0
        QueryNextBankTab()
        return
    end

    pendingScanAttempts = pendingScanAttempts + 1
    AddLog(string.format("Tab %d pending... attempt %d/%d", tab, pendingScanAttempts, maxScanAttempts))
    scanTimer = C_Timer.After(0.45, function()
        AttemptPendingBankTab(pendingScanAttempts >= maxScanAttempts)
    end)
end

QueryNextBankTab = function()
    if scanTimer and scanTimer.Cancel then
        pcall(function() scanTimer:Cancel() end)
    end
    scanTimer = nil

    pendingBankTab = table.remove(scanQueue, 1)
    pendingScanAttempts = 0
    if not pendingBankTab then
        FinishBankScan()
        return
    end

    if SetCurrentGuildBankTab then
        pcall(SetCurrentGuildBankTab, pendingBankTab)
    end
    if QueryGuildBankTab then
        pcall(QueryGuildBankTab, pendingBankTab)
    end

    AddLog(string.format("Querying tab %d...", pendingBankTab))
    scanTimer = C_Timer.After(0.55, function()
        AttemptPendingBankTab(false)
    end)
end

local function StartBankScan()
    if not IsGuildBankOpen() then
        SetStatus("Open the Guild Bank window first, then scan.", "red")
        return
    end

    EC.bankItems = {}
    scanQueue = {}
    scannedStacks = 0
    scannedItemsTotal = 0

    local numTabs = GetNumBankTabs()
    if numTabs == 0 then
        SetStatus("No guild bank tabs accessible.", "red")
        AddLog("Bank scan: no tabs accessible")
        return
    end

    for tab = 1, numTabs do
        local _, _, viewable = GetBankTabInfo(tab)
        if viewable then
            table.insert(scanQueue, tab)
        end
    end

    if #scanQueue == 0 then
        SetStatus("No viewable guild bank tabs found.", "red")
        AddLog("Bank scan: no viewable tabs")
        return
    end

    scanInProgress = true
    pendingBankTab = nil
    pendingScanAttempts = 0
    SetStatus("Scanning guild bank tabs...", nil)
    AddLog("Bank scan started: " .. #scanQueue .. " tab(s) queued")
    QueryNextBankTab()
end

-- ============================================================
-- TRANSACTION LOG PARSER
-- ============================================================
local TRANS_ICONS = {
    deposit  = GMT and GMT.Green  and GMT.Green("+")  or "+",
    withdraw = GMT and GMT.Red    and GMT.Red("-")    or "-",
    move     = GMT and GMT.Amber  and GMT.Amber("~")  or "~",
    repair   = GMT and GMT.Dim    and GMT.Dim("R")    or "R",
    depositMoney  = GMT and GMT.Green and GMT.Green("G+") or "G+",
    withdrawMoney = GMT and GMT.Red   and GMT.Red("G-")  or "G-",
    withdrawal = GMT and GMT.Red    and GMT.Red("-")    or "-",
}

local function MakeWhenText(years, months, days, hours)
    if type(years) == "number" and type(months) == "number" and type(days) == "number" and type(hours) == "number" then
        local totalHours = math.max(0, hours or 0)
        totalHours = totalHours + (math.max(0, days or 0) * 24)
        totalHours = totalHours + (math.max(0, months or 0) * 30 * 24)
        totalHours = totalHours + (math.max(0, years or 0) * 365 * 24)
        if totalHours <= 0 then
            return GMT.Green("Just now")
        end
        local secs = totalHours * 3600
        return FormatAgo(time() - secs)
    end
    return GMT.Dim("--")
end

local function NormalizeMoneyType(transType)
    if transType == "deposit" then return "depositMoney" end
    if transType == "withdraw" or transType == "withdrawal" then return "withdrawMoney" end
    return transType
end

local function GetOrCreateContrib(contribMap, name)
    name = (name and name ~= "") and name or "Unknown"
    if not contribMap[name] then
        contribMap[name] = { name=name, deposits=0, items=0, withdrawals=0, gold=0, moves=0 }
    end
    return contribMap[name]
end

local function ResetTransactionBuffers()
    wipe(scanTransactionsBuffer)
    wipe(scanContribMap)
end

local function RebuildContribMapFromTransactions()
    wipe(scanContribMap)
    for i = 1, #scanTransactionsBuffer do
        local e = scanTransactionsBuffer[i]
        local name = (e and e.name and e.name ~= "") and e.name or "Unknown"
        local contrib = GetOrCreateContrib(scanContribMap, name)
        local kind = e and e.kind or nil
        if kind == "deposit" then
            contrib.deposits = (contrib.deposits or 0) + 1
            contrib.items = (contrib.items or 0) + (tonumber(e.count) or 0)
        elseif kind == "withdraw" or kind == "withdrawal" then
            contrib.withdrawals = (contrib.withdrawals or 0) + 1
        elseif kind == "move" then
            contrib.moves = (contrib.moves or 0) + 1
        elseif kind == "depositMoney" then
            contrib.deposits = (contrib.deposits or 0) + 1
            contrib.gold = (contrib.gold or 0) + (tonumber(e.money) or 0)
        elseif kind == "withdrawMoney" or kind == "repair" then
            contrib.withdrawals = (contrib.withdrawals or 0) + 1
        end
    end
end

local function FinalizeContribsFromMap(contribMap)
    local out = {}
    for _, v in pairs(contribMap) do
        table.insert(out, v)
    end
    table.sort(out, function(a,b)
        local as = (a.items or 0) + math.floor((a.gold or 0) / 10000) + ((a.deposits or 0) * 10) - ((a.withdrawals or 0) * 5)
        local bs = (b.items or 0) + math.floor((b.gold or 0) / 10000) + ((b.deposits or 0) * 10) - ((b.withdrawals or 0) * 5)
        if as == bs then
            return (a.deposits or 0) > (b.deposits or 0)
        end
        return as > bs
    end)
    return out
end

local function SnapshotTransactionsFromBuffers()
    EC.transactions = {}
    for i = 1, #scanTransactionsBuffer do
        EC.transactions[i] = scanTransactionsBuffer[i]
    end
    EC.contribs = FinalizeContribsFromMap(scanContribMap)

    local db = EnsureDB()
    db.contribs = {}
    for i = 1, math.min(#EC.contribs, 50) do
        table.insert(db.contribs, EC.contribs[i])
    end
end

local function ParseCurrentLogTarget(query)
    if not query then return { parsedCount = 0, unknownNames = 0 } end
    query.parsed = true

    local sourceKey = (query.kind or "?") .. ":" .. tostring(query.tab or query.logTab or "?")
    for i = #scanTransactionsBuffer, 1, -1 do
        local e = scanTransactionsBuffer[i]
        if e and e.sourceKey == sourceKey then
            table.remove(scanTransactionsBuffer, i)
        end
    end

    local parsedCount, unknownNames = 0, 0

    if query.kind == "money" then
        local numMoney = 0
        if GetNumGuildBankMoneyTransactions then
            numMoney = GetNumGuildBankMoneyTransactions() or 0
        end
        for i = 1, numMoney do
            local r = _pack(GetGuildBankMoneyTransaction and GetGuildBankMoneyTransaction(i) or nil)
            local transType, rawName, amount, years, months, days, hours = r[1], r[2], r[3], r[4], r[5], r[6], r[7]
            if transType then
                local name = ResolveTransactionActor(rawName, nil, unpack(r, 2, r.n or #r))
                local kind = NormalizeMoneyType(transType)
                table.insert(scanTransactionsBuffer, {
                    kind     = kind,
                    name     = name,
                    link     = CopperToGold(amount or 0),
                    count    = 0,
                    money    = amount or 0,
                    whenText = MakeWhenText(years, months, days, hours),
                    tab      = "Gold",
                    sourceKey = sourceKey,
                })
                parsedCount = parsedCount + 1
                if name == "Unknown" then unknownNames = unknownNames + 1 end
            end
        end
        RebuildContribMapFromTransactions()
        return { parsedCount = parsedCount, unknownNames = unknownNames }
    end

    local tab = query.tab
    local numTrans = 0
    if GetNumGuildBankTransactions then
        numTrans = GetNumGuildBankTransactions(tab) or 0
    end
    for i = 1, numTrans do
        local r = _pack(GetGuildBankTransaction and GetGuildBankTransaction(tab, i) or nil)
        local transType, rawName, itemLink, count, tab1, tab2, years, months, days, hours =
            r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]
        if transType then
            local name = ResolveTransactionActor(rawName, itemLink, unpack(r, 2, r.n or #r))
            local displayLink = itemLink or ""
            if displayLink == "" then
                if transType == "move" then
                    local fromName = (tab1 and GetBankTabInfo and GetBankTabInfo(tab1)) or (tab1 and ("Tab "..tostring(tab1))) or "?"
                    local toName = (tab2 and GetBankTabInfo and GetBankTabInfo(tab2)) or (tab2 and ("Tab "..tostring(tab2))) or "?"
                    displayLink = string.format("Move %s -> %s", fromName, toName)
                else
                    displayLink = transType
                end
            end
            table.insert(scanTransactionsBuffer, {
                kind     = transType,
                name     = name,
                link     = displayLink,
                count    = tonumber(count) or 0,
                whenText = MakeWhenText(years, months, days, hours),
                tab      = tab,
                fromTab  = tab1,
                toTab    = tab2,
                sourceKey = sourceKey,
            })
            parsedCount = parsedCount + 1
            if name == "Unknown" then unknownNames = unknownNames + 1 end
        end
    end
    RebuildContribMapFromTransactions()
    return { parsedCount = parsedCount, unknownNames = unknownNames }
end

local function ParseTransactions()
    if #scanTransactionsBuffer > 0 or next(scanContribMap) ~= nil then
        SnapshotTransactionsFromBuffers()
        AddLog("Parsed " .. #EC.transactions .. " transactions, " .. #EC.contribs .. " contributors")
        SetStatus("Transaction parse complete: " .. #EC.transactions .. " entries.", #EC.transactions > 0 and "green" or nil)
        return
    end

    EC.transactions = {}
    EC.contribs     = {}
    local contribMap = {}

    local numTabs = math.max(GetNumBankTabs(), 0)
    for tab = 1, numTabs do
        local numTrans = 0
        if GetNumGuildBankTransactions then
            numTrans = GetNumGuildBankTransactions(tab) or 0
        end
        for i = 1, numTrans do
            local r = _pack(GetGuildBankTransaction and GetGuildBankTransaction(tab, i) or nil)
            local transType, rawName, itemLink, count, tab1, tab2, years, months, days, hours =
                r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]
            if transType then
                local name = ResolveTransactionActor(rawName, itemLink, unpack(r, 2, r.n or #r))
                local entry = {
                    kind     = transType,
                    name     = name,
                    link     = itemLink or transType or "",
                    count    = tonumber(count) or 0,
                    whenText = MakeWhenText(years, months, days, hours),
                    tab      = tab,
                    fromTab  = tab1,
                    toTab    = tab2,
                }
                table.insert(EC.transactions, entry)

                local contrib = GetOrCreateContrib(contribMap, name)
                if transType == "deposit" then
                    contrib.deposits  = contrib.deposits + 1
                    contrib.items     = contrib.items + (tonumber(count) or 0)
                elseif transType == "withdraw" or transType == "withdrawal" then
                    contrib.withdrawals = contrib.withdrawals + 1
                elseif transType == "move" then
                    contrib.moves = (contrib.moves or 0) + 1
                end
            end
        end
    end

    local numMoney = 0
    if GetNumGuildBankMoneyTransactions then
        numMoney = GetNumGuildBankMoneyTransactions() or 0
    end
    for i = 1, numMoney do
        local r = _pack(GetGuildBankMoneyTransaction and GetGuildBankMoneyTransaction(i) or nil)
        local transType, rawName, amount, years, months, days, hours =
            r[1], r[2], r[3], r[4], r[5], r[6], r[7]
        if transType then
            local name = ResolveTransactionActor(rawName, nil, unpack(r, 2, r.n or #r))
            local kind = NormalizeMoneyType(transType)
            table.insert(EC.transactions, {
                kind     = kind,
                name     = name,
                link     = CopperToGold(amount or 0),
                count    = 0,
                money    = amount or 0,
                whenText = MakeWhenText(years, months, days, hours),
                tab      = "Gold",
            })

            local contrib = GetOrCreateContrib(contribMap, name)
            if transType == "deposit" then
                contrib.deposits = contrib.deposits + 1
                contrib.gold = contrib.gold + (amount or 0)
            elseif transType == "withdraw" or transType == "withdrawal" or transType == "repair" then
                contrib.withdrawals = contrib.withdrawals + 1
            end
        end
    end

    EC.contribs = FinalizeContribsFromMap(contribMap)

    local db = EnsureDB()
    db.contribs = {}
    for i = 1, math.min(#EC.contribs, 50) do
        table.insert(db.contribs, EC.contribs[i])
    end

    AddLog("Parsed " .. #EC.transactions .. " transactions, " .. #EC.contribs .. " contributors")
    SetStatus("Transaction parse complete: " .. #EC.transactions .. " entries.", #EC.transactions > 0 and "green" or nil)
end

local function ScheduleTransactionRepaint()
    local tries = {0.35, 1.0, 2.5, 5.0, 8.0}
    for _, delay in ipairs(tries) do
        C_Timer.After(delay, function()
            if not logScanPending then
                ParseTransactions()
                if RefreshAll then RefreshAll() end
            end
        end)
    end
end

local function FinishTransactionScan()
    logScanPending = false
    pendingLogQueries = 0
    receivedLogUpdates = 0
    currentLogQuery = nil
    logQueryQueue = {}
    logQueryAttempts = 0
    if logScanTimer and logScanTimer.Cancel then
        pcall(function() logScanTimer:Cancel() end)
    end
    logScanTimer = nil
    ParseTransactions()
    if RefreshAll then RefreshAll() end
    ScheduleTransactionRepaint()
end

AttemptPendingLogQuery = function(finalAttempt)
    if not currentLogQuery then return end

    local sawUpdate = currentLogQuery.sawUpdate and true or false
    local num = 0
    if currentLogQuery.kind == "money" then
        num = GetNumGuildBankMoneyTransactions and (GetNumGuildBankMoneyTransactions() or 0) or 0
    else
        num = GetNumGuildBankTransactions and (GetNumGuildBankTransactions(currentLogQuery.tab) or 0) or 0
    end

    local ready = false
    if sawUpdate then
        -- Once the client has actually fired a log update for the active query,
        -- treat the current count as authoritative even when it is zero.
        ready = true
    elseif finalAttempt then
        ready = true
    end

    if ready then
        receivedLogUpdates = receivedLogUpdates + 1
        local stats = ParseCurrentLogTarget(currentLogQuery) or { parsedCount = 0, unknownNames = 0 }
        SnapshotTransactionsFromBuffers()
        if RefreshAll then RefreshAll() end
        AddLog(string.format("Log query complete: %s (%d entr%s, %d unknown)%s",
            currentLogQuery.label or tostring(currentLogQuery.tab or "money"),
            stats.parsedCount or num or 0,
            ((stats.parsedCount or num or 0) == 1) and "y" or "ies",
            stats.unknownNames or 0,
            sawUpdate and "" or " [timeout]"))

        currentLogQuery.passCount = (currentLogQuery.passCount or 0)
        if (stats.unknownNames or 0) > 0 and currentLogQuery.passCount < 2 then
            currentLogQuery.passCount = currentLogQuery.passCount + 1
            currentLogQuery.parsed = false
            currentLogQuery.sawUpdate = false
            table.insert(logQueryQueue, currentLogQuery)
            AddLog(string.format("Requery queued: %s (pass %d)", currentLogQuery.label or tostring(currentLogQuery.tab or "money"), currentLogQuery.passCount + 1))
        end

        currentLogQuery = nil
        logQueryAttempts = 0
        QueryNextLogTarget()
        return
    end

    logQueryAttempts = logQueryAttempts + 1
    logScanTimer = C_Timer.After(0.50, function()
        AttemptPendingLogQuery(logQueryAttempts >= maxLogQueryAttempts)
    end)
end

QueryNextLogTarget = function()
    if logScanTimer and logScanTimer.Cancel then
        pcall(function() logScanTimer:Cancel() end)
    end
    logScanTimer = nil

    currentLogQuery = table.remove(logQueryQueue, 1)
    logQueryAttempts = 0
    if currentLogQuery then
        currentLogQuery.sawUpdate = false
    end
    if not currentLogQuery then
        FinishTransactionScan()
        return
    end

    if currentLogQuery.kind == "tab" then
        if SetCurrentGuildBankTab then pcall(SetCurrentGuildBankTab, currentLogQuery.tab) end
        if QueryGuildBankTab then pcall(QueryGuildBankTab, currentLogQuery.tab) end
        if QueryGuildBankLog then pcall(QueryGuildBankLog, currentLogQuery.tab) end
    else
        if QueryGuildBankLog then pcall(QueryGuildBankLog, currentLogQuery.logTab) end
    end

    AddLog(string.format("Querying log: %s", currentLogQuery.label or tostring(currentLogQuery.tab or currentLogQuery.logTab or "?")))
    logScanTimer = C_Timer.After(0.60, function()
        AttemptPendingLogQuery(false)
    end)
end

local function RequestTransactionScan()
    if not IsGuildBankOpen() then
        SetStatus("Open the Guild Bank window first, then scan.", "red")
        return
    end

    local numTabs = math.max(GetNumBankTabs(), 0)
    if not QueryGuildBankLog or numTabs <= 0 then
        ParseTransactions()
        RefreshAll()
        return
    end

    pendingLogQueries = 0
    receivedLogUpdates = 0
    lastLogQueryAt = time()
    logQueryQueue = {}
    currentLogQuery = nil
    ResetTransactionBuffers()
    EC.transactions = {}
    EC.contribs = {}

    for tab = 1, numTabs do
        table.insert(logQueryQueue, { kind = "tab", tab = tab, label = "Tab " .. tab, passCount = 0 })
        pendingLogQueries = pendingLogQueries + 1
    end

    if GetNumGuildBankMoneyTransactions or GetGuildBankMoneyTransaction then
        local moneyTab = (MAX_GUILDBANK_TABS or numTabs or 0) + 1
        table.insert(logQueryQueue, { kind = "money", logTab = moneyTab, label = "Money", passCount = 0 })
        pendingLogQueries = pendingLogQueries + 1
    end

    if pendingLogQueries <= 0 then
        ParseTransactions()
        RefreshAll()
        return
    end

    logScanPending = true
    SetStatus("Querying guild bank logs...", nil)
    AddLog("Transaction log scan requested: " .. pendingLogQueries .. " query(s)")
    QueryNextLogTarget()
end

-- ============================================================
-- GOLD TRACKER
-- ============================================================
local function GetBankGoldFormatted()
    local copper = 0
    if GetGuildBankMoney then
        copper = GetGuildBankMoney() or 0
    end
    return CopperToGold(copper), copper
end

local function LogGoldEntry(note, amount)
    local db = EnsureDB()
    table.insert(db.goldLog, 1, {
        t      = time(),
        note   = note or "",
        amount = amount or 0,
    })
    while #db.goldLog > 40 do table.remove(db.goldLog) end
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
local bankCols = {
    { label="Tab",    w=70,  j="LEFT"   },
    { label="Item",   w=200, j="LEFT"   },
    { label="Stack",  w=52,  j="CENTER" },
    { label="Qual",   w=70,  j="LEFT"   },
}
local transCols = {
    { label="",       w=26,  j="CENTER" },
    { label="Player", w=110, j="LEFT"   },
    { label="Item",   w=160, j="LEFT"   },
    { label="#",      w=38,  j="CENTER" },
    { label="When",   w=68,  j="LEFT"   },
}
local contribCols = {
    { label="#",      w=28,  j="CENTER" },
    { label="Member", w=140, j="LEFT"   },
    { label="Dep",    w=46,  j="CENTER" },
    { label="Items",  w=52,  j="CENTER" },
    { label="Wdr",    w=46,  j="CENTER" },
    { label="Net",    w=60,  j="LEFT"   },
}
local goldCols = {
    { label="Time",   w=62,  j="LEFT"   },
    { label="Note",   w=220, j="LEFT"   },
    { label="Amount", w=100, j="LEFT"   },
}
local logCols = {
    { label="Activity", w=890, j="LEFT" },
}

local function RefreshSummary()
    local db = EnsureDB()
    if refs.sumTabs then
        refs.sumTabs:SetText(GMT.Amber(tostring(GetNumBankTabs())))
    end
    if refs.sumStacks then
        refs.sumStacks:SetText(GMT.Green(tostring(#EC.bankItems)))
    end
    if refs.sumContribs then
        refs.sumContribs:SetText(GMT.Green(tostring(#EC.contribs)))
    end
    if refs.sumTrans then
        refs.sumTrans:SetText(GMT.Amber(tostring(#EC.transactions)))
    end
    if refs.bankGold then
        local goldStr = GetBankGoldFormatted()
        refs.bankGold:SetText(goldStr)
    end
    if refs.lastScan then
        refs.lastScan:SetText(FormatAgo(db.lastScan))
    end
    if refs.bankStatus then
        refs.bankStatus:SetText(bankOpen and GMT.Green("Open") or GMT.Grey("Closed"))
    end
end

local function RefreshBankList()
    if not refs.bankContent then return end
    refs.bankRows = refs.bankRows or {}
    local rows = refs.bankRows
    local numTabs = GetNumBankTabs()

    for i, item in ipairs(EC.bankItems) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.bankContent, -((i-1)*ROW_H), 400)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.08, 0.06, 0.04, i%2==0 and 0.28 or 0.12)
        row:Show()
        local tabName = "Tab"
        if GetBankTabInfo then
            tabName = GetBankTabInfo(item.tab) or ("Tab"..item.tab)
        end
        local qualStr = QualityText(item.quality)
        FillRow(row, bankCols, {
            GMT.Clip(tabName, 10),
            GMT.Clip(item.name, 26),
            tostring(item.count),
            qualStr,
        })
    end
    for i = #EC.bankItems + 1, #rows do rows[i]:Hide() end

    if #EC.bankItems == 0 then
        if not refs.bankEmpty then
            refs.bankEmpty = refs.bankContent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            refs.bankEmpty:SetPoint("TOPLEFT", refs.bankContent, "TOPLEFT", 4, -4)
            refs.bankEmpty:SetTextColor(GMT.U(GMT.C.txtDim))
        end
        refs.bankEmpty:SetText(
            bankOpen
            and GMT.Amber("Click 'Scan Bank' with the guild bank open.")
            or  GMT.Dim("Open the guild bank, then click Scan Bank.")
        )
        refs.bankEmpty:Show()
    else
        if refs.bankEmpty then refs.bankEmpty:Hide() end
    end

    refs.bankContent:SetHeight(math.max(ROW_H, #EC.bankItems * ROW_H))
end

local function RefreshTransList()
    if not refs.transContent then return end
    refs.transRows = refs.transRows or {}
    local rows = refs.transRows
    for i, entry in ipairs(EC.transactions) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.transContent, -((i-1)*ROW_H), 460)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.08, 0.06, 0.04, i%2==0 and 0.28 or 0.12)
        row:Show()
        local icon = TRANS_ICONS[entry.kind] or GMT.Dim("?")
        local itemDisplay = entry.link ~= "" and (entry.link:match("%[(.-)%]") or entry.link) or ""
        if itemDisplay == "" then
            if entry.kind == "depositMoney" then itemDisplay = "Gold Deposit"
            elseif entry.kind == "withdrawMoney" then itemDisplay = "Gold Withdraw"
            else itemDisplay = entry.kind or "Transaction" end
        end
        local ago = entry.whenText or GMT.Dim("--")
        FillRow(row, transCols, {
            icon,
            GMT.Short(entry.name),
            GMT.Clip(itemDisplay, 20),
            entry.count > 0 and tostring(entry.count) or "",
            ago,
        })
    end
    for i = #EC.transactions + 1, #rows do rows[i]:Hide() end
    if #EC.transactions == 0 then
        if not refs.transEmpty then
            refs.transEmpty = refs.transContent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            refs.transEmpty:SetPoint("TOPLEFT", refs.transContent, "TOPLEFT", 4, -4)
            refs.transEmpty:SetTextColor(GMT.U(GMT.C.txtDim))
        end
        refs.transEmpty:SetText(GMT.Dim("Open guild bank and click Scan Transactions."))
        refs.transEmpty:Show()
    else
        if refs.transEmpty then refs.transEmpty:Hide() end
    end
    refs.transContent:SetHeight(math.max(ROW_H, #EC.transactions * ROW_H))
end

local function RefreshContribList()
    if not refs.contribContent then return end
    refs.contribRows = refs.contribRows or {}
    local rows = refs.contribRows
    for i, entry in ipairs(EC.contribs) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.contribContent, -((i-1)*ROW_H), 440)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.08, 0.06, 0.04, i%2==0 and 0.28 or 0.12)
        row:Show()
        local net = (entry.deposits or 0) - (entry.withdrawals or 0)
        local netStr = net > 0 and GMT.Green("+"..net) or (net < 0 and GMT.Red(tostring(net)) or GMT.Dim("0"))
        -- Top 3 get a gold/silver/bronze rank indicator
        local rank = i <= 3 and ({" "," ","*"})[i] or tostring(i)
        if i == 1 then rank = GMT.Gold(" ") end
        if i == 2 then rank = "|cffcccccc |r" end
        if i == 3 then rank = "|cffaa7733*|r" end
        FillRow(row, contribCols, {
            rank,
            GMT.Short(entry.name),
            tostring(entry.deposits),
            tostring(entry.items),
            tostring(entry.withdrawals),
            netStr,
        })
    end
    for i = #EC.contribs + 1, #rows do rows[i]:Hide() end
    if #EC.contribs == 0 then
        if not refs.contribEmpty then
            refs.contribEmpty = refs.contribContent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            refs.contribEmpty:SetPoint("TOPLEFT", refs.contribContent, "TOPLEFT", 4, -4)
            refs.contribEmpty:SetTextColor(GMT.U(GMT.C.txtDim))
        end
        refs.contribEmpty:SetText(GMT.Dim("Scan Transactions to build the contribution ranking."))
        refs.contribEmpty:Show()
    else
        if refs.contribEmpty then refs.contribEmpty:Hide() end
    end
    refs.contribContent:SetHeight(math.max(ROW_H, #EC.contribs * ROW_H))
end

local function RefreshGoldLog()
    if not refs.goldContent then return end
    refs.goldRows = refs.goldRows or {}
    local rows = refs.goldRows
    local log = EnsureDB().goldLog
    for i, entry in ipairs(log) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.goldContent, -((i-1)*ROW_H), 450)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.08, 0.06, 0.04, i%2==0 and 0.28 or 0.12)
        row:Show()
        FillRow(row, goldCols, {
            date("%H:%M", entry.t or time()),
            GMT.Clip(entry.note or "", 28),
            CopperToGold(entry.amount or 0),
        })
    end
    for i = #log + 1, #rows do rows[i]:Hide() end
    refs.goldContent:SetHeight(math.max(ROW_H, #log * ROW_H))
end

local function RefreshLog()
    if not refs.logContent then return end
    refs.logRows = refs.logRows or {}
    local rows = refs.logRows
    local log = EnsureDB().bankLog
    for i, entry in ipairs(log) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.logContent, -((i-1)*ROW_H), 900)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.08, 0.06, 0.04, i%2==0 and 0.28 or 0.12)
        row:Show()
        local line = date("%H:%M", entry.t or time()) .. "  " .. (entry.msg or "")
        FillRow(row, logCols, { GMT.Clip(line, 100) })
    end
    for i = #log + 1, #rows do rows[i]:Hide() end
    refs.logContent:SetHeight(math.max(ROW_H, #log * ROW_H))
end

RefreshAll = function()
    RefreshSummary()
    RefreshBankList()
    RefreshTransList()
    RefreshContribList()
    RefreshGoldLog()
    RefreshLog()
end

-- ============================================================
-- INIT
-- ============================================================
function GMT_Economy_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Economy")
        if not panel or panel._economyBuilt then return end
        panel._economyBuilt = true

        EnsureDB()

        GMT.Header(panel, "Guild Economy Dashboard", 14, -10)
        GMT.Label(panel, "Bank scanner . Transaction log . Contribution ranking . Gold tracker", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        --    Layout math                                   
        -- PW=960, PH=528
        -- Header+label+hline: 58px
        -- Summary: 66px  Mid: 196px  Bot: 124px  Log: 40px  Status: 12px
        -- Total: 58+8+66+8+196+8+124+8+40+12 = 528 (Y)
        local X1, W1 = 8,   460
        local X2, W2 = 476, 476

        local Y_SUM   = -66    -- Summary bar
        local H_SUM   = 66
        local Y_MID   = Y_SUM - H_SUM - 8    -- -140
        local H_MID   = 196
        local Y_BOT   = Y_MID - H_MID - 8    -- -344
        local H_BOT   = 124
        local Y_LOG   = Y_BOT - H_BOT - 8    -- -476
        local H_LOG   = 40
        --    SUMMARY BAR (full width)                       
        local sumBox = MkSection(panel, "  Economy Summary", 8, Y_SUM, GMT.PW - 16, H_SUM)

        local function SumStat(label, yref, x)
            local lbl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            lbl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", x, -34)
            lbl:SetTextColor(GMT.U(GMT.C.txtDim))
            lbl:SetText(label)
            local val = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            val:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            return val
        end

        refs.sumTabs    = SumStat("Bank Tabs",    nil,   14)
        refs.sumStacks  = SumStat("Stacks",       nil,  140)
        refs.sumContribs= SumStat("Contributors", nil,  260)
        refs.sumTrans   = SumStat("Transactions", nil,  410)

        -- Gold + scan time right-aligned
        local goldLbl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        goldLbl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 520, -34)
        goldLbl:SetTextColor(GMT.U(GMT.C.txtDim))
        goldLbl:SetText("Bank Gold")
        refs.bankGold = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        refs.bankGold:SetPoint("LEFT", goldLbl, "RIGHT", 8, 0)

        local scanLbl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        scanLbl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 14, -52)
        scanLbl:SetTextColor(GMT.U(GMT.C.txtDim))
        scanLbl:SetText("Last scan:")
        refs.lastScan = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.lastScan:SetPoint("LEFT", scanLbl, "RIGHT", 6, 0)

        local bankStatusLbl = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        bankStatusLbl:SetPoint("TOPLEFT", sumBox, "TOPLEFT", 160, -52)
        bankStatusLbl:SetTextColor(GMT.U(GMT.C.txtDim))
        bankStatusLbl:SetText("Bank window:")
        refs.bankStatus = sumBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.bankStatus:SetPoint("LEFT", bankStatusLbl, "RIGHT", 6, 0)

        -- Scan buttons anchored on the far-right side of the summary box
        local scanTransBtn = GMT.MBtn(sumBox, "Scan Transactions", 148, 24)
        scanTransBtn:SetPoint("TOPRIGHT", sumBox, "TOPRIGHT", -12, -34)
        scanTransBtn:SetScript("OnClick", function()
            if not IsGuildBankOpen() then
                SetStatus("Open the Guild Bank window first, then scan.", "red")
                return
            end
            RequestTransactionScan()
        end)

        local scanBankBtn = GMT.MBtn(sumBox, "Scan Bank Items", 134, 24)
        scanBankBtn:SetPoint("RIGHT", scanTransBtn, "LEFT", -8, 0)
        scanBankBtn:SetScript("OnClick", function()
            StartBankScan()
        end)

        --    BANK ITEMS (left, mid row)                     
        local bankBox = MkSection(panel, "  Guild Bank Contents", X1, Y_MID, W1, H_MID)
        local _, bankContent = MkScrollList(bankBox, 8, -30, W1 - 16, H_MID - 38, bankCols)
        refs.bankContent = bankContent

        --    TRANSACTION LOG (right, mid row)              
        local transBox = MkSection(panel, "  Transaction Log", X2, Y_MID, W2, H_MID)
        local _, transContent = MkScrollList(transBox, 8, -30, W2 - 16, H_MID - 38, transCols)
        refs.transContent = transContent

        --    CONTRIBUTION RANKING (left, bottom row)        
        local contribBox = MkSection(panel, "  Contribution Ranking", X1, Y_BOT, W1, H_BOT)
        local _, contribContent = MkScrollList(contribBox, 8, -30, W1 - 16, H_BOT - 38, contribCols)
        refs.contribContent = contribContent

        --    GOLD TRACKER (right, bottom row)              
        local goldBox = MkSection(panel, "  Gold Log", X2, Y_BOT, W2, H_BOT)

        -- Manual gold entry inputs
        MkLabel(goldBox, "Note", 10, -32)
        refs.goldNote = MkInput(goldBox, 10, -48, 194, 20)
        MkLabel(goldBox, "Amount (copper)", 214, -32)
        refs.goldAmt  = MkInput(goldBox, 214, -48, 100, 20)

        local goldAddBtn = GMT.MBtn(goldBox, "Log Entry", 90, 22)
        goldAddBtn:SetPoint("TOPLEFT", goldBox, "TOPLEFT", 322, -47)
        goldAddBtn:SetScript("OnClick", function()
            local note = refs.goldNote:GetText() or ""
            local amt  = tonumber(refs.goldAmt:GetText()) or 0
            if note == "" and amt == 0 then
                SetStatus("Enter a note or amount to log.", "red")
                return
            end
            LogGoldEntry(note, amt)
            refs.goldNote:SetText("")
            refs.goldAmt:SetText("")
            RefreshGoldLog()
            AddLog("Gold log entry: " .. note .. " " .. CopperToGold(amt))
            SetStatus("Gold entry logged.", "green")
        end)

        local _, goldContent = MkScrollList(goldBox, 8, -76, W2 - 16, H_BOT - 84, goldCols)
        refs.goldContent = goldContent

        --    ACTIVITY LOG removed to free bottom space
        refs.logContent = nil

        --    STATUS BAR                                     
        refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Economy dashboard ready.  Open Guild Bank to scan.")

        --    EVENTS                                         
        local evF = CreateFrame("Frame")
        evF:RegisterEvent("GUILDBANKFRAME_OPENED")
        evF:RegisterEvent("GUILDBANKFRAME_CLOSED")
        evF:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
        evF:RegisterEvent("GUILDBANKLOG_UPDATE")
        evF:SetScript("OnEvent", function(_, event)
            if event == "GUILDBANKFRAME_OPENED" then
                bankOpen = true
                SetStatus("Guild bank open -- ready to scan.", "green")
                AddLog("Guild bank window opened")
                RefreshSummary()
            elseif event == "GUILDBANKFRAME_CLOSED" then
                bankOpen = false
                SetStatus("Guild bank closed.", nil)
                RefreshSummary()
            elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
                if bankOpen and scanInProgress and pendingBankTab then
                    if scanTimer and scanTimer.Cancel then
                        pcall(function() scanTimer:Cancel() end)
                    end
                    scanTimer = C_Timer.After(0.10, function()
                        AttemptPendingBankTab(false)
                    end)
                elseif bankOpen and scanInProgress and not pendingBankTab and #scanQueue > 0 then
                    QueryNextBankTab()
                end
            elseif event == "GUILDBANKLOG_UPDATE" then
                if logScanPending then
                    if currentLogQuery then
                        currentLogQuery.sawUpdate = true
                    end
                    if logScanTimer and logScanTimer.Cancel then
                        pcall(function() logScanTimer:Cancel() end)
                    end
                    logScanTimer = C_Timer.After(0.25, function()
                        AttemptPendingLogQuery(false)
                    end)
                end
            end
        end)

        panel:SetScript("OnShow", function()
            RefreshAll()
        end)

        -- Restore persisted contribs from DB on load
        local db = EnsureDB()
        if #EC.contribs == 0 and #db.contribs > 0 then
            EC.contribs = db.contribs
        end

        RefreshAll()
    end)

    if not ok and GMT and GMT.Err then
        GMT.Err("Economy init failed: " .. tostring(err))
    end
end
