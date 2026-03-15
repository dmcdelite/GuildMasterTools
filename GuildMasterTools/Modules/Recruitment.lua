-- ============================================================
-- GuildMaster Tools  |  Modules/Recruitment.lua  |  v3.0.0
-- Phase 3 -- Recruitment Manager (preserved intact)
-- Phase 4 -- Recruitment Finder
--   . Trade / General / LFG chat scanner
--   . Whisper detection
--   . Pattern match engine with keyword config
--   . Live scanner feed with LED status indicator
--   . Auto-add detected players to results
-- ============================================================
local _, GMT = ...

GMT.RM = GMT.RM or {}
local RM = GMT.RM

local refs         = {}
local ROW_H        = 20
local pendingWho   = false
local lastWhoQuery = 0

-- ============================================================
-- PHASE 3 -- STATUS COLOR MAP
-- ============================================================
local STATUS_COLOR = {
    Prospect      = GMT.Grey,
    Messaged      = GMT.Amber,
    Invited       = GMT.Green,
    ["Follow-up"] = function(s) return "|cff66aaff"..s.."|r" end,
    Blacklisted   = GMT.Red,
}
local function StatusStr(s)
    local fn = STATUS_COLOR[s] or GMT.Dim
    return fn(s or "Prospect")
end

-- ============================================================
-- PHASE 4 -- SCANNER ENGINE
-- ============================================================
-- Chat channels to monitor (WoW channel numbers)
local SCAN_CHANNELS = {
    CHAT_MSG_CHANNEL = true,   -- Trade (2), General (1), LFG (5)
    CHAT_MSG_WHISPER = true,   -- incoming whispers
    CHAT_MSG_SAY     = true,   -- /say in world
    CHAT_MSG_YELL    = true,   -- /yell
}

-- Default LFG patterns (lower-case matching)
local DEFAULT_PATTERNS = {
    "lf.*guild", "looking.*guild", "lfguild", "need.*guild",
    "seeking.*guild", "want.*guild", "guild.*looking",
    "no.*guild", "guildless", "unguilded",
    "recruting", "recruiting",   -- intentional typo catch
}

local scannerFrame  = nil   -- event frame, created once
local scannerActive = false

local function GetScanPatterns()
    local db = GMT.DB.recruitment
    if db and db.scanner and db.scanner.patterns and #db.scanner.patterns > 0 then
        return db.scanner.patterns
    end
    return DEFAULT_PATTERNS
end

local function MessageMatchesLFG(msg)
    local lower = msg:lower()
    for _, pat in ipairs(GetScanPatterns()) do
        if lower:find(pat) then return true, pat end
    end
    return false
end

-- Add a detection to the scanner feed and optionally to results
local function AddDetection(playerName, msg, source)
    local db = GMT.DB.recruitment
    if not db then return end
    db.scanner = db.scanner or {}
    db.scanner.detections = db.scanner.detections or {}

    -- Dedup: skip if same player detected in last 10 minutes
    local now  = time()
    local short = GMT.Short(playerName)
    for _, det in ipairs(db.scanner.detections) do
        if GMT.Short(det.name) == short and (now - det.t) < 600 then return end
    end

    table.insert(db.scanner.detections, 1, {
        name   = short,
        msg    = msg,
        source = source,
        t      = now,
    })
    while #db.scanner.detections > 60 do
        table.remove(db.scanner.detections)
    end

    -- Also push into RM.results so they appear in the Finder Results list
    local alreadyInResults = false
    for _, r in ipairs(RM.results) do
        if GMT.Short(r.name) == short then alreadyInResults = true; break end
    end
    if not alreadyInResults then
        table.insert(RM.results, 1, {
            name     = playerName,
            fullName = playerName,
            level    = 0,
            class    = "",
            guild    = "",
            zone     = "[Scanner]",
            scanMsg  = GMT.Clip(msg, 40),
        })
    end

    -- Update LED and feed
    if refs.scanLED then
        refs.scanLED:SetVertexColor(GMT.U(GMT.C.green))
    end
    if refs.scanCount then
        refs.scanCount:SetText(GMT.Green(tostring(#db.scanner.detections)) .. GMT.Dim(" detected"))
    end
end

local function RefreshScannerFeed()
    if not refs.scanContent then return end
    refs.scanRows = refs.scanRows or {}
    local rows = refs.scanRows
    local db   = GMT.DB.recruitment
    local dets = (db and db.scanner and db.scanner.detections) or {}

    for i, det in ipairs(dets) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, refs.scanContent)
            row:SetPoint("TOPLEFT", refs.scanContent, "TOPLEFT", 0, -((i-1)*ROW_H))
            row:SetSize(340, ROW_H)
            row.bg  = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
            row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.txt:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.txt:SetWidth(334)
            row.txt:SetJustifyH("LEFT")
            rows[i] = row
        end
        row.bg:SetColorTexture(0.07, 0.05, 0.04, (i%2==0) and 0.30 or 0.12)
        local timeStr = GMT.Dim(date("%H:%M", det.t))
        local src     = GMT.Amber("["..(det.source or "?").."]")
        local nm      = "|cffbbbbbb" .. (det.name or "?") .. "|r"
        row.txt:SetText(timeStr .. " " .. src .. " " .. nm)
        row:Show()
        -- Click to select this person in Finder Results
        local detName = det.name
        row:SetScript("OnClick", function()
            for _, r in ipairs(RM.results) do
                if GMT.Short(r.name) == GMT.Short(detName) then
                    local key = GMT.Short(r.name)
                    RM.selectedResults[key] = not RM.selectedResults[key]
                    break
                end
            end
            if refs.RefreshResults then refs.RefreshResults() end
        end)
    end
    for i = #dets + 1, #rows do rows[i]:Hide() end
    refs.scanContent:SetHeight(math.max(ROW_H, #dets * ROW_H))
end

local function StartScanner()
    local db = GMT.DB.recruitment
    if not db then return end
    db.scanner = db.scanner or {}
    db.scanner.enabled = true
    scannerActive = true

    if not scannerFrame then
        scannerFrame = CreateFrame("Frame")
        scannerFrame:SetScript("OnEvent", function(_, event, msg, sender, ...)
            if not scannerActive then return end
            if event == "CHAT_MSG_WHISPER" then
                -- Only catch whispers that contain LFG content
                local match, _ = MessageMatchesLFG(msg)
                if match then
                    AddDetection(sender, msg, "Whisper")
                    RefreshScannerFeed()
                    if refs.RefreshResults then refs.RefreshResults() end
                end
            elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then
                local match, _ = MessageMatchesLFG(msg)
                if match then
                    local name = GMT.Short(sender)
                    AddDetection(name, msg, event == "CHAT_MSG_SAY" and "Say" or "Yell")
                    RefreshScannerFeed()
                    if refs.RefreshResults then refs.RefreshResults() end
                end
            elseif event == "CHAT_MSG_CHANNEL" then
                -- CHAT_MSG_CHANNEL payloads vary by client flavor/build.
                -- Walk the trailing args and use the first non-numeric string that looks like a channel name.
                local chanName = ""
                for i = 1, select("#", ...) do
                    local v = select(i, ...)
                    if type(v) == "string" and v ~= "" then
                        local lower = v:lower()
                        if lower:find("trade") or lower:find("general") or lower:find("lfg")
                        or lower:find("looking") or lower:find("local") or lower:find("defense")
                        or lower:find("world") then
                            chanName = v
                            break
                        end
                    end
                end
                local match, _ = MessageMatchesLFG(msg)
                if match and chanName ~= "" then
                    local name = GMT.Short(sender)
                    local cn = chanName:lower()
                    if cn:find("trade") or cn:find("general") or cn:find("lfg")
                    or cn:find("looking") or cn:find("local") or cn:find("defense")
                    or cn:find("world") then
                        AddDetection(name, msg, chanName)
                        RefreshScannerFeed()
                        if refs.RefreshResults then refs.RefreshResults() end
                    end
                end
            end
        end)
    end

    for event in pairs(SCAN_CHANNELS) do
        scannerFrame:RegisterEvent(event)
    end

    if refs.scanBtn then refs.scanBtn:SetText("Scanner: ON") end
    if refs.scanLED then refs.scanLED:SetVertexColor(GMT.U(GMT.C.green)) end
    if refs.scanStatus then refs.scanStatus:SetText(GMT.Green("Listening for LFG patterns...")) end
    GMT.Debug("Phase 4: Scanner started.")
end

local function StopScanner()
    local db = GMT.DB.recruitment
    if db then db.scanner = db.scanner or {}; db.scanner.enabled = false end
    scannerActive = false
    if scannerFrame then
        for event in pairs(SCAN_CHANNELS) do
            scannerFrame:UnregisterEvent(event)
        end
    end
    if refs.scanBtn then refs.scanBtn:SetText("Scanner: OFF") end
    if refs.scanLED then refs.scanLED:SetVertexColor(GMT.U(GMT.C.red)) end
    if refs.scanStatus then refs.scanStatus:SetText(GMT.Dim("Scanner off")) end
    GMT.Debug("Phase 4: Scanner stopped.")
end

local function ToggleScanner()
    if scannerActive then StopScanner() else StartScanner() end
end

local function ClearDetections()
    local db = GMT.DB.recruitment
    if db and db.scanner then db.scanner.detections = {} end
    RM.results = {}
    RM.selectedResults = {}
    RefreshScannerFeed()
    if refs.RefreshResults then refs.RefreshResults() end
    if refs.scanCount then refs.scanCount:SetText(GMT.Dim("0 detected")) end
    if refs.scanLED then refs.scanLED:SetVertexColor(GMT.U(GMT.C.grey)) end
end

-- ============================================================
-- DATA HELPERS
-- ============================================================
local function SafeMaxLevel()
    if type(GetMaxPlayerLevel) == "function" then
        local ok, v = pcall(GetMaxPlayerLevel)
        if ok and v then return v end
    end
    return MAX_PLAYER_LEVEL or 80
end

local function EnsureDB()
    GMT.DB.recruitment = GMT.DB.recruitment or {}
    local db = GMT.DB.recruitment
    db.settings = db.settings or {}
    if db.settings.minLevel     == nil then db.settings.minLevel         = 10            end
    if db.settings.maxLevel     == nil then db.settings.maxLevel         = SafeMaxLevel() end
    if db.settings.query        == nil then db.settings.query            = ""            end
    if db.settings.autoWhisper  == nil then db.settings.autoWhisper      = false         end
    if db.settings.autoInvite   == nil then db.settings.autoInvite       = false         end
    if db.settings.skipRecent   == nil then db.settings.skipRecent       = true          end
    if db.settings.messageDelay == nil then db.settings.messageDelay     = 3             end
    if db.settings.inviteDelay  == nil then db.settings.inviteDelay      = 1             end
    if db.settings.contactWindowMin == nil then db.settings.contactWindowMin = 30        end
    if db.settings.scanCooldown == nil then db.settings.scanCooldown     = 15            end
    db.templates = db.templates or {}
    if not db.templates.primary or db.templates.primary == "" then
        db.templates.primary = "Hey PLAYERNAME - <GUILDNAME> is recruiting active players. Interested in joining?"
    end
    db.blacklist  = db.blacklist  or {}
    db.contacted  = db.contacted  or {}
    db.pipeline   = db.pipeline   or {}
    db.history    = db.history    or {}
    -- Phase 4 scanner DB
    db.scanner = db.scanner or { enabled=false, patterns={}, detections={} }
    return db
end

local function ShortName(n)   return GMT.Short(n or "") end
local function ActionName(p)  return type(p)=="table" and (p.fullName or p.name or "") or (p or "") end
local function DisplayName(p) return type(p)=="table" and ShortName(p.name or p.fullName or "") or ShortName(p or "") end

local function AddHistory(msg)
    local db = EnsureDB()
    table.insert(db.history, 1, { t=time(), msg=msg })
    while #db.history > 40 do table.remove(db.history) end
end

local function SetStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Ready")
    if     kind == "green" then refs.status:SetTextColor(GMT.U(GMT.C.green))
    elseif kind == "red"   then refs.status:SetTextColor(GMT.U(GMT.C.red))
    else                        refs.status:SetTextColor(GMT.U(GMT.C.amber))
    end
end

local function IsBlacklisted(name)     return EnsureDB().blacklist[ShortName(name)] == true end
local function IsRecentlyContacted(name)
    local db = EnsureDB()
    local ts = db.contacted[ShortName(name)]
    if not ts then return false end
    return (time() - ts) < ((db.settings.contactWindowMin or 30) * 60)
end
local function MarkContacted(name) EnsureDB().contacted[ShortName(name)] = time() end

local function FindPipelineIndex(name)
    local short = ShortName(name)
    for i, row in ipairs(EnsureDB().pipeline) do
        if ShortName(row.name) == short then return i end
    end
    return nil
end

local function AddToPipeline(player, status)
    local db  = EnsureDB()
    local idx = FindPipelineIndex(player.name)
    if idx then
        local row = db.pipeline[idx]
        row.level    = player.level or row.level
        row.class    = player.class or row.class
        row.zone     = player.zone  or row.zone
        row.status   = status or row.status or "Prospect"
        row.lastSeen = time()
        return row
    end
    local entry = {
        name        = ShortName(player.name),
        fullName    = player.fullName or player.name,
        level       = player.level or 0,
        class       = player.class or "",
        zone        = player.zone  or "",
        status      = status or "Prospect",
        note        = "",
        lastSeen    = time(),
        lastContact = 0,
    }
    table.insert(db.pipeline, 1, entry)
    while #db.pipeline > 200 do table.remove(db.pipeline) end
    return entry
end

local function TemplateText(player)
    local db    = EnsureDB()
    local guild = GetGuildInfo("player") or "Our Guild"
    local text  = db.templates.primary or ""
    text = text:gsub("PLAYERNAME", DisplayName(player))
    text = text:gsub("GUILDNAME",  guild)
    return text
end

local function SaveControls()
    local db = EnsureDB()
    if refs.minLevel then db.settings.minLevel = tonumber(refs.minLevel:GetText()) or db.settings.minLevel end
    if refs.maxLevel then db.settings.maxLevel = tonumber(refs.maxLevel:GetText()) or db.settings.maxLevel end
    if refs.query    then db.settings.query    = refs.query:GetText() or "" end
    if refs.template then
        local t = refs.template:GetText()
        if t and t ~= "" then db.templates.primary = t end
    end
end

local function LoadControls()
    local db = EnsureDB()
    if refs.minLevel    then refs.minLevel:SetText(tostring(db.settings.minLevel or 10)) end
    if refs.maxLevel    then refs.maxLevel:SetText(tostring(db.settings.maxLevel or SafeMaxLevel())) end
    if refs.query       then refs.query:SetText(db.settings.query or "") end
    if refs.template    then refs.template:SetText(db.templates.primary or "") end
    if refs.autoWhisper then refs.autoWhisper:SetChecked(db.settings.autoWhisper) end
    if refs.autoInvite  then refs.autoInvite:SetChecked(db.settings.autoInvite)   end
    if refs.skipRecent  then refs.skipRecent:SetChecked(db.settings.skipRecent)   end
    -- Restore scanner state
    if db.scanner and db.scanner.enabled and not scannerActive then
        StartScanner()
    end
end

-- ============================================================
-- LOCAL UI HELPERS
-- ============================================================
local function Section(parent, title, x, y, w, h)
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

local function Label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(GMT.U(GMT.C.txtDim))
    fs:SetText(text)
    return fs
end

local function Input(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus(); SaveControls() end)
    return eb
end

local function MultiInput(parent, x, y, w, h)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, h)
    bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bg:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    bg:SetBackdropColor(GMT.U(GMT.C.panelBg))
    bg:SetBackdropBorderColor(GMT.U(GMT.C.brass))
    local eb = CreateFrame("EditBox", nil, bg)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextColor(GMT.U(GMT.C.txtBody))
    eb:SetPoint("TOPLEFT",     bg, "TOPLEFT",      6, -6)
    eb:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -6,  6)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged",   function() SaveControls() end)
    return eb
end

local function Check(parent, text, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetChecked(getter())
    local txt = cb.text or _G[(cb:GetName() or "") .. "Text"]
    if txt then
        txt:SetText(text)
        txt:SetTextColor(GMT.U(GMT.C.txtBody))
        txt:SetFontObject("GameFontHighlightSmall")
    end
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

local function MakeScrollList(parent, x, y, w, h, columns)
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
    for _, col in ipairs(columns) do
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
    btn.bg    = btn:CreateTexture(nil, "BACKGROUND"); btn.bg:SetAllPoints()
    btn.texts = {}
    return btn
end

local function SetRow(row, cols, values)
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

-- ============================================================
-- COLUMN DEFINITIONS
-- ============================================================
local resultsCols = {
    { label="",       w=20,  j="CENTER" },
    { label="Name",   w=126, j="LEFT"   },
    { label="Class",  w=84,  j="LEFT"   },
    { label="Lvl",    w=30,  j="CENTER" },
    { label="Source", w=72,  j="LEFT"   },
    { label="Flag",   w=42,  j="LEFT"   },
    { label="",       w=58,  j="CENTER" },  -- invite button column
}  -- total 432  (content width   510, fits fine)

local pipeCols = {
    { label="",       w=20,  j="CENTER" },
    { label="Name",   w=104, j="LEFT"   },
    { label="Status", w=72,  j="LEFT"   },
    { label="Last",   w=50,  j="LEFT"   },
    { label="Note",   w=90,  j="LEFT"   },
}  -- total 336

-- ============================================================
-- STATE
-- ============================================================
RM.results          = RM.results          or {}
RM.selectedResults  = RM.selectedResults  or {}
RM.selectedPipeline = RM.selectedPipeline or {}

local function FormatAgo(ts)
    if not ts or ts <= 0 then return GMT.Dim("Never") end
    local d = time() - ts
    if d < 60    then return GMT.Green("Now") end
    if d < 3600  then return tostring(math.floor(d/60)) .. "m"   end
    if d < 86400 then return tostring(math.floor(d/3600)) .. "h" end
    return tostring(math.floor(d/86400)) .. "d"
end

local function GetSelectedResults()
    local out = {}
    for _, p in ipairs(RM.results) do
        if RM.selectedResults[ShortName(p.name)] then table.insert(out, p) end
    end
    return out
end

local function GetSelectedPipeline()
    local out = {}
    for _, r in ipairs(EnsureDB().pipeline) do
        if RM.selectedPipeline[ShortName(r.name)] then table.insert(out, r) end
    end
    return out
end

local function PassesFilters(player)
    local db  = EnsureDB()
    local min = tonumber(db.settings.minLevel) or 1
    local max = tonumber(db.settings.maxLevel) or SafeMaxLevel()
    if player.level and player.level > 0
    and (player.level < min or player.level > max) then return false end
    if player.guild and player.guild ~= "" then return false end
    if IsBlacklisted(player.name) then return false end
    if db.settings.skipRecent and IsRecentlyContacted(player.name) then return false end
    return true
end

-- ============================================================
-- REFRESH FUNCTIONS
-- ============================================================
-- Forward declarations -- closures inside RefreshResults reference
-- RefreshPipeline which is defined after it. Lua requires upvalue
-- declaration before the first closure that captures it.
local RefreshPipeline
local RefreshStats

local function RefreshResults()
    if not refs.resultsContent then return end
    refs.resultRows = refs.resultRows or {}
    local rows = refs.resultRows
    for i, player in ipairs(RM.results) do
        local row = rows[i]
        if not row then
            row = Row(refs.resultsContent, -((i-1)*ROW_H), 460)
            -- Inline Invite button -- created once, reused each refresh
            local invBtn = GMT.MBtn(row, "Invite", 54, 16)
            invBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 376, 2)
            if invBtn:GetNormalTexture()    then invBtn:GetNormalTexture():SetVertexColor(0.20, 0.45, 0.15) end
            if invBtn:GetHighlightTexture() then invBtn:GetHighlightTexture():SetVertexColor(0.35, 0.70, 0.25, 0.55) end
            if invBtn:GetPushedTexture()    then invBtn:GetPushedTexture():SetVertexColor(0.12, 0.30, 0.08) end
            invBtn:GetFontString():SetTextColor(0.30, 1.00, 0.40)
            row.inviteBtn = invBtn
            rows[i] = row
        end
        local key      = ShortName(player.name)
        local selected = RM.selectedResults[key]
        row.bg:SetColorTexture(
            selected and 0.18 or 0.07,
            selected and 0.22 or 0.05, 0.04,
            selected and 0.75 or ((i%2==0) and 0.30 or 0.12))
        row:Show()
        local flag = "Open"
        if IsRecentlyContacted(key) then flag = GMT.Amber("Recent")
        elseif IsBlacklisted(key)   then flag = GMT.Red("Block")
        elseif FindPipelineIndex(key) then flag = GMT.Green("Saved")
        end
        -- Show zone or scan source
        local source = player.scanMsg and (GMT.Amber("[Scan]")) or GMT.Clip(player.zone or "--", 12)
        SetRow(row, resultsCols, {
            selected and GMT.Green("x") or "",
            GMT.ClassStr(player.class or "", DisplayName(player)),
            player.class or GMT.Dim("?"),
            player.level and player.level > 0 and tostring(player.level) or GMT.Dim("?"),
            source,
            flag,
            "",  -- invite column placeholder (button overlays this)
        })
        -- Wire invite button to this specific player (closure captures snapshot)
        if row.inviteBtn then
            local capturedPlayer = player
            row.inviteBtn:SetScript("OnClick", function()
                if CanGuildInvite and not CanGuildInvite() then
                    SetStatus("No guild invite permission.", "red"); return
                end
                local target = capturedPlayer.fullName or capturedPlayer.name
                if target and target ~= "" then
                    local ok = false
                    if GuildInvite then ok = pcall(GuildInvite, target)
                    elseif C_GuildInfo and C_GuildInfo.Invite then ok = pcall(C_GuildInfo.Invite, target) end
                    if ok then
                        MarkContacted(capturedPlayer.name)
                        local entry = AddToPipeline(capturedPlayer, "Invited")
                        entry.lastContact = time()
                        AddHistory("Invited " .. DisplayName(capturedPlayer))
                        SetStatus("Invited " .. DisplayName(capturedPlayer) .. ".", "green")
                        RefreshPipeline()
                    else
                        SetStatus("Invite failed for " .. DisplayName(capturedPlayer) .. ".", "red")
                    end
                end
            end)
        end
        row:SetScript("OnClick", function()
            RM.selectedResults[key] = not RM.selectedResults[key]
            RefreshResults()
        end)
    end
    for i = #RM.results + 1, #rows do rows[i]:Hide() end
    refs.resultsContent:SetHeight(math.max(ROW_H, #RM.results * ROW_H))
    if refs.resultsStats then
        local scanCount = 0
        for _, r in ipairs(RM.results) do if r.scanMsg then scanCount = scanCount + 1 end end
        local txt = GMT.Amber(tostring(#RM.results)) .. GMT.Dim(" result(s)")
        if scanCount > 0 then txt = txt .. "  " .. GMT.Green(tostring(scanCount)) .. GMT.Dim(" from scanner") end
        refs.resultsStats:SetText(#RM.results > 0 and txt or GMT.Dim("No results"))
    end
end
-- Expose for scanner engine callbacks
refs.RefreshResults = RefreshResults

RefreshPipeline = function()
    if not refs.pipeContent then return end
    refs.pipeRows = refs.pipeRows or {}
    local rows     = refs.pipeRows
    local pipeline = EnsureDB().pipeline
    for i, item in ipairs(pipeline) do
        local row = rows[i]
        if not row then
            row = Row(refs.pipeContent, -((i-1)*ROW_H), 336)
            rows[i] = row
        end
        local key      = ShortName(item.name)
        local selected = RM.selectedPipeline[key]
        row.bg:SetColorTexture(
            selected and 0.18 or 0.07,
            selected and 0.22 or 0.05, 0.04,
            selected and 0.75 or ((i%2==0) and 0.30 or 0.12))
        row:Show()
        SetRow(row, pipeCols, {
            selected and GMT.Green("x") or "",
            GMT.ClassStr(item.class or "", item.name),
            StatusStr(item.status),
            FormatAgo(item.lastContact),
            GMT.Clip(item.note or "", 14),
        })
        row:SetScript("OnClick", function()
            RM.selectedPipeline[key] = not RM.selectedPipeline[key]
            if RM.selectedPipeline[key] then
                refs.pipeNoteTarget = key
                if refs.pipeNoteInput then refs.pipeNoteInput:SetText(item.note or "") end
            end
            RefreshPipeline()
        end)
    end
    for i = #pipeline + 1, #rows do rows[i]:Hide() end
    refs.pipeContent:SetHeight(math.max(ROW_H, #pipeline * ROW_H))
    if refs.pipeStats then
        if #pipeline == 0 then
            refs.pipeStats:SetText(GMT.Dim("Empty pipeline"))
        else
            local counts = {}
            local order  = {"Prospect","Messaged","Invited","Follow-up","Blacklisted"}
            for _, item in ipairs(pipeline) do
                local s = item.status or "Prospect"
                counts[s] = (counts[s] or 0) + 1
            end
            local parts = {}
            for _, s in ipairs(order) do
                if counts[s] then table.insert(parts, StatusStr(s)..GMT.Dim(":"..counts[s])) end
            end
            refs.pipeStats:SetText(table.concat(parts, "  "))
        end
    end
end

RefreshStats = function()
    local db = EnsureDB()
    if refs.stats then
        local bl = 0; for _ in pairs(db.blacklist) do bl = bl + 1 end
        refs.stats:SetText(
            GMT.Dim("Results") .. " " .. GMT.Amber(tostring(#RM.results)) ..
            "   " .. GMT.Dim("Pipeline") .. " " .. GMT.Green(tostring(#db.pipeline)) ..
            "   " .. GMT.Dim("Blacklist") .. " " .. GMT.Grey(tostring(bl)))
    end
end

local function RefreshAll()
    LoadControls()
    RefreshResults()
    RefreshPipeline()
    RefreshScannerFeed()
    RefreshStats()
end

-- ============================================================
-- PHASE 3 ACTIONS (preserved)
-- ============================================================
local function SaveTemplate()
    SaveControls()
    SetStatus("Recruitment template saved.", "green")
    AddHistory("Updated recruitment template")
end

local function SaveSelectedResults()
    local picked = GetSelectedResults()
    local count  = 0
    for _, p in ipairs(picked) do AddToPipeline(p, "Prospect"); count = count + 1 end
    SetStatus("Saved " .. count .. " recruit(s) to pipeline.", count>0 and "green" or "red")
    AddHistory("Saved " .. count .. " recruits to pipeline")
    RefreshAll()
end

local function BlacklistSelected()
    local db    = EnsureDB()
    local count = 0
    for _, p in ipairs(GetSelectedResults()) do
        db.blacklist[ShortName(p.name)] = true
        RM.selectedResults[ShortName(p.name)] = nil
        count = count + 1
    end
    for _, r in ipairs(GetSelectedPipeline()) do
        db.blacklist[ShortName(r.name)] = true
        RM.selectedPipeline[ShortName(r.name)] = nil
        r.status = "Blacklisted"
        count = count + 1
    end
    SetStatus("Blacklisted " .. count .. " recruit(s).", count>0 and "green" or "red")
    AddHistory("Blacklisted " .. count .. " recruits")
    RefreshAll()
end

local function UpdatePipelineStatus(status)
    local picked = GetSelectedPipeline()
    local count  = 0
    for _, row in ipairs(picked) do
        row.status = status
        if status == "Messaged" or status == "Invited" or status == "Follow-up" then
            row.lastContact = time()
        end
        count = count + 1
    end
    SetStatus("Updated " .. count .. " to " .. status .. ".", count>0 and "green" or "red")
    AddHistory("Marked " .. count .. " recruits as " .. status)
    RefreshAll()
end

local function RemoveSelectedPipeline()
    local db      = EnsureDB()
    local fresh   = {}
    local removed = 0
    for _, row in ipairs(db.pipeline) do
        if RM.selectedPipeline[ShortName(row.name)] then
            removed = removed + 1
        else
            table.insert(fresh, row)
        end
    end
    db.pipeline           = fresh
    RM.selectedPipeline   = {}
    refs.pipeNoteTarget   = nil
    if refs.pipeNoteInput then refs.pipeNoteInput:SetText("") end
    SetStatus("Removed " .. removed .. " recruit(s).", removed>0 and "green" or "red")
    AddHistory("Removed " .. removed .. " recruits from pipeline")
    RefreshAll()
end

local function SendWhisperTo(player)
    local msg    = TemplateText(player)
    local target = ActionName(player)
    if target == "" then return false end
    SendChatMessage(msg, "WHISPER", nil, target)
    MarkContacted(player.name)
    local row = AddToPipeline(player, "Messaged")
    row.lastContact = time()
    AddHistory("Whispered " .. DisplayName(player))
    return true
end

local function WhisperSelected()
    local db     = EnsureDB()
    local picked = GetSelectedResults()
    if #picked == 0 then SetStatus("Select at least one recruit to whisper.", "red"); return end
    local function step(i)
        local player = picked[i]
        if not player then SetStatus("Whisper queue complete.", "green"); RefreshAll(); return end
        if (not db.settings.skipRecent) or (not IsRecentlyContacted(player.name)) then
            SendWhisperTo(player)
        end
        RefreshAll()
        C_Timer.After(db.settings.messageDelay or 3, function() step(i+1) end)
    end
    SetStatus("Whispering " .. #picked .. " recruit(s)...", "green")
    step(1)
end

local function SendInviteTo(player)
    local target = ActionName(player)
    if target == "" then return false end
    local ok = false
    if GuildInvite then ok = pcall(GuildInvite, target)
    elseif C_GuildInfo and C_GuildInfo.Invite then ok = pcall(C_GuildInfo.Invite, target) end
    if ok then
        MarkContacted(player.name)
        local row = AddToPipeline(player, "Invited")
        row.lastContact = time()
        AddHistory("Invited " .. DisplayName(player))
    end
    return ok
end

local function InviteSelected()
    local db     = EnsureDB()
    local picked = GetSelectedResults()
    if #picked == 0 then SetStatus("Select at least one recruit to invite.", "red"); return end
    if CanGuildInvite and not CanGuildInvite() then
        SetStatus("No guild invite permission.", "red"); return
    end
    local function step(i)
        local player = picked[i]
        if not player then SetStatus("Invite queue complete.", "green"); RefreshAll(); return end
        SendInviteTo(player)
        RefreshAll()
        C_Timer.After(db.settings.inviteDelay or 1, function() step(i+1) end)
    end
    SetStatus("Inviting " .. #picked .. " recruit(s)...", "green")
    step(1)
end

local function ScanTarget()
    SaveControls()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        SetStatus("No player target selected.", "red"); return
    end
    local name = UnitName("target")
    local _, cf = UnitClass("target")
    RM.results         = {{ name=name, fullName=name, level=UnitLevel("target"),
                            class=cf, guild=GetGuildInfo("target"), zone=GetZoneText() or "" }}
    RM.selectedResults = {}
    SetStatus("Scanned target: " .. ShortName(name), "green")
    AddHistory("Scanned target " .. ShortName(name))
    RefreshAll()
end

local function ProcessWhoResults()
    local total = 0
    if C_FriendList and C_FriendList.GetNumWhoResults then
        total = C_FriendList.GetNumWhoResults() or 0
    elseif GetNumWhoResults then
        total = GetNumWhoResults() or 0
    end
    RM.results         = {}
    RM.selectedResults = {}
    for i = 1, total do
        local info
        if C_FriendList and C_FriendList.GetWhoInfo then
            info = C_FriendList.GetWhoInfo(i)
        elseif GetWhoInfo then
            local fn, guild, level, _, cd, zone, cf = GetWhoInfo(i)
            info = { fullName=fn, name=fn, guild=guild, level=level, area=zone, filename=cf or cd }
        end
        if info then
            local p = {
                name     = info.name or info.fullName,
                fullName = info.fullName or info.name,
                level    = info.level or 0,
                class    = info.filename or info.classFilename or "",
                guild    = info.fullGuildName or info.guild or "",
                zone     = info.area or "",
            }
            if p.name and p.name ~= UnitName("player") and PassesFilters(p) then
                table.insert(RM.results, p)
            end
        end
    end
    pendingWho = false
    AddHistory("Finder returned " .. #RM.results .. " recruit(s)")
    SetStatus("Finder: " .. #RM.results .. " result(s).", #RM.results>0 and "green" or "red")
    RefreshAll()
    local db = EnsureDB()
    if refs.autoWhisper and refs.autoWhisper:GetChecked() then
        for _, p in ipairs(RM.results) do RM.selectedResults[ShortName(p.name)] = true end
        WhisperSelected()
        if refs.autoInvite and refs.autoInvite:GetChecked() then
            C_Timer.After((#RM.results * (db.settings.messageDelay or 3)) + 1, InviteSelected)
        end
    elseif refs.autoInvite and refs.autoInvite:GetChecked() then
        for _, p in ipairs(RM.results) do RM.selectedResults[ShortName(p.name)] = true end
        C_Timer.After(0.5, InviteSelected)
    end
end

local function RunFinder()
    SaveControls()
    local db  = EnsureDB()
    local now = GetTime()
    local cd  = db.settings.scanCooldown or 15
    if pendingWho then SetStatus("Finder already running.", "red"); return end
    if now - lastWhoQuery < cd then
        SetStatus("Cooldown: " .. math.ceil(cd - (now - lastWhoQuery)) .. "s", "red"); return
    end
    local q = tostring(db.settings.minLevel or 10) .. "-" .. tostring(db.settings.maxLevel or SafeMaxLevel())
    local e = db.settings.query or ""
    if e ~= "" then q = q .. " " .. e end
    RM.results = {}; RM.selectedResults = {}
    pendingWho = true; lastWhoQuery = now
    local ok = false
    if FriendsFrame_SendWho then ok = pcall(FriendsFrame_SendWho, q) end
    if not ok and C_FriendList and C_FriendList.SendWho then ok = pcall(C_FriendList.SendWho, q) end
    if not ok then pendingWho = false; SetStatus("WHO finder failed.", "red"); return end
    SetStatus("Running finder: " .. q, "green")
    AddHistory("Started finder: " .. q)
    C_Timer.After(2, function() if pendingWho then ProcessWhoResults() end end)
end

-- ============================================================
-- INIT  -- Phase 4 layout
-- ============================================================
-- Layout (PH=528):
--   header/label: 58px
--   Row 1 Controls (full W): ctrlH=136
--   gap: 8
--   Row 2 Data left(550) | right(386): dataH=188
--   gap: 8
--   Row 3 Template+Actions(550) | Scanner Feed(386): btmH=96
--   status bar: ~12px
-- Total: 58+136+8+188+8+96+12 = 506  (22px margin)
-- ============================================================
function GMT_Recruitment_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Recruitment")
        if not panel or panel._builtRecruitment then return end
        panel._builtRecruitment = true

        EnsureDB()

        GMT.Header(panel, "Recruitment Suite", 14, -10)
        GMT.Label(panel, "WHO Finder  .  Chat Scanner  .  Pipeline  .  Whisper / Invite", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local PAD    = 8
        local GAP    = 8
        local W      = GMT.PW - PAD * 2   -- 944
        local leftW  = 550
        local rightW = W - leftW - GAP    -- 386

        local ctrlY = -58;  local ctrlH = 136
        local dataY = ctrlY - ctrlH - GAP -- -202
        local dataH = 188
        local btmY  = dataY - dataH - GAP -- -398
        local btmH  = 112

        local db = EnsureDB()

        -- +================================================== 
        -- |  ROW 1 -- Controls (full width)                  |
        -- +================================================== 
        local ctrlBox = Section(panel, "Finder + Scanner Controls", PAD, ctrlY, W, ctrlH)

        --    WHO Finder row                                  
        Label(ctrlBox, "Min Lvl",     12,  -32)
        Label(ctrlBox, "Max Lvl",     74,  -32)
        Label(ctrlBox, "Zone / Query", 136, -32)
        refs.minLevel = Input(ctrlBox, 12,  -46, 52, 20)
        refs.maxLevel = Input(ctrlBox, 74,  -46, 52, 20)
        refs.query    = Input(ctrlBox, 136, -46, 286, 20)

        local runBtn = GMT.MBtn(ctrlBox, "Run Finder",  106, 22)
        runBtn:SetPoint("TOPLEFT", ctrlBox, "TOPLEFT", 430, -45)
        runBtn:SetScript("OnClick", RunFinder)

        local targetBtn = GMT.MBtn(ctrlBox, "Scan Target", 106, 22)
        targetBtn:SetPoint("TOPLEFT", ctrlBox, "TOPLEFT", 544, -45)
        targetBtn:SetScript("OnClick", ScanTarget)

        --    Finder checkboxes                               
        refs.autoWhisper = Check(ctrlBox, "Auto Whisper", 12,  -70, function() return db.settings.autoWhisper end, function(v) db.settings.autoWhisper = v end)
        refs.autoInvite  = Check(ctrlBox, "Auto Invite",  142, -70, function() return db.settings.autoInvite  end, function(v) db.settings.autoInvite  = v end)
        refs.skipRecent  = Check(ctrlBox, "Skip Recent",  262, -70, function() return db.settings.skipRecent  end, function(v) db.settings.skipRecent  = v end)

        --    Phase 4 scanner row                             
        -- Copper divider separating Finder from Scanner
        local scanDiv = ctrlBox:CreateTexture(nil, "ARTWORK")
        scanDiv:SetPoint("TOPLEFT",  ctrlBox, "TOPLEFT",   6, -96)
        scanDiv:SetPoint("TOPRIGHT", ctrlBox, "TOPRIGHT", -6, -96)
        scanDiv:SetHeight(1)
        scanDiv:SetColorTexture(GMT.U(GMT.C.copper))
        scanDiv:SetAlpha(0.45)

        -- Phase 4 scanner label with LED
        local scanLabel = ctrlBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scanLabel:SetPoint("TOPLEFT", ctrlBox, "TOPLEFT", 30, -104)
        scanLabel:SetTextColor(GMT.U(GMT.C.txtTitle))
        scanLabel:SetText("CHAT SCANNER  --  Trade . General . LFG . Whisper . Say")

        -- LED indicator
        refs.scanLED = GMT.LED(ctrlBox, 18, -108, 9, GMT.C.red)

        -- Scanner toggle button
        refs.scanBtn = GMT.MBtn(ctrlBox, "Scanner: OFF", 120, 22)
        refs.scanBtn:SetPoint("TOPRIGHT", ctrlBox, "TOPRIGHT", -134, -100)
        refs.scanBtn:SetScript("OnClick", ToggleScanner)

        -- Clear button
        local clearBtn = GMT.MBtn(ctrlBox, "Clear Feed", 100, 22)
        clearBtn:SetPoint("LEFT", refs.scanBtn, "RIGHT", 8, 0)
        clearBtn:SetScript("OnClick", function()
            ClearDetections()
            SetStatus("Scanner feed cleared.", "green")
        end)

        -- Scanner status / hint text
        refs.scanStatus = ctrlBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.scanStatus:SetPoint("TOPLEFT", ctrlBox, "TOPLEFT", 30, -122)
        refs.scanStatus:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.scanStatus:SetText("Monitors chat and adds detected players to results.")

        -- Detected count badge
        refs.scanCount = ctrlBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.scanCount:SetPoint("TOPRIGHT", ctrlBox, "TOPRIGHT", -18, -124)
        refs.scanCount:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.scanCount:SetText(GMT.Dim("0 detected"))

        -- +================================================== 
        -- |  ROW 2A -- Finder Results (left)                 |
        -- +================================================== 
        local resultsBox = Section(panel, "Results  (WHO + Scanner)", PAD, dataY, leftW, dataH)

        refs.resultsStats = resultsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.resultsStats:SetPoint("TOPRIGHT", resultsBox, "TOPRIGHT", -14, -32)
        refs.resultsStats:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.resultsStats:SetText(GMT.Dim("No results"))

        -- list height = dataH - 58 = 130
        local _, resultsContent = MakeScrollList(resultsBox, 8, -48, leftW - 16, dataH - 58, resultsCols)
        refs.resultsContent = resultsContent

        -- +================================================== 
        -- |  ROW 2B -- Pipeline (right)                      |
        -- +================================================== 
        local pipeBox = Section(panel, "Recruitment Pipeline", PAD + leftW + GAP, dataY, rightW, dataH)

        refs.pipeStats = pipeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.pipeStats:SetPoint("TOPLEFT", pipeBox, "TOPLEFT", 10, -32)
        refs.pipeStats:SetTextColor(GMT.U(GMT.C.txtDim))
        refs.pipeStats:SetText(GMT.Dim("Empty pipeline"))

        -- scroll list height = 90
        local _, pipeContent = MakeScrollList(pipeBox, 8, -48, rightW - 16, 90, pipeCols)
        refs.pipeContent = pipeContent

        -- Note editor
        Label(pipeBox, "Note:", 10, -146)
        refs.pipeNoteInput  = Input(pipeBox, 52, -144, 200, 18)
        refs.pipeNoteTarget = nil
        local saveNoteBtn   = GMT.MBtn(pipeBox, "Save", 56, 18)
        saveNoteBtn:SetPoint("TOPLEFT", pipeBox, "TOPLEFT", 260, -143)
        saveNoteBtn:SetScript("OnClick", function()
            local key = refs.pipeNoteTarget
            if not key then SetStatus("Select a pipeline recruit first.", "red"); return end
            for _, row in ipairs(EnsureDB().pipeline) do
                if ShortName(row.name) == key then
                    row.note = refs.pipeNoteInput:GetText() or ""
                    break
                end
            end
            SetStatus("Note saved for " .. key .. ".", "green")
            RefreshPipeline()
        end)

        -- Pipeline action buttons (LEFT-chained, 4 across)
        local pmBtn = GMT.MBtn(pipeBox, "Messaged",  80, 20)
        local piBtn = GMT.MBtn(pipeBox, "Invited",   80, 20)
        local pfBtn = GMT.MBtn(pipeBox, "Follow-up", 88, 20)
        local prBtn = GMT.MBtn(pipeBox, "Remove",    80, 20)
        pmBtn:SetPoint("BOTTOMLEFT", pipeBox, "BOTTOMLEFT", 8, 8)
        piBtn:SetPoint("LEFT", pmBtn, "RIGHT", 5, 0)
        pfBtn:SetPoint("LEFT", piBtn, "RIGHT", 5, 0)
        prBtn:SetPoint("LEFT", pfBtn, "RIGHT", 5, 0)
        pmBtn:SetScript("OnClick", function() UpdatePipelineStatus("Messaged")  end)
        piBtn:SetScript("OnClick", function() UpdatePipelineStatus("Invited")   end)
        pfBtn:SetScript("OnClick", function() UpdatePipelineStatus("Follow-up") end)
        prBtn:SetScript("OnClick", RemoveSelectedPipeline)

        -- +================================================== 
        -- |  ROW 3A -- Template + Actions (left)             |
        -- +================================================== 
        local tplBox = Section(panel, "Message Template & Actions", PAD, btmY, leftW, btmH)

        Label(tplBox, "Tokens: PLAYERNAME  GUILDNAME", 12, -32)
        refs.template = MultiInput(tplBox, 12, -48, leftW - 24, 30)

        -- 5 equal action buttons, TOPLEFT chained
        local btnDefs = {
            { label="Save Template",  fn=SaveTemplate         },
            { label="Whisper",        fn=WhisperSelected      },
            { label="Invite",         fn=InviteSelected       },
            { label="  Pipeline",     fn=SaveSelectedResults  },
            { label="Blacklist",      fn=BlacklistSelected    },
        }
        for i, bdef in ipairs(btnDefs) do
            local btn = GMT.MBtn(tplBox, bdef.label, 100, 22)
            btn:SetPoint("TOPLEFT", tplBox, "TOPLEFT", 12 + (i-1)*104, -82)
            btn:SetScript("OnClick", bdef.fn)
        end

        -- +================================================== 
        -- |  ROW 3B -- Scanner Feed (right)                  |
        -- +================================================== 
        local feedBox = Section(panel, "Live Scanner Feed", PAD + leftW + GAP, btmY, rightW, btmH)

        local feedHint = feedBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        feedHint:SetPoint("TOPRIGHT", feedBox, "TOPRIGHT", -14, -32)
        feedHint:SetTextColor(GMT.U(GMT.C.txtDim))
        feedHint:SetText(GMT.Dim("Click row to select in Results"))

        -- Scanner feed scroll list (height = btmH - 42 = 54)
        local feedSF = CreateFrame("ScrollFrame", nil, feedBox, "UIPanelScrollFrameTemplate")
        feedSF:SetSize(rightW - 28, btmH - 44)
        feedSF:SetPoint("TOPLEFT", feedBox, "TOPLEFT", 8, -34)

        refs.scanContent = CreateFrame("Frame", nil, feedSF)
        refs.scanContent:SetSize(rightW - 28, ROW_H)
        feedSF:SetScrollChild(refs.scanContent)

        --    Status bar                                      
        refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Recruitment systems ready.")

        refs.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.stats:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
        refs.stats:SetTextColor(GMT.U(GMT.C.txtDim))

        panel:SetScript("OnShow", function()
            RefreshAll()
            RefreshScannerFeed()
            -- Update LED from saved state
            local sdb = EnsureDB()
            local dets = (sdb.scanner and sdb.scanner.detections) or {}
            if refs.scanCount then
                refs.scanCount:SetText(
                    #dets > 0 and (GMT.Green(tostring(#dets)) .. GMT.Dim(" detected"))
                    or GMT.Dim("0 detected"))
            end
        end)

        RefreshAll()
        RefreshScannerFeed()
    end)

    if not ok then GMT.Err("Recruitment init failed: " .. tostring(err)) end
end

-- ============================================================
-- PHASE 15 -- V2 Recruitment Network
-- Appended to GMT_Recruitment_Init via post-hook
-- Class/role filter matrix . Smart keyword builder
-- Blacklist manager . Contact history browser
-- ============================================================
local function Phase15_Build(panel)
    local PW = GMT.PW  -- 960

    -- Phase 15 adds a sub-panel that overlays the bottom area of the
    -- Recruitment panel as a toggleable drawer anchored to the BOTTOM
    local drawerH = 190
    local drawer  = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    drawer:SetFrameStrata("DIALOG")
    drawer:SetFrameLevel(panel:GetFrameLevel() + 25)
    drawer:SetSize(PW - 16, drawerH)
    drawer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 30)
    drawer:SetBackdrop({
        bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    drawer:SetBackdropColor(0.06,0.045,0.025,0.985)
    drawer:SetBackdropBorderColor(GMT.U(GMT.C.brass))
    drawer:Hide()

    local dHead = drawer:CreateTexture(nil,"BACKGROUND")
    dHead:SetPoint("TOPLEFT",  drawer,"TOPLEFT",   3,-3)
    dHead:SetPoint("TOPRIGHT", drawer,"TOPRIGHT", -3,-3)
    dHead:SetHeight(24)
    dHead:SetColorTexture(GMT.U(GMT.C.cardHead))

    local dTitle = drawer:CreateFontString(nil,"OVERLAY","GameFontNormal")
    dTitle:SetPoint("TOPLEFT",drawer,"TOPLEFT",10,-8)
    dTitle:SetTextColor(GMT.U(GMT.C.txtTitle))
    dTitle:SetText("Recruitment Tools")

    --    Toggle button on main panel                   
    local toggleBtn = GMT.MBtn(panel,"^ Tools",72,18)
    toggleBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -12)
    toggleBtn:SetScript("OnClick",function()
        if drawer:IsShown() then
            drawer:Hide()
            toggleBtn:SetText("^ Tools")
        else
            drawer:Show()
            drawer:Raise()
            toggleBtn:SetText("v Tools")
        end
    end)

    --    INNER LAYOUT (3 columns inside drawer)        
    local DW    = PW - 16
    local col1W = 280
    local col2W = 310
    local col3W = DW - col1W - col2W - 16
    local CY    = -32   -- content start Y

    --    COL 1: Class / Role Filter Matrix             
    local c1 = drawer:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    c1:SetPoint("TOPLEFT",drawer,"TOPLEFT",8,CY-2)
    c1:SetTextColor(GMT.U(GMT.C.txtTitle))
    c1:SetText("Class / Role Filters")

    local CLASSES = {"WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST",
                     "DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","MONK",
                     "DRUID","DEMONHUNTER","EVOKER"}
    local classFilters = {}
    local filterFrame  = CreateFrame("Frame",nil,drawer)
    filterFrame:SetSize(col1W, drawerH-40)
    filterFrame:SetPoint("TOPLEFT",drawer,"TOPLEFT",8,CY-18)

    local cols2 = 4
    local bW, bH = 64, 14
    for i, cls in ipairs(CLASSES) do
        local col = (i-1) % cols2
        local row = math.floor((i-1) / cols2)
        local hex = GMT.ClassHex(cls)
        local btn = CreateFrame("Button",nil,filterFrame,"BackdropTemplate")
        btn:SetSize(bW, bH)
        btn:SetPoint("TOPLEFT",filterFrame,"TOPLEFT", col*(bW+2), -row*(bH+2))
        btn:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
            edgeFile="Interface/Tooltips/UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=6,insets={left=1,right=1,top=1,bottom=1}})
        btn:SetBackdropColor(0.08,0.06,0.04,0.95)
        btn:SetBackdropBorderColor(0.35,0.28,0.16,0.80)
        classFilters[cls] = false
        local fs = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        fs:SetAllPoints()
        fs:SetJustifyH("CENTER")
        fs:SetText(hex..cls:sub(1,4).."|r")
        fs:SetFontObject("GameFontHighlightSmall")
        btn:SetScript("OnClick",function()
            classFilters[cls] = not classFilters[cls]
            local active = classFilters[cls]
            btn:SetBackdropColor(active and 0.18 or 0.08, active and 0.22 or 0.06, 0.04, 0.95)
            btn:SetBackdropBorderColor(active and GMT.U(GMT.C.green) or 0.35,
                                       active and 0.65 or 0.28, 0.16, 0.90)
        end)
    end

    -- Apply filters button
    local applyFilters = GMT.MBtn(drawer,"Apply Class Filter",134,18)
    applyFilters:SetPoint("BOTTOMLEFT",drawer,"BOTTOMLEFT",8,8)
    applyFilters:SetScript("OnClick",function()
        local active = {}
        for cls, on in pairs(classFilters) do if on then active[cls]=true end end
        local count = 0
        for _ in pairs(active) do count=count+1 end
        if count == 0 then
            -- No filter active, reset
            if refs.RefreshResults then refs.RefreshResults() end
            return
        end
        -- Filter RM.results in place
        local fresh = {}
        for _, p in ipairs(RM.results or {}) do
            if active[p.class or ""] then table.insert(fresh, p) end
        end
        RM.results = fresh; RM.selectedResults = {}
        if refs.RefreshResults then refs.RefreshResults() end
    end)

    --    COL 2: Smart Keyword Builder                  
    local c2x = col1W + 12
    local c2 = drawer:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    c2:SetPoint("TOPLEFT",drawer,"TOPLEFT",c2x,CY-2)
    c2:SetTextColor(GMT.U(GMT.C.txtTitle))
    c2:SetText("Smart Keyword Builder")

    local KEYWORD_PRESETS = {
        { label="LFGuild",    kw="lf guild" },
        { label="LF<Raid>",   kw="lf raid guild" },
        { label="Heroic+",    kw="lf heroic guild" },
        { label="M+ Focused", kw="lf mythic+ guild" },
        { label="PvP Guild",  kw="lf pvp guild" },
        { label="Casual",     kw="lf casual guild" },
        { label="Guildless",  kw="guildless" },
        { label="No Guild",   kw="no guild" },
    }

    local kwBtnY = CY-20
    for i, preset in ipairs(KEYWORD_PRESETS) do
        local col = (i-1) % 2
        local row = math.floor((i-1) / 2)
        local kb = GMT.MBtn(drawer, preset.label, 134, 18)
        kb:SetPoint("TOPLEFT",drawer,"TOPLEFT", c2x + col*140, kwBtnY - row*22)
        local kw = preset.kw
        kb:SetScript("OnClick",function()
            if refs.query then
                local cur = refs.query:GetText() or ""
                if cur ~= "" then
                    refs.query:SetText(cur.." "..kw)
                else
                    refs.query:SetText(kw)
                end
            end
        end)
    end

    local clearKw = GMT.MBtn(drawer,"Clear Query",100,18)
    clearKw:SetPoint("BOTTOMLEFT",drawer,"BOTTOMLEFT",c2x,8)
    clearKw:SetScript("OnClick",function()
        if refs.query then refs.query:SetText("") end
    end)

    --    COL 3: Blacklist Manager                       
    local c3x = col1W + col2W + 16
    local c3 = drawer:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    c3:SetPoint("TOPLEFT",drawer,"TOPLEFT",c3x,CY-2)
    c3:SetTextColor(GMT.U(GMT.C.txtTitle))
    c3:SetText("Blacklist Manager")

    -- Scrollable blacklist display
    local blFrame = CreateFrame("Frame",nil,drawer,"BackdropTemplate")
    blFrame:SetSize(col3W-4, drawerH-72)
    blFrame:SetPoint("TOPLEFT",drawer,"TOPLEFT",c3x,CY-18)
    blFrame:SetBackdrop({bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    blFrame:SetBackdropColor(GMT.U(GMT.C.panelBg))
    blFrame:SetBackdropBorderColor(GMT.U(GMT.C.brass))

    local blSF = CreateFrame("ScrollFrame",nil,blFrame,"UIPanelScrollFrameTemplate")
    blSF:SetPoint("TOPLEFT",blFrame,"TOPLEFT",2,-2)
    blSF:SetSize(col3W-24, drawerH-76)
    local blContent = CreateFrame("Frame",nil,blSF)
    blContent:SetSize(col3W-24,20)
    blSF:SetScrollChild(blContent)

    local blRows = {}
    local selectedBL = nil

    local function RefreshBlacklist()
        local db = EnsureDB()
        local names = {}
        for name in pairs(db.blacklist or {}) do table.insert(names, name) end
        table.sort(names)
        for i, name in ipairs(names) do
            local r = blRows[i]
            if not r then
                r = CreateFrame("Button",nil,blContent)
                r:SetSize(col3W-28, 16)
                r:SetPoint("TOPLEFT",blContent,"TOPLEFT",0,-((i-1)*16))
                r.bg = r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints()
                r.fs = r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                r.fs:SetPoint("LEFT",r,"LEFT",4,0); r.fs:SetWidth(col3W-36)
                r.fs:SetJustifyH("LEFT")
                blRows[i] = r
            end
            local sel = (selectedBL == name)
            r.bg:SetColorTexture(sel and 0.25 or 0.07, sel and 0.06 or 0.05, 0.04, sel and 0.75 or (i%2==0 and 0.28 or 0.10))
            r.fs:SetText(GMT.Red("(N)").."  |cffbbbbbb"..name.."|r")
            r:Show()
            r:SetScript("OnClick",function() selectedBL=name; RefreshBlacklist() end)
        end
        for i=#names+1,#blRows do blRows[i]:Hide() end
        blContent:SetHeight(math.max(16,#names*16))
    end

    local removeBlBtn = GMT.MBtn(drawer,"Remove Selected",124,18)
    removeBlBtn:SetPoint("BOTTOMLEFT",drawer,"BOTTOMLEFT",c3x,8)
    removeBlBtn:SetScript("OnClick",function()
        if not selectedBL then return end
        local db = EnsureDB()
        db.blacklist[selectedBL] = nil
        selectedBL = nil
        RefreshBlacklist()
        if refs.RefreshResults then refs.RefreshResults() end
    end)

    local clearBlBtn = GMT.MBtn(drawer,"Clear All",80,18)
    clearBlBtn:SetPoint("LEFT",removeBlBtn,"RIGHT",6,0)
    clearBlBtn:SetScript("OnClick",function()
        local db = EnsureDB()
        db.blacklist = {}
        selectedBL = nil
        RefreshBlacklist()
    end)

    -- Refresh blacklist when drawer opens
    drawer:HookScript("OnShow",RefreshBlacklist)
end

-- Hook Phase 15 onto the existing Recruitment panel
local _origRecInit15 = GMT_Recruitment_Init
GMT_Recruitment_Init = function()
    _origRecInit15()
    local panel = GMT_GetPanel("Recruitment")
    if panel and not panel._phase15Built then
        panel._phase15Built = true
        Phase15_Build(panel)
    end
end
