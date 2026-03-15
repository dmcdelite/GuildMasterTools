-- ============================================================
-- GuildMaster Tools  |  Modules/GuildSync.lua  |  v3.3.0
-- Phase 10 -- Guild Sync Network
--
-- Addon presence detection  .  Guild-wide data broadcasting
-- Shared raid readiness      .  Shared recruit scores
-- Shared supply status       .  Sync history log
-- ============================================================
local _, GMT = ...

GMT.GS = GMT.GS or {}
local GS = GMT.GS

local refs  = {}
local ROW_H = 20

-- ============================================================
-- COMM MESSAGE TYPES
-- All messages use the existing GMT comm system (prefix GMT2)
-- Payload is always a pipe-delimited string to avoid JSON overhead
-- ============================================================
local MSG = {
    PING      = "GSPNG",   -- presence beacon: version
    PONG      = "GSPOG",   -- presence reply:  version
    SYNC_REQ  = "GSREQ",   -- request a data packet
    RAID_DATA = "GSRDT",   -- broadcast raid readiness summary
    SUP_DATA  = "GSSUP",   -- broadcast supply shortage summary
    REC_DATA  = "GSREC",   -- broadcast top recruit scores
    PERF_DATA = "GSPRF",   -- broadcast raid perf baseline
    CHAT      = "GSCHAT",  -- in-addon guild chat message
    CFG_REQ   = "GSCFGQ",
    CFG_PUSH  = "GSCFGP",
}

-- ============================================================
-- STATE
-- ============================================================
GS.members   = GS.members   or {}  -- [name] = { ver, lastSeen, online }
GS.syncLog   = GS.syncLog   or {}  -- chronological sync event log
GS.chatLog   = GS.chatLog   or {}  -- in-addon chat messages
GS.syncEnabled = GS.syncEnabled or false
GS.selectedMember = nil

-- ============================================================
-- DB
-- ============================================================
local function EnsureDB()
    GMT.DB.sync = GMT.DB.sync or {}
    local db = GMT.DB.sync
    db.enabled     = db.enabled     ~= false   -- default true once user enables
    db.autoOnLogin = db.autoOnLogin or false
    db.sharedRaid  = db.sharedRaid  or {}
    db.sharedSupply= db.sharedSupply or {}
    db.sharedRec   = db.sharedRec   or {}
    db.sharedPerf  = db.sharedPerf  or {}
    db.log         = db.log         or {}
    return db
end

local function AddLog(msg, kind)
    local entry = { t=time(), msg=msg, kind=kind or "info" }
    table.insert(GS.syncLog, 1, entry)
    while #GS.syncLog > 80 do table.remove(GS.syncLog) end
    -- persist short version
    local db = EnsureDB()
    table.insert(db.log, 1, { t=entry.t, msg=msg })
    while #db.log > 60 do table.remove(db.log) end
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
-- SERIALISATION HELPERS
-- Simple pipe-delimited, no binary -- safe for addon messages
-- ============================================================
local function Encode(t)
    local parts = {}
    for _, v in ipairs(t) do
        -- Wrap gsub in () to discard the count return value.
        -- Without (), table.insert(parts, str, count) treats count as position.
        local safe = (tostring(v or ""):gsub("|", "_"))
        parts[#parts + 1] = safe
    end
    return table.concat(parts, "|")
end

local function Decode(s)
    local parts = {}
    for p in (s.."|"):gmatch("([^|]*)|") do
        table.insert(parts, p)
    end
    return parts
end

local function MyName()
    return UnitName("player") or "Unknown"
end

local function LayerInfo()
    local zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or "?"
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
    local inInstance, instanceType = IsInInstance()
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local wm = (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) and "WM" or "NW"
    local layer = string.format('%s M%s I%s D%s %s', GMT.Clip(zone, 14), tostring(mapID or 0), tostring(instanceID or 0), tostring(difficultyID or 0), wm)
    return layer
end

local function CanSyncConfigFrom(sender)
    if not sender or not IsInGuild() then return false end
    local count = GetNumGuildMembers() or 0
    for i=1,count do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if GMT.Short(name) == GMT.Short(sender) then
            return (tonumber(rankIndex) or 99) <= 1
        end
    end
    return false
end

-- ============================================================
-- COMM HANDLERS  -- registered once on init
-- ============================================================
local function OnPing(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    local ver   = parts[1] or "?"
    GS.members[sender] = { ver=ver, lastSeen=time(), online=true, layer=parts[2] or "--" }
    AddLog("Ping from "..sender.." (v"..ver..")", "ping")
    -- Reply with pong
    GMT.SendComm(MSG.PONG, Encode({ GMT.VERSION, LayerInfo() }), "WHISPER", sender)
    if refs.RefreshMembers then refs.RefreshMembers() end
end

local function OnPong(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    local ver   = parts[1] or "?"
    GS.members[sender] = { ver=ver, lastSeen=time(), online=true, layer=parts[2] or "--" }
    AddLog("Pong from "..sender.." (v"..ver..")", "pong")
    if refs.RefreshMembers then refs.RefreshMembers() end
end

local function OnRaidData(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    -- format: ready|total|tank_avg|heal_avg|dps_avg|timestamp
    local db = EnsureDB()
    db.sharedRaid[sender] = {
        ready   = tonumber(parts[1]) or 0,
        total   = tonumber(parts[2]) or 0,
        tankAvg = tonumber(parts[3]) or 0,
        healAvg = tonumber(parts[4]) or 0,
        dpsAvg  = tonumber(parts[5]) or 0,
        t       = tonumber(parts[6]) or time(),
        sender  = sender,
    }
    AddLog("Raid data from "..sender..": "..
        (parts[1] or "?").."/".. (parts[2] or "?").." ready", "raid")
    if refs.RefreshShared then refs.RefreshShared() end
end

local function OnSupplyData(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    -- format: shortages|stocked|buckets|timestamp
    local db = EnsureDB()
    db.sharedSupply[sender] = {
        shortages = tonumber(parts[1]) or 0,
        stocked   = tonumber(parts[2]) or 0,
        buckets   = tonumber(parts[3]) or 0,
        t         = tonumber(parts[4]) or time(),
        sender    = sender,
    }
    AddLog("Supply data from "..sender..": "..
        (parts[1] or "?").." shortage(s)", "supply")
    if refs.RefreshShared then refs.RefreshShared() end
end

local function OnRecruitData(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    -- format: count|top_name|top_score|timestamp
    local db = EnsureDB()
    db.sharedRec[sender] = {
        count    = tonumber(parts[1]) or 0,
        topName  = parts[2] or "--",
        topScore = tonumber(parts[3]) or 0,
        t        = tonumber(parts[4]) or time(),
        sender   = sender,
    }
    AddLog("Recruit data from "..sender..": "..
        (parts[1] or "0").." recruit(s)", "rec")
    if refs.RefreshShared then refs.RefreshShared() end
end

local function OnPerfData(payload, sender)
    if sender == MyName() then return end
    local parts = Decode(payload)
    -- format: tank_base|heal_base|dps_base|roster_size|timestamp
    local db = EnsureDB()
    db.sharedPerf[sender] = {
        tankBase = tonumber(parts[1]) or 0,
        healBase = tonumber(parts[2]) or 0,
        dpsBase  = tonumber(parts[3]) or 0,
        rosterSz = tonumber(parts[4]) or 0,
        t        = tonumber(parts[5]) or time(),
        sender   = sender,
    }
    AddLog("Perf baseline from "..sender, "perf")
    if refs.RefreshShared then refs.RefreshShared() end
end

local function OnChat(payload, sender)
    if sender == MyName() then return end
    table.insert(GS.chatLog, 1, { t=time(), sender=sender, msg=payload })
    while #GS.chatLog > 40 do table.remove(GS.chatLog) end
    AddLog("[Chat] "..sender..": "..GMT.Clip(payload, 40), "chat")
    if refs.RefreshChat then refs.RefreshChat() end
end

local function OnSyncReq(payload, sender)
    if sender == MyName() then return end
    -- Someone requested our data -- broadcast everything
    AddLog("Sync request from "..sender, "req")
    C_Timer.After(0.5, function()
        GMT.SendComm(MSG.PING, Encode({ GMT.VERSION, LayerInfo() }), "GUILD")
    end)
end

local function EncodeConfig()
    local s = GMT.DB.settings or {}
    local acc = s.access or { whitelist = {}, tabs = {} }
    local wl = {}
    for name in pairs(acc.whitelist or {}) do wl[#wl+1] = name end
    table.sort(wl)
    local tabs = {}
    for k,v in pairs(acc.tabs or {}) do tabs[#tabs+1] = k .. '=' .. tostring(v) end
    table.sort(tabs)
    return Encode({ tostring(GMT.DB.configVersion or GMT.CONFIG_VERSION or 1), table.concat(wl, ','), table.concat(tabs, ',') })
end

local function ApplyConfig(payload, sender)
    if not CanSyncConfigFrom(sender) then return end
    local parts = Decode(payload)
    local ver = tonumber(parts[1] or 0) or 0
    if ver <= (GMT.DB.configVersion or 0) then return end
    GMT.DB.settings.access = GMT.DB.settings.access or { whitelist = {}, tabs = {} }
    local acc = GMT.DB.settings.access
    acc.whitelist = {}
    for name in tostring(parts[2] or ''):gmatch('([^,]+)') do acc.whitelist[GMT.Short(name)] = true end
    acc.tabs = acc.tabs or {}
    for pair in tostring(parts[3] or ''):gmatch('([^,]+)') do
        local k,v = pair:match('^(.-)=(%d+)$')
        if k then acc.tabs[k] = tonumber(v) end
    end
    GMT.DB.configVersion = ver
    GMT.NormalizeWhitelist()
    AddLog('Applied officer config v'..ver..' from '..sender, 'cfg')
    SetStatus('Config sync applied from '..sender..'.', 'green')
end

local function OnConfigReq(_, sender)
    if GMT.IsOfficer and GMT.IsOfficer() then
        GMT.SendComm(MSG.CFG_PUSH, EncodeConfig(), 'WHISPER', sender)
    end
end

local function OnConfigPush(payload, sender)
    ApplyConfig(payload, sender)
    if refs.RefreshMembers then refs.RefreshMembers() end
end

-- ============================================================
-- BROADCAST FUNCTIONS
-- ============================================================
local function BroadcastPresence()
    GMT.SendComm(MSG.PING, Encode({ GMT.VERSION, LayerInfo() }), "GUILD")
    AddLog("Broadcasted presence beacon", "ping")
    SetStatus("Presence beacon sent to guild.", "green")
end

local function BroadcastRaidData()
    local ready, total = 0, 0
    local tankAvg, healAvg, dpsAvg = 0, 0, 0
    if GMT.RP and GMT.RP.rows then
        total = #GMT.RP.rows
        local db = (GMT.DB.raidPerf and GMT.DB.raidPerf.thresholds) or { minScore=60, minDur=75 }
        local sums = { TANK={n=0,s=0}, HEALER={n=0,s=0}, DAMAGER={n=0,s=0} }
        if GMT.PF and GMT.PF.rosterScores then
            for _, e in ipairs(GMT.PF.rosterScores) do
                local role = e.role or "DAMAGER"
                if role == "-" or role == "" then role = "DAMAGER" end
                sums[role].n = sums[role].n + 1
                sums[role].s = sums[role].s + (e.score or 0)
                if (e.score or 0) >= (db.minScore or 60) then ready = ready + 1 end
            end
        end
        if sums.TANK.n    > 0 then tankAvg = math.floor(sums.TANK.s    / sums.TANK.n)    end
        if sums.HEALER.n  > 0 then healAvg = math.floor(sums.HEALER.s  / sums.HEALER.n)  end
        if sums.DAMAGER.n > 0 then dpsAvg  = math.floor(sums.DAMAGER.s / sums.DAMAGER.n) end
    end
    GMT.SendComm(MSG.RAID_DATA,
        Encode({ ready, total, tankAvg, healAvg, dpsAvg, time() }), "GUILD")
    AddLog("Broadcast raid data: "..ready.."/"..total.." ready", "raid")
    SetStatus("Raid readiness broadcast sent.", "green")
end

local function BroadcastSupplyData()
    local shortages, stocked, buckets = 0, 0, 0
    if GMT.LX and GMT.LX.supplies then
        buckets = #GMT.LX.supplies
        for _, e in ipairs(GMT.LX.supplies) do
            local need = tonumber(e.need or 0) or 0
            if need > 0 then
                if e.total >= need then stocked = stocked + 1
                else shortages = shortages + 1 end
            end
        end
    end
    GMT.SendComm(MSG.SUP_DATA,
        Encode({ shortages, stocked, buckets, time() }), "GUILD")
    AddLog("Broadcast supply data: "..shortages.." shortage(s)", "supply")
    SetStatus("Supply status broadcast sent.", "green")
end

local function BroadcastRecruitData()
    local db = GMT.DB.raidPerf
    local recs = (db and db.recruits) or {}
    local topName, topScore = "--", 0
    for _, r in ipairs(recs) do
        if (r.score or 0) > topScore then
            topScore = r.score or 0
            topName  = r.name  or "--"
        end
    end
    GMT.SendComm(MSG.REC_DATA,
        Encode({ #recs, topName, topScore, time() }), "GUILD")
    AddLog("Broadcast recruit data: "..#recs.." recruit(s)", "rec")
    SetStatus("Recruit data broadcast sent.", "green")
end

local function BroadcastPerfData()
    local bl = (GMT.DB.raidPerf and GMT.DB.raidPerf.baseline) or {}
    local rosterSz = (GMT.RP and GMT.RP.rows and #GMT.RP.rows) or 0
    GMT.SendComm(MSG.PERF_DATA,
        Encode({ bl.TANK or 0, bl.HEALER or 0, bl.DAMAGER or 0, rosterSz, time() }), "GUILD")
    AddLog("Broadcast perf baselines", "perf")
    SetStatus("Performance baselines broadcast sent.", "green")
end

function GS.RequestAllSync()
    GMT.SendComm(MSG.SYNC_REQ, "", "GUILD")
    AddLog("Sync request broadcast to guild")
    if GMT.IsOfficer and GMT.IsOfficer() then GMT.SendComm(MSG.CFG_REQ, "", "GUILD") end
end

local function BroadcastAll()
    BroadcastPresence()
    C_Timer.After(0.3, BroadcastRaidData)
    C_Timer.After(0.6, BroadcastSupplyData)
    C_Timer.After(0.9, BroadcastRecruitData)
    C_Timer.After(1.2, BroadcastPerfData)
    SetStatus("Full sync broadcast sent (5 packets).", "green")
    AddLog("Full sync broadcast initiated")
end

local function RequestSync(targetName)
    if not targetName or targetName == "" then
        -- Broadcast to whole guild
        GMT.SendComm(MSG.SYNC_REQ, "", "GUILD")
        AddLog("Sync request broadcast to guild")
        SetStatus("Sync request sent to guild.", "green")
    else
        GMT.SendComm(MSG.SYNC_REQ, "", "WHISPER", targetName)
        AddLog("Sync request sent to "..targetName)
        SetStatus("Sync request sent to "..targetName..".", "green")
    end
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
    eb:SetAutoFocus(false); eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    return eb
end

local function ScrollList(parent, x, y, w, h, cols)
    local fr = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    fr:SetSize(w, h); fr:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
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
    local hb = hdr:CreateTexture(nil,"BACKGROUND"); hb:SetAllPoints()
    hb:SetColorTexture(GMT.U(GMT.C.cardHead))
    local cx = 4
    for _, col in ipairs(cols) do
        local fs = hdr:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        fs:SetPoint("LEFT",hdr,"LEFT",cx,0); fs:SetWidth(col.w)
        fs:SetJustifyH(col.j or "LEFT")
        fs:SetTextColor(GMT.U(GMT.C.txtTitle)); fs:SetText(col.label)
        cx = cx + col.w
    end
    local sf = CreateFrame("ScrollFrame", nil, fr, "UIPanelScrollFrameTemplate")
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
    local x = 4
    for i, col in ipairs(cols) do
        local fs = row.cells[i]
        if not fs then
            fs = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.cells[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT",row,"LEFT",x,0)
        fs:SetWidth(col.w); fs:SetJustifyH(col.j or "LEFT")
        fs:SetText(vals[i] or "")
        x = x + col.w
    end
end

local function FormatAgo(ts)
    if not ts or ts <= 0 then return GMT.Dim("Never") end
    local d = time() - ts
    if d < 60    then return GMT.Green("Now") end
    if d < 3600  then return tostring(math.floor(d/60)).."m" end
    if d < 86400 then return tostring(math.floor(d/3600)).."h" end
    return tostring(math.floor(d/86400)).."d"
end

-- ============================================================
-- COLUMN DEFINITIONS
-- ============================================================
-- Member roster: LW=560, content ~536
local memberCols = {
    { label="",        w=16,  j="CENTER" },  -- LED
    { label="Name",    w=130, j="LEFT"   },
    { label="Version", w=70,  j="LEFT"   },
    { label="Seen",    w=56,  j="LEFT"   },
    { label="Raid",    w=68,  j="LEFT"   },  -- raid ready status
    { label="Supply",  w=76,  j="LEFT"   },  -- supply status
    { label="Recruits",w=60,  j="CENTER" },
    { label="Perf",    w=60,  j="LEFT"   },
}  -- total 536

-- Sync log: RW=376, content ~346
local logCols = {
    { label="",       w=14,  j="CENTER" },
    { label="Time",   w=46,  j="LEFT"   },
    { label="Event",  w=286, j="LEFT"   },
}  -- total 346

-- Chat: same width
local chatCols = {
    { label="From",    w=90,  j="LEFT"   },
    { label="Message", w=256, j="LEFT"   },
}  -- total 346

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
local function RefreshMembers()
    if not refs.memberContent then return end
    refs.memberRows = refs.memberRows or {}
    local rows = refs.memberRows
    local db   = EnsureDB()

    -- Build sorted list from GS.members
    local list = {}
    for name, data in pairs(GS.members) do
        table.insert(list, { name=name, data=data })
    end
    table.sort(list, function(a,b) return (a.data.lastSeen or 0) > (b.data.lastSeen or 0) end)

    -- Get shared data for each member
    for i, entry in ipairs(list) do
        local name = entry.name
        local data = entry.data
        local row  = rows[i]
        if not row then
            row = MkRow(refs.memberContent, i, 536)
            rows[i] = row
        end
        local sel = (GS.selectedMember == name)
        row.bg:SetColorTexture(
            sel and 0.18 or 0.07,
            sel and 0.22 or 0.05, 0.04,
            sel and 0.75 or (i%2==0 and 0.28 or 0.10))
        row:Show()

        -- Online LED color
        local recent = (time() - (data.lastSeen or 0)) < 300  -- seen in last 5 min
        local ledColor = recent and "|cff19f580*|r" or "|cff444440*|r"

        -- Raid ready summary
        local raidStr = GMT.Dim("--")
        local rd = db.sharedRaid[name]
        if rd then
            local pct = rd.total > 0 and math.floor(rd.ready/rd.total*100) or 0
            raidStr = (pct >= 80 and GMT.Green or pct >= 60 and GMT.Amber or GMT.Red)(rd.ready.."/"..rd.total)
        end

        -- Supply summary
        local supStr = GMT.Dim("--")
        local sd = db.sharedSupply[name]
        if sd then
            supStr = sd.shortages == 0 and GMT.Green("Stocked") or GMT.Red(sd.shortages.." short")
        end

        -- Recruit count
        local recStr = GMT.Dim("--")
        local rcd = db.sharedRec[name]
        if rcd then
            recStr = GMT.Amber(tostring(rcd.count))
        end

        -- Perf baseline (DPS avg as representative)
        local perfStr = GMT.Dim("--")
        local pd = db.sharedPerf[name]
        if pd then
            local avg = math.floor(((pd.tankBase or 0)+(pd.healBase or 0)+(pd.dpsBase or 0)) / 3)
            perfStr = avg > 0 and (avg >= 70 and GMT.Green(tostring(avg)) or GMT.Amber(tostring(avg))) or GMT.Dim("--")
        end

        FillRow(row, memberCols, {
            ledColor,
            "|cffbbbbbb"..name.."|r",
            GMT.Dim(data.ver or "?"),
            FormatAgo(data.lastSeen),
            raidStr,
            supStr,
            recStr,
            perfStr,
        })

        row:SetScript("OnClick", function()
            GS.selectedMember = name
            RefreshMembers()
            -- Show detailed data in the right column
            if refs.detailBox then
                local lines = {}
                table.insert(lines, GMT.Gold(name).."  "..GMT.Dim("v"..(data.ver or "?")))
                table.insert(lines, GMT.Dim("Last seen: ")..FormatAgo(data.lastSeen))
                if data.layer then table.insert(lines, GMT.Dim("Layer: ")..data.layer) end
                if rd then
                    table.insert(lines, GMT.Dim("Raid: ")..rd.ready.."/"..rd.total.." ready  "..
                        GMT.Dim("T:")..rd.tankAvg.." H:"..rd.healAvg.." D:"..rd.dpsAvg)
                end
                if sd then
                    table.insert(lines, GMT.Dim("Supply: ")..sd.stocked..GMT.Dim("/")..sd.buckets..
                        " stocked  "..sd.shortages.." shortage(s)")
                end
                if rcd then
                    table.insert(lines, GMT.Dim("Recruits: ")..rcd.count..
                        "  Top: "..(rcd.topName or "--").." ("..rcd.topScore..")")
                end
                if pd then
                    table.insert(lines, GMT.Dim("Perf: T:")..pd.tankBase..
                        GMT.Dim(" H:")..pd.healBase..GMT.Dim(" D:")..pd.dpsBase..
                        GMT.Dim("  ("..pd.rosterSz.." players)"))
                end
                refs.detailBox:SetText(table.concat(lines, "\n"))
            end
            -- Populate whisper target
            if refs.whisperTarget then refs.whisperTarget:SetText(name) end
        end)
    end

    for i = #list+1, #rows do rows[i]:Hide() end
    refs.memberContent:SetHeight(math.max(ROW_H, #list * ROW_H))

    if refs.memberCount then
        refs.memberCount:SetText(
            GMT.Green(tostring(#list)).." "..GMT.Dim("addon member(s) detected"))
    end
end
refs.RefreshMembers = RefreshMembers

local function RefreshSyncLog()
    if not refs.logContent then return end
    refs.logRows = refs.logRows or {}
    for i, entry in ipairs(GS.syncLog) do
        local row = refs.logRows[i]
        if not row then
            row = MkRow(refs.logContent, i, 346)
            refs.logRows[i] = row
        end
        row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        -- LED color by kind
        local led = GMT.Dim(".")
        if     entry.kind == "raid"   then led = GMT.Amber(">")
        elseif entry.kind == "supply" then led = GMT.Green(">")
        elseif entry.kind == "rec"    then led = "|cff66aaff>|r"
        elseif entry.kind == "chat"   then led = GMT.Gold(">")
        elseif entry.kind == "ping" or entry.kind == "pong" then led = GMT.Dim("o")
        end
        FillRow(row, logCols, {
            led,
            GMT.Dim(date("%H:%M", entry.t)),
            GMT.Clip(entry.msg or "", 48),
        })
    end
    for i = #GS.syncLog+1, #refs.logRows do refs.logRows[i]:Hide() end
    refs.logContent:SetHeight(math.max(ROW_H, #GS.syncLog * ROW_H))
end

local function RefreshChat()
    if not refs.chatContent then return end
    refs.chatRows = refs.chatRows or {}
    for i, entry in ipairs(GS.chatLog) do
        local row = refs.chatRows[i]
        if not row then
            row = MkRow(refs.chatContent, i, 346)
            refs.chatRows[i] = row
        end
        row.bg:SetColorTexture(0.07,0.05,0.04, i%2==0 and 0.28 or 0.10)
        row:Show()
        FillRow(row, chatCols, {
            GMT.Amber(GMT.Short(entry.sender or "?")),
            GMT.Clip(entry.msg or "", 42),
        })
    end
    for i = #GS.chatLog+1, #refs.chatRows do refs.chatRows[i]:Hide() end
    refs.chatContent:SetHeight(math.max(ROW_H, #GS.chatLog * ROW_H))
end

local function RefreshShared()
    RefreshMembers()
    RefreshSyncLog()
end
refs.RefreshShared = RefreshShared
refs.RefreshChat   = RefreshChat

local function RefreshAll()
    RefreshMembers()
    RefreshSyncLog()
    RefreshChat()
end

-- ============================================================
-- REGISTER COMM HANDLERS
-- ============================================================
local function RegisterHandlers()
    GMT.RegComm(MSG.PING,      OnPing)
    GMT.RegComm(MSG.PONG,      OnPong)
    GMT.RegComm(MSG.RAID_DATA, OnRaidData)
    GMT.RegComm(MSG.SUP_DATA,  OnSupplyData)
    GMT.RegComm(MSG.REC_DATA,  OnRecruitData)
    GMT.RegComm(MSG.PERF_DATA, OnPerfData)
    GMT.RegComm(MSG.CHAT,      OnChat)
    GMT.RegComm(MSG.CFG_REQ,   OnConfigReq)
    GMT.RegComm(MSG.CFG_PUSH,  OnConfigPush)
    GMT.RegComm(MSG.SYNC_REQ,  OnSyncReq)
    GMT.Debug("GuildSync: comm handlers registered")
end

-- ============================================================
-- INIT
-- ============================================================
-- Layout (PH=528):
--   header+label+hline: 58px
--   Row 1 -- Controls (full W):           y=-66  h=46
--   Row 2 -- Members L(560) | Right R(376): y=-120 h=350
--     Right column breakdown:
--       Sync log label+list: 30+110=140
--       divider: 8
--       Chat label+list: 30+90=120
--       chat input row: 28
--       target row: 28
--       broadcast btns: 28
--       = 352 -- fits in 350 with tiny trim
--   Status bar: 12px
--   Total: 58+8+46+8+350+12 = 482  (46px spare used in members row)
-- ============================================================
function GMT_GuildSync_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Guild Sync")
        if not panel or panel._syncBuilt then return end
        panel._syncBuilt = true

        EnsureDB()
        RegisterHandlers()

        GMT.Header(panel, "Guild Sync Network", 14, -10)
        GMT.Label(panel,
            "Addon detection  .  Data broadcasting  .  Guild-wide intelligence  .  Officer chat",
            16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local PAD=8; local GAP=8
        local W  = GMT.PW - PAD*2   -- 944
        local LW = 560; local RW = W - LW - GAP  -- 376

        local r1Y=-66;  local r1H=56
        local r2Y=r1Y-r1H-GAP    -- -130
        local r2H=350

        -- +================================================ 
        -- |  ROW 1 -- Controls bar (full width)            |
        -- +================================================ 
        local ctrlBox = Sec(panel, "Sync Controls", PAD, r1Y, W, r1H)

        refs.memberCount = ctrlBox:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        refs.memberCount:SetPoint("TOPLEFT", ctrlBox, "TOPLEFT", 14, -30)
        refs.memberCount:SetTextColor(GMT.U(GMT.C.txtBody))
        refs.memberCount:SetText(GMT.Dim("No GMT members detected yet -- click Ping Guild"))

        -- LED + buttons RIGHT side of controls, LEFT-chained from right
        refs.syncLED = GMT.LED(ctrlBox, W-296, -32, 8, GMT.C.grey)

        local pingBtn      = GMT.MBtn(ctrlBox, "Ping Guild",    100, 22)
        local broadcastBtn = GMT.MBtn(ctrlBox, "Broadcast All", 120, 22)
        local reqBtn       = GMT.MBtn(ctrlBox, "Request Sync",  110, 22)

        pingBtn:SetPoint("TOPRIGHT",     ctrlBox, "TOPRIGHT",   -8, -26)
        broadcastBtn:SetPoint("RIGHT",   pingBtn, "LEFT",       -6,  0)
        reqBtn:SetPoint("RIGHT",         broadcastBtn, "LEFT",  -6,  0)

        pingBtn:SetScript("OnClick", function()
            BroadcastPresence()
            if refs.syncLED then refs.syncLED:SetVertexColor(GMT.U(GMT.C.green)) end
        end)
        broadcastBtn:SetScript("OnClick", BroadcastAll)
        reqBtn:SetScript("OnClick", function()
            local target = refs.whisperTarget and refs.whisperTarget:GetText() or ""
            target = target:match("^%s*(.-)%s*$")
            RequestSync(target ~= "" and target or nil)
        end)

        -- +================================================ 
        -- |  ROW 2A -- Member Roster (left 560px)          |
        -- +================================================ 
        local memberBox = Sec(panel, "GMT Members  --  Live Intel", PAD, r2Y, LW, r2H)

        -- Count badge top-right of header
        refs.memberCount2 = memberBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.memberCount2:SetPoint("TOPRIGHT", memberBox, "TOPRIGHT", -14, -32)
        refs.memberCount2:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.memberCount2:SetText(GMT.Dim("0 members"))

        -- Member list -- leaves 60px at bottom for detail text
        -- list h = r2H - 30 - 60 = 260
        local _, memberContent = ScrollList(memberBox, 8, -30, LW-16, r2H-96, memberCols)
        refs.memberContent = memberContent

        -- Detail panel -- last ~56px inside section
        local detailBg = memberBox:CreateTexture(nil,"BACKGROUND")
        detailBg:SetPoint("BOTTOMLEFT",  memberBox, "BOTTOMLEFT",   4, 4)
        detailBg:SetPoint("BOTTOMRIGHT", memberBox, "BOTTOMRIGHT", -4, 4)
        detailBg:SetHeight(52)
        detailBg:SetColorTexture(0.10, 0.07, 0.04, 0.85)

        refs.detailBox = memberBox:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        refs.detailBox:SetPoint("BOTTOMLEFT", memberBox, "BOTTOMLEFT", 10, 12)
        refs.detailBox:SetWidth(LW - 20)
        refs.detailBox:SetJustifyH("LEFT")
        refs.detailBox:SetTextColor(GMT.U(GMT.C.txtBody))
        refs.detailBox:SetText(GMT.Dim("Click a member row to view their synced data"))

        -- +================================================ 
        -- |  ROW 2B -- Right column (376px)                |
        -- |  Sync log | Officer chat | Target | Buttons   |
        -- +================================================ 
        -- Explicit Y budget for r2H=350, header=30, usable=320:
        --   Log label:   y=-32  (14px)
        --   Log list:    y=-48  h=106    ends -154
        --   Divider:     y=-158 (1px)
        --   Chat label:  y=-164 (14px)
        --   Chat list:   y=-180 h=88     ends -268
        --   Chat input:  y=-274 h=20     ends -294
        --   Target row:  y=-300 h=20     ends -320
        --   Bcast btns:  BOTTOMLEFT+8  fits at y -322
        --   Total used: 322   320 usable   trim log by 4 and chat by 2 = OK

        local rightBox = Sec(panel, "Sync Log  &  Officer Chat", PAD+LW+GAP, r2Y, RW, r2H)
        local RU = RW - 16  -- 360 usable inside padding

        -- Sync log
        Lbl(rightBox, "Sync Events:", 10, -32)
        local _, logContent = ScrollList(rightBox, 8, -48, RU, 104, logCols)
        refs.logContent = logContent

        -- Divider
        local div = rightBox:CreateTexture(nil,"ARTWORK")
        div:SetPoint("TOPLEFT",  rightBox, "TOPLEFT",   4, -158)
        div:SetPoint("TOPRIGHT", rightBox, "TOPRIGHT", -4, -158)
        div:SetHeight(1)
        div:SetColorTexture(GMT.U(GMT.C.copper))
        div:SetAlpha(0.45)

        -- Officer chat
        Lbl(rightBox, "Officer Chat  (addon-only):", 10, -164)
        local _, chatContent = ScrollList(rightBox, 8, -180, RU, 82, chatCols)
        refs.chatContent = chatContent

        -- Chat input row
        refs.chatInput = Inp(rightBox, 8, -272, RU-66, 20)
        local sendChat = GMT.MBtn(rightBox, "Send", 60, 20)
        sendChat:SetPoint("LEFT", refs.chatInput, "RIGHT", 4, 0)
        sendChat:SetScript("OnClick", function()
            local msg = refs.chatInput and refs.chatInput:GetText() or ""
            msg = msg:match("^%s*(.-)%s*$")
            if msg == "" then return end
            GMT.SendComm(MSG.CHAT, msg, "GUILD")
            table.insert(GS.chatLog, 1, { t=time(), sender=MyName(), msg=msg })
            while #GS.chatLog > 40 do table.remove(GS.chatLog) end
            AddLog("[Chat] "..MyName()..": "..GMT.Clip(msg, 40), "chat")
            refs.chatInput:SetText("")
            RefreshChat()
            RefreshSyncLog()
        end)

        -- Target row
        Lbl(rightBox, "Target:", 8, -294)
        refs.whisperTarget = Inp(rightBox, 56, -292, 104, 20)
        local syncTarget = GMT.MBtn(rightBox, "Sync Target", 94, 20)
        syncTarget:SetPoint("LEFT", refs.whisperTarget, "RIGHT", 4, 0)
        syncTarget:SetScript("OnClick", function()
            local target = refs.whisperTarget and refs.whisperTarget:GetText() or ""
            target = target:match("^%s*(.-)%s*$")
            if target == "" then SetStatus("Enter a player name in Target first.", "red"); return end
            GMT.SendComm(MSG.PING, Encode({ GMT.VERSION }), "WHISPER", target)
            AddLog("Individual sync to "..target)
            SetStatus("Sync sent to "..target..".", "green")
        end)

        -- Individual broadcast buttons -- BOTTOMLEFT-chained, 4 equal buttons
        -- 4   82 + 3   6 = 346   RU=360 (Y)
        local bDefs = {
            { label="Raid",     fn=BroadcastRaidData    },
            { label="Supply",   fn=BroadcastSupplyData  },
            { label="Recruits", fn=BroadcastRecruitData },
            { label="Perf",     fn=BroadcastPerfData    },
        }
        for i, bd in ipairs(bDefs) do
            local btn = GMT.MBtn(rightBox, bd.label, 82, 22)
            btn:SetPoint("BOTTOMLEFT", rightBox, "BOTTOMLEFT", 8+(i-1)*86, 8)
            btn:SetScript("OnClick", bd.fn)
        end

        --    Status bar                                     
        refs.status = panel:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Guild Sync ready.  Click Ping Guild to detect addon members.")

        --    Panel events                                   
        panel:SetScript("OnShow", function()
            RefreshAll()
            -- Sync member count badges
            local n = 0; for _ in pairs(GS.members) do n=n+1 end
            local txt = n > 0 and (GMT.Green(tostring(n)).." "..GMT.Dim("GMT member(s) detected"))
                               or GMT.Dim("No GMT members detected yet -- click Ping Guild")
            if refs.memberCount  then refs.memberCount:SetText(txt) end
            if refs.memberCount2 then refs.memberCount2:SetText(GMT.Amber(tostring(n)).." "..GMT.Dim("members")) end
        end)

        --    Guild event hooks                              
        local evF = CreateFrame("Frame")
        evF:RegisterEvent("PLAYER_ENTERING_WORLD")
        evF:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                local db = EnsureDB()
                if db.autoOnLogin then
                    C_Timer.After(5, function()
                        BroadcastPresence()
                        AddLog("Auto-ping on login")
                    end)
                end
            end
        end)

        local db = EnsureDB()
        if db.autoOnLogin then C_Timer.After(3, BroadcastPresence) end

        RefreshAll()
        GMT.Debug("GuildSync init done v3.3.0")
    end)

    if not ok and GMT and GMT.Err then
        GMT.Err("GuildSync init failed: "..tostring(err))
    end
end
