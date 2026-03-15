-- ============================================================
-- GuildMasterTools  |  Modules/Options.lua  |  v3.6.3
-- Data-rich Settings / Addon Command Center
-- ============================================================
local _, GMT = ...

GMT.OPT = GMT.OPT or {}
local OPT = GMT.OPT

local refs = {}

local function Count(t)
    return type(t) == "table" and #t or 0
end

local function EnsureDB()
    GMT.DB.settings = GMT.DB.settings or {}
    local s = GMT.DB.settings

    if s.defaultTab == nil then s.defaultTab = "Home" end
    if s.openOnLogin == nil then s.openOnLogin = false end
    if s.lockWindow == nil then s.lockWindow = false end
    if s.uiScale == nil then s.uiScale = 1.0 end
    if s.alpha == nil then s.alpha = 1.0 end
    if s.enableSounds == nil then s.enableSounds = false end
    if s.debug == nil then s.debug = GMT.DEBUG and true or false end

    s.modules = s.modules or {}
    if s.modules.recruitment == nil then s.modules.recruitment = true end
    if s.modules.raidprep == nil then s.modules.raidprep = true end
    if s.modules.crafting == nil then s.modules.crafting = true end
    if s.modules.logistics == nil then s.modules.logistics = true end

    return s
end

local function Clamp(v, minv, maxv)
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function SetStatus(msg, kind)
    if not refs.status then return end
    refs.status:SetText(msg or "Settings ready.")
    if kind == "green" then
        refs.status:SetTextColor(GMT.U(GMT.C.green))
    elseif kind == "red" then
        refs.status:SetTextColor(GMT.U(GMT.C.red))
    else
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
    end
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

local function Label(parent, text, x, y, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if color then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    else
        fs:SetTextColor(GMT.U(GMT.C.txtDim))
    end
    fs:SetText(text or "")
    return fs
end

local function ValueLine(parent, key, x, y, width, valueWidth)
    local k = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    k:SetWidth(width or 90)
    k:SetJustifyH("LEFT")
    k:SetTextColor(GMT.U(GMT.C.txtDim))
    k:SetText(key)

    local v = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v:SetPoint("LEFT", k, "RIGHT", 6, 0)
    v:SetWidth(valueWidth or 180)
    v:SetJustifyH("LEFT")
    v:SetTextColor(GMT.U(GMT.C.txtBody))
    v:SetText("--")
    return v
end

local function Input(parent, x, y, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(w, h or 20)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function Check(parent, text, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local txt = cb.text or _G[(cb:GetName() or "") .. "Text"]
    if txt then
        txt:SetText(text)
        txt:SetTextColor(GMT.U(GMT.C.txtBody))
        txt:SetFontObject("GameFontHighlightSmall")
    end
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    return cb
end

local function ApplyFrameSettings()
    local s = EnsureDB()
    if not GMT_MainFrame then return end

    GMT_MainFrame:SetScale(tonumber(s.uiScale) or 1.0)
    GMT_MainFrame:SetAlpha(tonumber(s.alpha) or 1.0)
    GMT_MainFrame:SetMovable(not s.lockWindow)
    if s.lockWindow then
        GMT_MainFrame:RegisterForDrag()
    else
        GMT_MainFrame:RegisterForDrag("LeftButton")
    end
end

local function SaveValues()
    local s = EnsureDB()
    if refs.scale then
        s.uiScale = Clamp(tonumber(refs.scale:GetText()) or s.uiScale or 1.0, 0.70, 1.30)
        refs.scale:SetText(string.format("%.2f", s.uiScale))
    end
    if refs.alpha then
        s.alpha = Clamp(tonumber(refs.alpha:GetText()) or s.alpha or 1.0, 0.50, 1.00)
        refs.alpha:SetText(string.format("%.2f", s.alpha))
    end
    if refs.defaultTab then
        local t = tostring(refs.defaultTab:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then s.defaultTab = t end
    end
    ApplyFrameSettings()
    SetStatus("Settings saved.", "green")
end

local function ResetDefaults()
    GMT.DB.settings = nil
    local s = EnsureDB()
    GMT.DEBUG = s.debug and true or false
    if refs.debugToggle then refs.debugToggle:SetChecked(s.debug) end
    ApplyFrameSettings()
    SetStatus("Settings reset to defaults.", "green")
end

local function LoadValues()
    local s = EnsureDB()
    if refs.scale then refs.scale:SetText(string.format("%.2f", tonumber(s.uiScale) or 1.0)) end
    if refs.alpha then refs.alpha:SetText(string.format("%.2f", tonumber(s.alpha) or 1.0)) end
    if refs.defaultTab then refs.defaultTab:SetText(s.defaultTab or "Home") end
    if refs.openOnLogin then refs.openOnLogin:SetChecked(s.openOnLogin) end
    if refs.lockWindow then refs.lockWindow:SetChecked(s.lockWindow) end
    if refs.enableSounds then refs.enableSounds:SetChecked(s.enableSounds) end
    if refs.debugToggle then refs.debugToggle:SetChecked(s.debug and true or false) end
    if refs.modRecruitment then refs.modRecruitment:SetChecked(s.modules.recruitment) end
    if refs.modRaid then refs.modRaid:SetChecked(s.modules.raidprep) end
    if refs.modCrafting then refs.modCrafting:SetChecked(s.modules.crafting) end
    if refs.modLogistics then refs.modLogistics:SetChecked(s.modules.logistics) end
end

local function UpdateModuleToggles()
    SetStatus("Module toggles saved. Reload recommended for a clean tab refresh.", "green")
end

local function GuildCounts()
    local total, online = 0, 0
    if IsInGuild and IsInGuild() then
        total = GetNumGuildMembers() or 0
        for i = 1, total do
            local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline then online = online + 1 end
        end
    end
    return total, online
end

local function CountRaidRoster()
    local n = 0
    if IsInRaid and IsInRaid() then
        n = GetNumGroupMembers() or 0
    elseif IsInGroup and IsInGroup() then
        n = GetNumSubgroupMembers() + 1
    end
    return n
end

local function GetSnapshot()
    local db = GMT.DB or {}
    local totalGuild, onlineGuild = GuildCounts()
    local crafterCount = 0
    local recipeCount = 0
    if GMT.CF and GMT.CF.guildMap then
        crafterCount = #GMT.CF.guildMap
    end
    if GMT.CF and GMT.CF.guildRecipes then
        for _, recipes in pairs(GMT.CF.guildRecipes) do
            if type(recipes) == "table" then recipeCount = recipeCount + #recipes end
        end
    end

    return {
        version = GMT.VERSION or "?",
        player = UnitName("player") or "?",
        class = select(2, UnitClass("player")) or "?",
        level = UnitLevel("player") or 0,
        guild = GetGuildInfo("player") or "No guild",
        guildTotal = totalGuild,
        guildOnline = onlineGuild,
        raidRoster = CountRaidRoster(),
        defaultTab = (db.settings and db.settings.defaultTab) or "Home",
        scale = (db.settings and db.settings.uiScale) or 1.0,
        alpha = (db.settings and db.settings.alpha) or 1.0,
        debug = GMT.DEBUG and "ON" or "OFF",
        recruitment = Count(db.recruitment and db.recruitment.pipeline),
        events = Count(db.events and db.events.events),
        gatherers = Count(db.logistics and db.logistics.gatherers),
        logisticsCrafters = Count(db.logistics and db.logistics.crafters),
        trackedCrafts = Count(db.crafting and db.crafting.tracked),
        talentCrafters = crafterCount,
        cachedRecipes = recipeCount,
        perfProfiles = Count(db.raidPerf and db.raidPerf.profiles),
        perfRecruits = Count(db.raidPerf and db.raidPerf.recruits),
        bankLogs = Count(db.economy and db.economy.bankLog),
        goldLogs = Count(db.economy and db.economy.goldLog),
        syncLog = Count(db.sync and db.sync.log),
    }
end

local function RefreshLivePanel()
    if not refs.snapshotValues then return end
    local s = GetSnapshot()
    local v = refs.snapshotValues
    if v.version then v.version:SetText(s.version) end
    if v.player then v.player:SetText(string.format("%s  Lv%d  %s", s.player, s.level or 0, s.class or "?")) end
    if v.guild then v.guild:SetText(s.guild) end
    if v.guildRoster then v.guildRoster:SetText(string.format("%d total / %d online", s.guildTotal, s.guildOnline)) end
    if v.raidRoster then v.raidRoster:SetText(tostring(s.raidRoster)) end
    if v.defaultTab then v.defaultTab:SetText(s.defaultTab) end
    if v.frame then v.frame:SetText(string.format("Scale %.2f  |  Alpha %.2f", s.scale, s.alpha)) end
    if v.debug then v.debug:SetText(s.debug) end
    if v.moduleDataLeft then
        v.moduleDataLeft:SetText(table.concat({
            string.format("Recruitment: %d", s.recruitment),
            string.format("Events: %d", s.events),
            string.format("Logistics: %d gatherers, %d crafters", s.gatherers, s.logisticsCrafters),
            string.format("Guild Professions: %d crafters, %d recipes", s.talentCrafters, s.cachedRecipes),
            string.format("Tracked Crafts: %d", s.trackedCrafts),
        }, "\n"))
    end
    if v.moduleDataRight then
        v.moduleDataRight:SetText(table.concat({
            string.format("Raid Perf: %d profiles, %d recruits", s.perfProfiles, s.perfRecruits),
            string.format("Economy: %d bank logs, %d gold logs", s.bankLogs, s.goldLogs),
            string.format("Sync: %d entries", s.syncLog),
        }, "\n"))
    end
end

local function PrintSnapshotToChat()
    local s = GetSnapshot()
    GMT.Print(string.format(
        "Snapshot | Version %s | Guild %s (%d/%d online) | Recruits %d | Events %d | Guild Professions %d crafters | Recipes %d | Perf %d/%d | Economy %d/%d",
        s.version, s.guild, s.guildOnline, s.guildTotal, s.recruitment, s.events, s.talentCrafters, s.cachedRecipes, s.perfProfiles, s.perfRecruits, s.bankLogs, s.goldLogs
    ))
    SetStatus("Addon snapshot printed to chat.", "green")
end

local function ResetWindowPosition()
    if not GMT_MainFrame then return end
    GMT_MainFrame:ClearAllPoints()
    GMT_MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    SetStatus("Window recentered.", "green")
end

local function ToggleDebug()
    local s = EnsureDB()
    s.debug = not s.debug
    GMT.DEBUG = s.debug
    if refs.debugToggle then refs.debugToggle:SetChecked(s.debug) end
    RefreshLivePanel()
    SetStatus("Debug " .. (s.debug and "enabled." or "disabled."), "green")
end

local function BuildDiagnosticsText()
    local s = GetSnapshot()
    local lines = {
        "=== GUILDMASTERTOOLS DIAGNOSTICS ===",
        string.format("Version: %s", s.version),
        string.format("Player: %s", s.player),
        string.format("Guild: %s", s.guild),
        string.format("Guild roster: %d total / %d online", s.guildTotal, s.guildOnline),
        string.format("Default tab: %s", s.defaultTab),
        string.format("Frame: scale %.2f / alpha %.2f", s.scale, s.alpha),
        string.format("Debug: %s", s.debug),
        "",
        "-- Module Data --",
        string.format("Recruitment pipeline: %d", s.recruitment),
        string.format("Events: %d", s.events),
        string.format("Logistics gatherers: %d", s.gatherers),
        string.format("Logistics crafters: %d", s.logisticsCrafters),
        string.format("Talent map crafters: %d", s.talentCrafters),
        string.format("Cached recipes: %d", s.cachedRecipes),
        string.format("Tracked crafts: %d", s.trackedCrafts),
        string.format("Raid perf profiles: %d", s.perfProfiles),
        string.format("Raid perf recruits: %d", s.perfRecruits),
        string.format("Economy bank logs: %d", s.bankLogs),
        string.format("Economy gold logs: %d", s.goldLogs),
        string.format("Sync log entries: %d", s.syncLog),
        "",
        "Slash commands:",
        "/gmt  /gmt toggle  /gmt debug  /gmt reset  /gmt reload",
    }
    return table.concat(lines, "\n")
end


local function OutputBoxHeight(box)
    if not box then return 80 end
    local num = 1
    if box.GetNumLines then
        local ok, lines = pcall(box.GetNumLines, box)
        if ok and type(lines) == "number" and lines > 0 then
            num = lines
        end
    end
    local _, size = box:GetFont()
    size = tonumber(size) or 12
    return math.max(80, math.floor(num * (size + 3) + 16))
end

local function SetOutput(text)
    if not refs.outputBox then return end
    refs.outputBox:SetText(text or "")
    refs.outputBox:SetCursorPosition(0)
    refs.outputBox:HighlightText(0, 0)
    refs.outputBox:SetHeight(OutputBoxHeight(refs.outputBox))
    if refs.outputScroll then
        refs.outputScroll:SetVerticalScroll(0)
        if refs.outputScroll.UpdateScrollChildRect then refs.outputScroll:UpdateScrollChildRect() end
    end
end

local function ExportRecruitment()
    local db = GMT.DB.recruitment
    if not db or not db.pipeline then SetOutput("No recruitment data."); return end
    local lines = { "=== RECRUITMENT PIPELINE ===" }
    for _, p in ipairs(db.pipeline) do
        lines[#lines+1] = string.format("%-20s  %-10s  %-12s  %s",
            GMT.Short(p.name or "?"), p.status or "Prospect",
            p.class or "?", p.note or "")
    end
    lines[#lines+1] = "Total: " .. #db.pipeline .. " recruits"
    SetOutput(table.concat(lines, "\n"))
end

local function ExportLogistics()
    local db = GMT.DB.logistics
    if not db then SetOutput("No logistics data."); return end
    local lines = { "=== LOGISTICS SUPPLY STATUS ===" }
    if db.stockPlan then
        for k, v in pairs(db.stockPlan) do
            lines[#lines+1] = string.format("  %-14s  target: %d", k, v)
        end
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "=== GATHERERS ==="
    for _, g in ipairs(db.gatherers or {}) do
        lines[#lines+1] = string.format("  %-20s  %s", g.name or "?", g.materials or "")
    end
    lines[#lines+1] = "=== CRAFTERS ==="
    for _, c in ipairs(db.crafters or {}) do
        lines[#lines+1] = string.format("  %-20s  %-14s  %s", c.name or "?", c.profession or "", c.recipes or "")
    end
    SetOutput(table.concat(lines, "\n"))
end

local function ExportEvents()
    local db = GMT.DB.events
    if not db or not db.events then SetOutput("No event data."); return end
    local lines = { "=== GUILD EVENTS ===" }
    local sorted = {}
    for _, ev in ipairs(db.events) do table.insert(sorted, ev) end
    table.sort(sorted, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    for _, ev in ipairs(sorted) do
        local yes = 0
        for _, r in ipairs(ev.rsvp or {}) do if r.status == "yes" then yes = yes + 1 end end
        lines[#lines+1] = string.format("%-30s  %-10s  %s  RSVP: %d",
            ev.name or "?", ev.type or "other",
            ev.date and (ev.date .. " " .. (ev.evtime or "")) or "?", yes)
    end
    lines[#lines+1] = "Total: " .. #sorted .. " events"
    SetOutput(table.concat(lines, "\n"))
end

local function ExportPerfScores()
    local db = GMT.DB.raidPerf
    if not db then SetOutput("No raid performance data."); return end
    local lines = { "=== RAID PERFORMANCE SCORES ===" }
    if GMT.PF and GMT.PF.rosterScores then
        lines[#lines+1] = "-- Roster --"
        for _, e in ipairs(GMT.PF.rosterScores) do
            lines[#lines+1] = string.format("  %-20s  %-8s  %3d/100", e.short, e.role or "?", e.score or 0)
        end
    end
    if db.recruits and #db.recruits > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = "-- Scored Recruits --"
        for _, r in ipairs(db.recruits) do
            lines[#lines+1] = string.format("  %-20s  %-8s  %3d/100", r.name, r.role or "?", r.score or 0)
        end
    end
    SetOutput(table.concat(lines, "\n"))
end

local function ExportAll()
    local db = GMT.DB
    local parts = {}
    parts[#parts+1] = BuildDiagnosticsText()
    parts[#parts+1] = ""
    parts[#parts+1] = "=== RECRUITMENT (" .. #((db.recruitment and db.recruitment.pipeline) or {}) .. " in pipeline) ==="
    for _, p in ipairs((db.recruitment and db.recruitment.pipeline) or {}) do
        parts[#parts+1] = "  " .. GMT.Short(p.name or "?") .. "  " .. (p.status or "") .. "  " .. (p.class or "")
    end
    parts[#parts+1] = ""
    parts[#parts+1] = "=== EVENTS (" .. #((db.events and db.events.events) or {}) .. " total) ==="
    for _, ev in ipairs((db.events and db.events.events) or {}) do
        parts[#parts+1] = "  " .. (ev.name or "?") .. "  " .. (ev.date or "") .. " " .. (ev.evtime or "")
    end
    parts[#parts+1] = ""
    parts[#parts+1] = "=== LOGISTICS ==="
    parts[#parts+1] = "  Gatherers: " .. #((db.logistics and db.logistics.gatherers) or {})
    parts[#parts+1] = "  Crafters: " .. #((db.logistics and db.logistics.crafters) or {})
    parts[#parts+1] = ""
    local pf = (db.raidPerf and db.raidPerf.baseline) or {}
    parts[#parts+1] = "=== PERF BASELINES ==="
    parts[#parts+1] = string.format("  Tank=%s  Healer=%s  Damage=%s", tostring(pf.TANK or 0), tostring(pf.HEALER or 0), tostring(pf.DAMAGER or 0))
    SetOutput(table.concat(parts, "\n"))
end


local function EnsureBlizzardOptionsCategory()
    if GMT._blizzardOptionsRegistered then return end
    GMT._blizzardOptionsRegistered = true

    local s = EnsureDB()
    local panel = CreateFrame("Frame", "GuildMasterToolsBlizzardOptionsPanel", UIParent)
    panel.name = "GuildMasterTools"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GuildMasterTools")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(620)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Core addon settings for the in-game AddOns settings screen. The full dashboard remains available inside GuildMasterTools.")

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(170, 24)
    openBtn:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    openBtn:SetText("Open GuildMasterTools")
    openBtn:SetScript("OnClick", function()
        if GMT_ShowTab then GMT_ShowTab("Settings") end
        if GMT_MainFrame then GMT_MainFrame:Show() end
    end)

    local reloadBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reloadBtn:SetSize(120, 24)
    reloadBtn:SetPoint("LEFT", openBtn, "RIGHT", 8, 0)
    reloadBtn:SetText("/reload UI")
    reloadBtn:SetScript("OnClick", function() GMT.ReloadNow("Reloading UI...") end)

    local defaultLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    defaultLbl:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -22)
    defaultLbl:SetText("Default Tab")

    local defaultTab = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    defaultTab:SetAutoFocus(false)
    defaultTab:SetSize(150, 20)
    defaultTab:SetPoint("TOPLEFT", defaultLbl, "BOTTOMLEFT", 0, -8)
    defaultTab:SetTextInsets(6, 6, 2, 2)

    local scaleLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scaleLbl:SetPoint("LEFT", defaultTab, "RIGHT", 24, 10)
    scaleLbl:SetText("UI Scale")

    local scaleBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    scaleBox:SetAutoFocus(false)
    scaleBox:SetSize(60, 20)
    scaleBox:SetPoint("TOPLEFT", scaleLbl, "BOTTOMLEFT", 0, -8)
    scaleBox:SetTextInsets(6, 6, 2, 2)

    local alphaLbl = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    alphaLbl:SetPoint("LEFT", scaleBox, "RIGHT", 24, 10)
    alphaLbl:SetText("Alpha")

    local alphaBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    alphaBox:SetAutoFocus(false)
    alphaBox:SetSize(60, 20)
    alphaBox:SetPoint("TOPLEFT", alphaLbl, "BOTTOMLEFT", 0, -8)
    alphaBox:SetTextInsets(6, 6, 2, 2)

    local openCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    openCB:SetPoint("TOPLEFT", defaultTab, "BOTTOMLEFT", -4, -18)
    openCB.text:SetText("Open on login")

    local soundCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCB:SetPoint("LEFT", openCB, "RIGHT", 140, 0)
    soundCB.text:SetText("Enable sounds")

    local debugCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    debugCB:SetPoint("LEFT", soundCB, "RIGHT", 140, 0)
    debugCB.text:SetText("Debug mode")

    local lockCB = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", openCB, "BOTTOMLEFT", 0, -8)
    lockCB.text:SetText("Lock main window")

    local summary = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 4, -22)
    summary:SetWidth(700)
    summary:SetJustifyH("LEFT")
    summary:SetJustifyV("TOP")

    local function refresh()
        s = EnsureDB()
        defaultTab:SetText(s.defaultTab or "Home")
        scaleBox:SetText(string.format("%.2f", tonumber(s.uiScale) or 1.0))
        alphaBox:SetText(string.format("%.2f", tonumber(s.alpha) or 1.0))
        openCB:SetChecked(s.openOnLogin)
        soundCB:SetChecked(s.enableSounds)
        debugCB:SetChecked(s.debug)
        lockCB:SetChecked(s.lockWindow)
        local total, online = GuildCounts()
        summary:SetText(string.format("Version: %s\nGuild: %s (%d/%d online)\nRaid members: %d\nDefault tab: %s", tostring(GMT.VERSION), GetGuildInfo("player") or "No guild", online, total, CountRaidRoster(), s.defaultTab or "Home"))
    end

    local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applyBtn:SetSize(100, 24)
    applyBtn:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -16)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        local s2 = EnsureDB()
        local t = tostring(defaultTab:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then s2.defaultTab = t end
        s2.uiScale = Clamp(tonumber(scaleBox:GetText()) or s2.uiScale or 1.0, 0.70, 1.30)
        s2.alpha = Clamp(tonumber(alphaBox:GetText()) or s2.alpha or 1.0, 0.50, 1.00)
        s2.openOnLogin = openCB:GetChecked() and true or false
        s2.enableSounds = soundCB:GetChecked() and true or false
        s2.debug = debugCB:GetChecked() and true or false
        s2.lockWindow = lockCB:GetChecked() and true or false
        GMT.DEBUG = s2.debug and true or false
        ApplyFrameSettings()
        refresh()
    end)

    panel:SetScript("OnShow", refresh)

    if type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
    end
end

function GMT_Options_Init()
    local ok, err = pcall(function()
        local panel = GMT_GetPanel("Settings")
        if not panel or panel._settingsBuilt then return end
        panel._settingsBuilt = true

        EnsureDB()
        EnsureBlizzardOptionsCategory()

        GMT.Header(panel, "Addon Command Center", 14, -10)
        GMT.Label(panel, "Startup controls, module toggles, live metrics, exports, and diagnostics", 16, -34)
        GMT.HLine(panel, 8, -48, GMT.PW - 16)

        local general = MakeSection(panel, "General", 8, -58, 226, 154)
        local frameBox = MakeSection(panel, "Frame", 242, -58, 196, 154)
        local modules = MakeSection(panel, "Module Visibility", 446, -58, 238, 154)
        local overview = MakeSection(panel, "Live Addon Snapshot", 692, -58, 252, 154)

        local actions = MakeSection(panel, "Quick Actions", 8, -220, 316, 108)
        local commands = MakeSection(panel, "Slash Commands", 332, -220, 284, 108)
        local moduleData = MakeSection(panel, "Module Data", 624, -220, 320, 108)

        local exportBox = MakeSection(panel, "Data / Diagnostics Center", 8, -336, 936, 158)

        Label(general, "Default Tab", 12, -30)
        refs.defaultTab = Input(general, 12, -46, 120, 20)
        Label(general, "Examples: Home, Members, Guild Professions", 12, -72)

        refs.openOnLogin = Check(general, "Open on login", 12, -98,
            function() return EnsureDB().openOnLogin end,
            function(v) EnsureDB().openOnLogin = v; SetStatus("Open on login updated.", "green") end)

        refs.enableSounds = Check(general, "Enable sounds", 120, -98,
            function() return EnsureDB().enableSounds end,
            function(v) EnsureDB().enableSounds = v; SetStatus("Sound preference updated.", "green") end)

        refs.debugToggle = Check(general, "Debug mode", 12, -124,
            function() return EnsureDB().debug end,
            function(v) EnsureDB().debug = v; GMT.DEBUG = v; RefreshLivePanel(); SetStatus("Debug preference updated.", "green") end)

        Label(frameBox, "UI Scale", 12, -30)
        refs.scale = Input(frameBox, 12, -46, 70, 20)
        Label(frameBox, "Alpha", 92, -30)
        refs.alpha = Input(frameBox, 92, -46, 70, 20)
        refs.lockWindow = Check(frameBox, "Lock window", 12, -98,
            function() return EnsureDB().lockWindow end,
            function(v) EnsureDB().lockWindow = v; ApplyFrameSettings(); SetStatus("Window lock updated.", "green") end)
        local applyFrame = GMT.MBtn(frameBox, "Apply", 72, 22)
        applyFrame:SetPoint("TOPLEFT", frameBox, "TOPLEFT", 112, -74)
        applyFrame:SetScript("OnClick", function() SaveValues(); RefreshLivePanel() end)

        refs.modRecruitment = Check(modules, "Recruitment tab", 12, -30,
            function() return EnsureDB().modules.recruitment end,
            function(v) EnsureDB().modules.recruitment = v; UpdateModuleToggles() end)
        refs.modRaid = Check(modules, "Raid Prep tab", 12, -56,
            function() return EnsureDB().modules.raidprep end,
            function(v) EnsureDB().modules.raidprep = v; UpdateModuleToggles() end)
        refs.modCrafting = Check(modules, "Guild Professions tab", 12, -82,
            function() return EnsureDB().modules.crafting end,
            function(v) EnsureDB().modules.crafting = v; UpdateModuleToggles() end)
        refs.modLogistics = Check(modules, "Logistics tab", 12, -108,
            function() return EnsureDB().modules.logistics end,
            function(v) EnsureDB().modules.logistics = v; UpdateModuleToggles() end)
        Label(modules, "Toggle-heavy changes may need /reload.", 12, -134)

        refs.snapshotValues = {}
        refs.snapshotValues.version = ValueLine(overview, "Version", 12, -30, 78)
        refs.snapshotValues.player = ValueLine(overview, "Player", 12, -48, 78)
        refs.snapshotValues.guild = ValueLine(overview, "Guild", 12, -66, 78)
        refs.snapshotValues.guildRoster = ValueLine(overview, "Roster", 12, -84, 78)
        refs.snapshotValues.raidRoster = ValueLine(overview, "Raid", 12, -102, 78)
        refs.snapshotValues.defaultTab = ValueLine(overview, "Startup", 12, -120, 78)
        refs.snapshotValues.frame = ValueLine(overview, "Frame", 12, -138, 78)
        refs.snapshotValues.debug = ValueLine(overview, "Debug", 126, -138, 60)

        local saveBtn = GMT.MBtn(actions, "Save", 70, 24)
        saveBtn:SetPoint("TOPLEFT", actions, "TOPLEFT", 14, -34)
        saveBtn:SetScript("OnClick", function() SaveValues(); RefreshLivePanel() end)

        local resetBtn = GMT.MBtn(actions, "Defaults", 78, 24)
        resetBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
        resetBtn:SetScript("OnClick", function() ResetDefaults(); LoadValues(); RefreshLivePanel() end)

        local reloadBtn = GMT.MBtn(actions, "Reload", 76, 24)
        reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
        reloadBtn:SetScript("OnClick", function()
            SaveValues()
            SetStatus("Reloading UI...", "green")
            GMT.ReloadNow("Reloading UI...")
        end)

        local homeBtn = GMT.MBtn(actions, "Home", 70, 22)
        homeBtn:SetPoint("TOPLEFT", actions, "TOPLEFT", 14, -66)
        homeBtn:SetScript("OnClick", function() if GMT_ShowTab then GMT_ShowTab("Home") end end)

        local centerBtn = GMT.MBtn(actions, "Center", 78, 22)
        centerBtn:SetPoint("LEFT", homeBtn, "RIGHT", 8, 0)
        centerBtn:SetScript("OnClick", ResetWindowPosition)

        local dbgBtn = GMT.MBtn(actions, "Debug", 76, 22)
        dbgBtn:SetPoint("LEFT", centerBtn, "RIGHT", 8, 0)
        dbgBtn:SetScript("OnClick", ToggleDebug)

        local c1 = commands:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c1:SetPoint("TOPLEFT", commands, "TOPLEFT", 14, -28)
        c1:SetJustifyH("LEFT")
        c1:SetWidth(252)
        c1:SetTextColor(GMT.U(GMT.C.txtBody))
        c1:SetText("/gmt  opens addon\n/gmt toggle  show/hide\n/gmt reload  full UI reload")

        local c2 = commands:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c2:SetPoint("TOPLEFT", commands, "TOPLEFT", 14, -70)
        c2:SetJustifyH("LEFT")
        c2:SetWidth(252)
        c2:SetTextColor(GMT.U(GMT.C.txtBody))
        c2:SetText("/gmt debug  toggle debug\n/gmt reset  wipe saved data\n/guildmaster  alternate command")

        refs.snapshotValues.moduleDataLeft = moduleData:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.snapshotValues.moduleDataLeft:SetPoint("TOPLEFT", moduleData, "TOPLEFT", 12, -30)
        refs.snapshotValues.moduleDataLeft:SetWidth(174)
        refs.snapshotValues.moduleDataLeft:SetJustifyH("LEFT")
        refs.snapshotValues.moduleDataLeft:SetJustifyV("TOP")
        refs.snapshotValues.moduleDataLeft:SetSpacing(4)
        refs.snapshotValues.moduleDataLeft:SetTextColor(GMT.U(GMT.C.txtBody))

        refs.snapshotValues.moduleDataRight = moduleData:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.snapshotValues.moduleDataRight:SetPoint("TOPLEFT", moduleData, "TOPLEFT", 194, -30)
        refs.snapshotValues.moduleDataRight:SetWidth(112)
        refs.snapshotValues.moduleDataRight:SetJustifyH("LEFT")
        refs.snapshotValues.moduleDataRight:SetJustifyV("TOP")
        refs.snapshotValues.moduleDataRight:SetSpacing(4)
        refs.snapshotValues.moduleDataRight:SetTextColor(GMT.U(GMT.C.txtBody))

        local outBg = CreateFrame("Frame", nil, exportBox, "BackdropTemplate")
        outBg:SetSize(676, 88)
        outBg:SetPoint("TOPLEFT", exportBox, "TOPLEFT", 10, -32)
        outBg:SetBackdrop({
            bgFile="Interface/DialogFrame/UI-DialogBox-Background-Dark",
            edgeFile="Interface/Tooltips/UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=8, insets={left=2,right=2,top=2,bottom=2},
        })
        outBg:SetBackdropColor(GMT.U(GMT.C.panelBg))
        outBg:SetBackdropBorderColor(GMT.U(GMT.C.brass))

        local outScroll = CreateFrame("ScrollFrame", nil, outBg, "UIPanelScrollFrameTemplate")
        outScroll:SetPoint("TOPLEFT", outBg, "TOPLEFT", 4, -4)
        outScroll:SetPoint("BOTTOMRIGHT", outBg, "BOTTOMRIGHT", -26, 4)
        refs.outputScroll = outScroll

        refs.outputBox = CreateFrame("EditBox", nil, outScroll)
        refs.outputBox:SetMultiLine(true)
        refs.outputBox:SetAutoFocus(false)
        refs.outputBox:SetFontObject("GameFontHighlightSmall")
        refs.outputBox:SetTextInsets(4, 4, 4, 4)
        refs.outputBox:SetWidth(640)
        refs.outputBox:SetJustifyH("LEFT")
        refs.outputBox:SetJustifyV("TOP")
        refs.outputBox:SetScript("OnEscapePressed", refs.outputBox.ClearFocus)
        refs.outputBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
            if refs.outputScroll and refs.outputScroll.UpdateScrollChildRect then
                refs.outputScroll:UpdateScrollChildRect()
            end
            if refs.outputScroll and refs.outputScroll.ScrollToVertical then
                refs.outputScroll:ScrollToVertical(y)
            elseif refs.outputScroll then
                local cur = refs.outputScroll:GetVerticalScroll() or 0
                local max = math.max(0, (self:GetHeight() or 0) - (refs.outputScroll:GetHeight() or 0))
                if y < cur then
                    refs.outputScroll:SetVerticalScroll(y)
                elseif y + h > cur + (refs.outputScroll:GetHeight() or 0) then
                    refs.outputScroll:SetVerticalScroll(math.min(max, y + h - (refs.outputScroll:GetHeight() or 0)))
                end
            end
        end)
        refs.outputBox:SetScript("OnTextChanged", function(self)
            self:SetWidth(640)
            self:SetHeight(OutputBoxHeight(self))
            if refs.outputScroll and refs.outputScroll.UpdateScrollChildRect then
                refs.outputScroll:UpdateScrollChildRect()
            end
        end)
        outScroll:SetScrollChild(refs.outputBox)
        refs.outputBox:SetPoint("TOPLEFT", outScroll, "TOPLEFT", 0, 0)
        C_Timer.After(0, function()
            if refs.outputBox then
                refs.outputBox:SetTextColor(0.86, 0.82, 0.68, 1.0)
                refs.outputBox:SetHeight(OutputBoxHeight(refs.outputBox))
            end
            if refs.outputScroll and refs.outputScroll.UpdateScrollChildRect then
                refs.outputScroll:UpdateScrollChildRect()
            end
        end)

        local btnDefs = {
            { label="Summary",    fn=function() SetOutput(BuildDiagnosticsText()) end },
            { label="Recruit",    fn=ExportRecruitment },
            { label="Logistics",  fn=ExportLogistics },
            { label="Events",     fn=ExportEvents },
            { label="Raid Perf",  fn=ExportPerfScores },
            { label="Export All", fn=ExportAll },
        }
        for i, bd in ipairs(btnDefs) do
            local btn = GMT.MBtn(exportBox, bd.label, 78, 22)
            local row = (i > 3) and 1 or 0
            local col = ((i - 1) % 3)
            btn:SetPoint("TOPLEFT", exportBox, "TOPLEFT", 694 + col * 80, -34 - row * 28)
            btn:SetScript("OnClick", bd.fn)
        end

        local selectAllBtn = GMT.MBtn(exportBox, "Select Text", 98, 18)
        selectAllBtn:SetPoint("BOTTOMLEFT", exportBox, "BOTTOMLEFT", 10, 8)
        selectAllBtn:SetScript("OnClick", function()
            refs.outputBox:SetFocus()
            refs.outputBox:HighlightText()
        end)

        local chatBtn = GMT.MBtn(exportBox, "Print", 78, 18)
        chatBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 8, 0)
        chatBtn:SetScript("OnClick", PrintSnapshotToChat)

        refs.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refs.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
        refs.status:SetTextColor(GMT.U(GMT.C.amber))
        refs.status:SetText("Settings ready.")

        panel:SetScript("OnShow", function()
            LoadValues()
            ApplyFrameSettings()
            RefreshLivePanel()
            SetOutput(BuildDiagnosticsText())
        end)

        LoadValues()
        ApplyFrameSettings()
        RefreshLivePanel()
        SetOutput(BuildDiagnosticsText())
    end)

    if not ok and GMT and GMT.Err then
        GMT.Err("Settings init failed: " .. tostring(err))
    end
end
