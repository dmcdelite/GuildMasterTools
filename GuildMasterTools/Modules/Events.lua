-- ============================================================
-- GuildMaster Tools  |  Modules/Events.lua  |  v3.4.0
-- Phase 13 -- Guild Event Planner
--
-- Event calendar . RSVP tracking . Reminder broadcasts
-- Recurring events . Countdown timers . Activity log
-- ============================================================
local _, GMT = ...

GMT.EV = GMT.EV or {}
local EV = GMT.EV

local refs  = {}
local ROW_H = 20

-- ============================================================
-- EVENT TYPES
-- ============================================================
local EVENT_TYPES = {
    { key="raid",    label="Raid",        color="|cffff9944" },
    { key="mythic",  label="Mythic+",     color="|cff9966ff" },
    { key="pvp",     label="PvP",         color="|cffff4444" },
    { key="social",  label="Social",      color="|cff44ee88" },
    { key="meeting", label="Meeting",     color="|cffffd700" },
    { key="other",   label="Other",       color="|cffaaaaaa" },
}

local function TypeColor(key)
    for _, t in ipairs(EVENT_TYPES) do
        if t.key == key then return t.color end
    end
    return "|cffaaaaaa"
end
local function TypeLabel(key)
    for _, t in ipairs(EVENT_TYPES) do
        if t.key == key then return t.label end
    end
    return key or "Other"
end

-- ============================================================
-- DB
-- ============================================================
local function EnsureDB()
    GMT.DB.events = GMT.DB.events or {}
    local db = GMT.DB.events
    db.events  = db.events  or {}
    db.log     = db.log     or {}
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
-- HELPERS
-- ============================================================
local function FormatTimestamp(ts)
    if not ts or ts <= 0 then return GMT.Dim("--") end
    return date("%a %b %d  %H:%M", ts)
end

local function Countdown(ts)
    if not ts or ts <= 0 then return GMT.Dim("--") end
    local diff = ts - time()
    if diff < 0 then return GMT.Red("Ended") end
    if diff < 3600 then
        return GMT.Green(math.floor(diff/60).."m")
    elseif diff < 86400 then
        return GMT.Amber(math.floor(diff/3600).."h "..math.floor((diff%3600)/60).."m")
    else
        return GMT.Dim(math.floor(diff/86400).."d "..math.floor((diff%86400)/3600).."h")
    end
end

local function ParseDatetime(dateStr, timeStr)
    -- dateStr: "YYYY-MM-DD", timeStr: "HH:MM"
    dateStr = dateStr or ""; timeStr = timeStr or "00:00"
    local y,mo,d  = dateStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    local h,mi    = timeStr:match("^(%d%d):(%d%d)$")
    if not y then return nil, "Date must be YYYY-MM-DD" end
    if not h then return nil, "Time must be HH:MM"      end
    -- Build timestamp via table
    local ok, ts = pcall(function()
        return time({ year=tonumber(y), month=tonumber(mo), day=tonumber(d),
                      hour=tonumber(h),  min=tonumber(mi),  sec=0 })
    end)
    if ok and ts then return ts, nil end
    return nil, "Invalid date/time"
end

local function MyName() return UnitName("player") or "Unknown" end

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
    local head = box:CreateTexture(nil,"BACKGROUND")
    head:SetPoint("TOPLEFT",  box, "TOPLEFT",   3,-3)
    head:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3,-3)
    head:SetHeight(24)
    head:SetColorTexture(GMT.U(GMT.C.cardHead))
    local hdiv = box:CreateTexture(nil,"ARTWORK")
    hdiv:SetPoint("TOPLEFT",  box, "TOPLEFT",   3,-27)
    hdiv:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3,-27)
    hdiv:SetHeight(1); hdiv:SetColorTexture(GMT.U(GMT.C.copper)); hdiv:SetAlpha(0.85)
    local tf = box:CreateFontString(nil,"OVERLAY","GameFontNormal")
    tf:SetPoint("TOPLEFT",box,"TOPLEFT",10,-8)
    tf:SetTextColor(GMT.U(GMT.C.txtTitle)); tf:SetText(title)
    GMT.Rivets(box,6,4)
    return box
end

local function Lbl(parent, text, x, y)
    local fs = parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    fs:SetTextColor(GMT.U(GMT.C.txtDim)); fs:SetText(text)
    return fs
end

local function Inp(parent, x, y, w, h)
    local eb = CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    eb:SetAutoFocus(false); eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    eb:SetTextInsets(6,6,2,2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    return eb
end

local function ScrollList(parent, x, y, w, h, cols)
    local fr = CreateFrame("Frame",nil,parent,"BackdropTemplate")
    fr:SetSize(w,h); fr:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
    fr:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=10,insets={left=3,right=3,top=3,bottom=3},
    })
    fr:SetBackdropColor(GMT.U(GMT.C.panelBg))
    fr:SetBackdropBorderColor(GMT.U(GMT.C.brass))
    local hdr = CreateFrame("Frame",nil,fr)
    hdr:SetPoint("TOPLEFT",fr,"TOPLEFT",4,-4); hdr:SetSize(w-8,18)
    local hb = hdr:CreateTexture(nil,"BACKGROUND"); hb:SetAllPoints()
    hb:SetColorTexture(GMT.U(GMT.C.cardHead))
    local cx=4
    for _,col in ipairs(cols) do
        local fs = hdr:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        fs:SetPoint("LEFT",hdr,"LEFT",cx,0); fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetTextColor(GMT.U(GMT.C.txtTitle)); fs:SetText(col.label)
        cx=cx+col.w
    end
    local sf = CreateFrame("ScrollFrame",nil,fr,"UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",fr,"TOPLEFT",4,-24); sf:SetSize(w-24,h-28)
    local content = CreateFrame("Frame",nil,sf)
    content:SetSize(w-24,20); sf:SetScrollChild(content)
    return fr, content
end

local function MkRow(content, idx, w)
    local btn = CreateFrame("Button",nil,content)
    btn:SetPoint("TOPLEFT",content,"TOPLEFT",0,-((idx-1)*ROW_H))
    btn:SetSize(w,ROW_H)
    btn.bg = btn:CreateTexture(nil,"BACKGROUND"); btn.bg:SetAllPoints()
    btn.cells = {}
    return btn
end

local function FillRow(row, cols, vals)
    local x=4
    for i,col in ipairs(cols) do
        local fs = row.cells[i]
        if not fs then
            fs = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.cells[i]=fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT",row,"LEFT",x,0)
        fs:SetWidth(col.w); fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(vals[i] or "")
        x=x+col.w
    end
end

-- ============================================================
-- COLUMNS
-- ============================================================
-- Event list: full width 944, content ~920
local eventCols = {
    { label="",       w=18,  j="CENTER" },
    { label="Event",  w=220, j="LEFT"   },
    { label="Type",   w=72,  j="LEFT"   },
    { label="When",   w=160, j="LEFT"   },
    { label="In",     w=80,  j="LEFT"   },
    { label="RSVP (Y)", w=56,  j="CENTER" },
    { label="RSVP (N)", w=56,  j="CENTER" },
    { label="Leader", w=110, j="LEFT"   },
}  -- total 772  (content ~920, fits)

local rsvpCols = {
    { label="Player",  w=140, j="LEFT"   },
    { label="Status",  w=80,  j="LEFT"   },
    { label="Note",    w=180, j="LEFT"   },
}  -- total 400

local logCols = { { label="Activity", w=890, j="LEFT" } }

-- ============================================================
-- STATE
-- ============================================================
EV.selected = nil   -- selected event id

-- ============================================================
-- RSVP HELPERS
-- ============================================================
local function GetEvent(id)
    local db = EnsureDB()
    for _, ev in ipairs(db.events) do
        if ev.id == id then return ev end
    end
    return nil
end

local function RSVP(eventId, status, note)
    local ev = GetEvent(eventId)
    if not ev then return end
    ev.rsvp = ev.rsvp or {}
    local me = MyName()
    for _, r in ipairs(ev.rsvp) do
        if r.name == me then r.status=status; r.note=note or r.note; return end
    end
    table.insert(ev.rsvp, { name=me, status=status, note=note or "" })
end

local function RSVPCount(ev, status)
    if not ev.rsvp then return 0 end
    local n = 0
    for _, r in ipairs(ev.rsvp) do if r.status==status then n=n+1 end end
    return n
end

-- ============================================================
-- REFRESH
-- ============================================================
local function RefreshEventList()
    if not refs.eventContent then return end
    refs.eventRows = refs.eventRows or {}
    local rows = refs.eventRows
    local db   = EnsureDB()

    -- Sort: upcoming first, then by timestamp
    local sorted = {}
    for _, ev in ipairs(db.events) do table.insert(sorted, ev) end
    table.sort(sorted, function(a,b) return (a.ts or 0) < (b.ts or 0) end)

    for i, ev in ipairs(sorted) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.eventContent, i, 772)
            rows[i] = row
        end
        local sel = (EV.selected == ev.id)
        local past = (ev.ts or 0) < time()
        row.bg:SetColorTexture(
            sel and 0.18 or (past and 0.05 or 0.07),
            sel and 0.22 or 0.05, 0.04,
            sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()

        local typeColor = TypeColor(ev.type or "other")
        local typeStr   = typeColor..TypeLabel(ev.type or "other").."|r"
        local yes = RSVPCount(ev, "yes")
        local no  = RSVPCount(ev, "no")
        local yesStr = yes>0 and GMT.Green(tostring(yes)) or GMT.Dim("0")
        local noStr  = no>0  and GMT.Red(tostring(no))    or GMT.Dim("0")
        local nameStr = past and GMT.Dim(ev.name or "?") or GMT.Gold(ev.name or "?")

        FillRow(row, eventCols, {
            sel and GMT.Green(">") or (past and GMT.Dim(".") or GMT.Amber("*")),
            nameStr,
            typeStr,
            past and GMT.Dim(FormatTimestamp(ev.ts)) or FormatTimestamp(ev.ts),
            Countdown(ev.ts),
            yesStr,
            noStr,
            GMT.Dim(GMT.Short(ev.leader or "--")),
        })

        row:SetScript("OnClick", function()
            EV.selected = ev.id
            RefreshEventList()
            RefreshRSVP(ev)
            -- Populate edit fields
            if refs.editName   then refs.editName:SetText(ev.name    or "") end
            if refs.editDate   then refs.editDate:SetText(ev.date    or "") end
            if refs.editTime   then refs.editTime:SetText(ev.evtime  or "") end
            if refs.editType   then refs.editType:SetText(ev.type    or "") end
            if refs.editNote   then refs.editNote:SetText(ev.note    or "") end
            if refs.editLeader then refs.editLeader:SetText(ev.leader or "") end
            if refs.detailTitle then
                refs.detailTitle:SetText(typeColor.."["..TypeLabel(ev.type).."]|r  "..GMT.Gold(ev.name or ""))
            end
        end)
    end
    for i=#sorted+1, #rows do rows[i]:Hide() end
    refs.eventContent:SetHeight(math.max(ROW_H, #sorted * ROW_H))

    if refs.eventCount then
        local upcoming = 0
        for _, ev in ipairs(db.events) do if (ev.ts or 0) >= time() then upcoming=upcoming+1 end end
        refs.eventCount:SetText(GMT.Green(tostring(upcoming)).." "..GMT.Dim("upcoming  |  ")
            ..GMT.Amber(tostring(#db.events)).." "..GMT.Dim("total"))
    end
end

function RefreshRSVP(ev)
    if not refs.rsvpContent or not ev then return end
    refs.rsvpRows = refs.rsvpRows or {}
    local rows = refs.rsvpRows
    local rsvp = ev.rsvp or {}
    for i, r in ipairs(rsvp) do
        local row = rows[i]
        if not row then
            row = MkRow(refs.rsvpContent, i, 400)
            rows[i] = row
        end
        row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        local statusStr = r.status=="yes" and GMT.Green("Going (Y)")
                       or r.status=="no"  and GMT.Red("Decline (N)")
                       or GMT.Amber("Maybe ?")
        FillRow(row, rsvpCols, {
            GMT.Dim(GMT.Short(r.name or "?")),
            statusStr,
            GMT.Clip(r.note or "", 28),
        })
    end
    for i=#rsvp+1, #rows do rows[i]:Hide() end
    refs.rsvpContent:SetHeight(math.max(ROW_H, #rsvp * ROW_H))
end

local function RefreshLog()
    if not refs.logContent then return end
    refs.logRows = refs.logRows or {}
    local log = EnsureDB().log or {}
    for i, entry in ipairs(log) do
        local row = refs.logRows[i]
        if not row then
            row = MkRow(refs.logContent, i, 894)
            refs.logRows[i] = row
        end
        row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        FillRow(row, logCols, { GMT.Dim(date("%H:%M", entry.t)).."  "..(entry.msg or "") })
    end
    for i=#log+1, #refs.logRows do refs.logRows[i]:Hide() end
    refs.logContent:SetHeight(math.max(ROW_H, #log * ROW_H))
end

local function RefreshAll()
    RefreshEventList()
    if refs.logContent then RefreshLog() end
end

-- ============================================================
-- ACTIONS
-- ============================================================
local nextId = 1

local function SaveEvent()
    local db = EnsureDB()
    local name   = refs.editName   and refs.editName:GetText()   or ""
    local dateS  = refs.editDate   and refs.editDate:GetText()   or ""
    local timeS  = refs.editTime   and refs.editTime:GetText()   or "00:00"
    local evType = refs.editType   and refs.editType:GetText()   or "other"
    local note   = refs.editNote   and refs.editNote:GetText()   or ""
    local leader = refs.editLeader and refs.editLeader:GetText() or MyName()

    name = name:match("^%s*(.-)%s*$")
    if name == "" then SetStatus("Enter an event name.", "red"); return end

    local ts, err = ParseDatetime(dateS, timeS)
    if not ts then SetStatus("Date error: "..(err or "invalid"), "red"); return end

    evType = evType:lower():match("^%s*(.-)%s*$")
    if evType == "" then evType = "other" end

    -- Check if editing existing
    if EV.selected then
        for _, ev in ipairs(db.events) do
            if ev.id == EV.selected then
                ev.name=name; ev.ts=ts; ev.date=dateS; ev.evtime=timeS
                ev.type=evType; ev.note=note; ev.leader=leader
                AddLog("Updated event: "..name)
                SetStatus("Event updated: "..name, "green")
                RefreshAll()
                return
            end
        end
    end

    -- New event
    local id = nextId; nextId = nextId + 1
    table.insert(db.events, {
        id=id, name=name, ts=ts, date=dateS, evtime=timeS,
        type=evType, note=note, leader=leader, rsvp={},
    })
    while #db.events > 100 do table.remove(db.events) end
    EV.selected = id
    AddLog("Created event: "..name.." on "..dateS.." "..timeS)
    SetStatus("Event created: "..name, "green")
    RefreshAll()
end

local function DeleteEvent()
    if not EV.selected then SetStatus("Select an event first.", "red"); return end
    local db = EnsureDB()
    local fresh, name = {}, "?"
    for _, ev in ipairs(db.events) do
        if ev.id == EV.selected then name=ev.name else table.insert(fresh, ev) end
    end
    db.events = fresh; EV.selected = nil
    AddLog("Deleted event: "..name)
    SetStatus("Deleted: "..name, "green")
    RefreshAll()
end

local function AnnounceEvent()
    if not EV.selected then SetStatus("Select an event to announce.", "red"); return end
    local ev = GetEvent(EV.selected)
    if not ev then return end
    local chan = IsInRaid() and "RAID" or (GetNumSubgroupMembers()>0 and "PARTY" or "GUILD")
    local yes  = RSVPCount(ev,"yes")
    local msg  = "["..TypeLabel(ev.type).."] "..ev.name.." -- "..FormatTimestamp(ev.ts)
        .."  ("..Countdown(ev.ts)..") -- "..yes.." confirmed"
    -- Strip color codes for chat
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    SendChatMessage(msg, chan)
    AddLog("Announced: "..ev.name)
    SetStatus("Event announced to "..chan, "green")
end

local function SetReminder()
    if not EV.selected then SetStatus("Select an event first.", "red"); return end
    local ev = GetEvent(EV.selected)
    if not ev or not ev.ts then SetStatus("Event has no timestamp.", "red"); return end
    local diff = ev.ts - time()
    if diff <= 0 then SetStatus("Event has already passed.", "red"); return end
    -- 30-minute warning
    local warnAt = diff - 1800
    if warnAt > 0 then
        C_Timer.After(warnAt, function()
            GMT.Print("Reminder: |cffffd700"..ev.name.."|r starts in 30 minutes!")
        end)
    end
    -- At-time alert
    C_Timer.After(math.max(0,diff), function()
        GMT.Print("|cffff4444EVENT NOW:|r |cffffd700"..ev.name.."|r is starting!")
    end)
    AddLog("Reminder set for: "..ev.name)
    SetStatus("Reminder set. Alert 30min before + at event time.", "green")
end

local function DoRSVP(status)
    if not EV.selected then SetStatus("Select an event first.", "red"); return end
    local note = refs.rsvpNote and refs.rsvpNote:GetText() or ""
    RSVP(EV.selected, status, note)
    local ev = GetEvent(EV.selected)
    AddLog("RSVP "..status.." for "..(ev and ev.name or "?"))
    SetStatus("RSVP recorded: "..status, "green")
    RefreshEventList()
    if ev then RefreshRSVP(ev) end
end

-- ============================================================
-- INIT
-- ============================================================
-- Layout (PH=528, margin=8):
--   header:  58
--   events list (full W):   y=-66  h=200
--   bottom row: add/edit(L560) | rsvp(R376): y=-274 h=226
--   activity log removed to give the action area enough room
-- ============================================================
function GMT_Events_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Events")
        if not panel or panel._eventsBuilt then return end
        panel._eventsBuilt = true

        EnsureDB()

        GMT.Header(panel, "Guild Event Planner", 14, -10)
        GMT.Label(panel, "Schedule events  .  RSVP tracking  .  Countdown timers  .  Announcements", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local PAD=8; local GAP=8
        local W  = GMT.PW - PAD*2   -- 944
        local LW = 560; local RW = W - LW - GAP  -- 376

        local evY=-66;  local evH=200
        local botY=evY-evH-GAP      -- -274
        local botH=226

        -- +================================================ 
        -- |  EVENT LIST  (full width)                     |
        -- +================================================ 
        local evBox = Sec(panel, "Guild Calendar", PAD, evY, W, evH)

        refs.eventCount = evBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.eventCount:SetPoint("TOPRIGHT",evBox,"TOPRIGHT",-14,-32)
        refs.eventCount:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.eventCount:SetText(GMT.Dim("No events scheduled"))

        -- List height = evH - 38 = 162
        local _, eventContent = ScrollList(evBox, 8, -30, W-16, evH-38, eventCols)
        refs.eventContent = eventContent

        -- +================================================ 
        -- |  BOT LEFT -- Add / Edit event                  |
        -- +================================================ 
        local addBox = Sec(panel, "Add / Edit Event", PAD, botY, LW, botH)

        -- Row 1: Name + Type
        Lbl(addBox, "Name:", 10, -32)
        refs.editName = Inp(addBox, 54, -30, 240, 20)
        Lbl(addBox, "Type:", 304, -32)
        refs.editType = Inp(addBox, 344, -30, 86, 20)
        Lbl(addBox, "Type of Event", 440, -34)

        -- Row 2: Date + Time + Leader
        Lbl(addBox, "Date:", 10, -60)
        refs.editDate = Inp(addBox, 54, -58, 120, 20)
        Lbl(addBox, "Time:", 196, -60)
        refs.editTime = Inp(addBox, 238, -58, 74, 20)
        Lbl(addBox, "Leader:", 336, -60)
        refs.editLeader = Inp(addBox, 388, -58, 154, 20)

        -- Row 3: Note
        Lbl(addBox, "Note:", 10, -88)
        refs.editNote = Inp(addBox, 54, -86, 488, 20)

        -- Buttons row (cleaned up after helper text removal)
        local saveEvt = GMT.MBtn(addBox, "Save Event",    92, 20)
        local delEvt  = GMT.MBtn(addBox, "Delete",        64, 20)
        local annEvt  = GMT.MBtn(addBox, "Announce",      84, 20)
        local remEvt  = GMT.MBtn(addBox, "Set Reminder", 100, 20)
        local clrEvt  = GMT.MBtn(addBox, "Clear Fields",  94, 20)

        saveEvt:SetPoint("TOPLEFT", addBox, "TOPLEFT", 10, -122)
        delEvt:SetPoint("LEFT",  saveEvt, "RIGHT", 8, 0)
        annEvt:SetPoint("LEFT",  delEvt,  "RIGHT", 8, 0)
        remEvt:SetPoint("TOPLEFT", addBox, "TOPLEFT", 10, -150)
        clrEvt:SetPoint("LEFT",  remEvt,  "RIGHT", 8, 0)

        saveEvt:SetScript("OnClick", SaveEvent)
        delEvt:SetScript("OnClick",  DeleteEvent)
        annEvt:SetScript("OnClick",  AnnounceEvent)
        remEvt:SetScript("OnClick",  SetReminder)
        clrEvt:SetScript("OnClick", function()
            EV.selected = nil
            if refs.editName   then refs.editName:SetText("")   end
            if refs.editDate   then refs.editDate:SetText("")   end
            if refs.editTime   then refs.editTime:SetText("00:00") end
            if refs.editType   then refs.editType:SetText("raid") end
            if refs.editNote   then refs.editNote:SetText("")   end
            if refs.editLeader then refs.editLeader:SetText(MyName()) end
            RefreshEventList()
        end)

        -- +================================================ 
        -- |  BOT RIGHT -- RSVP panel                       |
        -- +================================================ 
        local rsvpBox = Sec(panel, "RSVP", PAD+LW+GAP, botY, RW, botH)

        refs.detailTitle = rsvpBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.detailTitle:SetPoint("TOPLEFT",rsvpBox,"TOPLEFT",10,-32)
        refs.detailTitle:SetTextColor(GMT.U(GMT.C.txtBody))
        refs.detailTitle:SetText(GMT.Dim("Select an event to RSVP"))

        -- RSVP list
        local _, rsvpContent = ScrollList(rsvpBox, 8, -48, RW-16, 76, rsvpCols)
        refs.rsvpContent = rsvpContent

        -- RSVP note + buttons
        Lbl(rsvpBox, "Note:", 10, -130)
        refs.rsvpNote = Inp(rsvpBox, 52, -128, RW-72, 18)

        local yesBtn = GMT.MBtn(rsvpBox, "Going (Y)",   82, 20)
        local mayBtn = GMT.MBtn(rsvpBox, "Maybe ?",     72, 20)
        local noBtn  = GMT.MBtn(rsvpBox, "Decline (N)", 86, 20)

        yesBtn:SetPoint("TOPLEFT", rsvpBox, "TOPLEFT", 8, -156)
        mayBtn:SetPoint("LEFT", yesBtn, "RIGHT", 6, 0)
        noBtn:SetPoint("LEFT",  mayBtn, "RIGHT", 6, 0)

        yesBtn:SetScript("OnClick", function() DoRSVP("yes")   end)
        mayBtn:SetScript("OnClick", function() DoRSVP("maybe") end)
        noBtn:SetScript("OnClick",  function() DoRSVP("no")    end)

        refs.logContent = nil

        --    Status bar
        refs.status = panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        refs.status:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",12,10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Event Planner ready.  Use YYYY-MM-DD and HH:MM for dates.")

        panel:SetScript("OnShow", RefreshAll)

        -- Seed nextId from existing events
        local db = EnsureDB()
        for _, ev in ipairs(db.events) do
            if (ev.id or 0) >= nextId then nextId = ev.id + 1 end
        end

        RefreshAll()
    end)
    if not ok and GMT and GMT.Err then
        GMT.Err("Events init failed: "..tostring(err))
    end
end
