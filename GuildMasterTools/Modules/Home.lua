-- ============================================================
-- GuildMaster Tools  |  Modules/Home.lua  |  v4.3.0
-- Dashboard -- fully populated live data, no gears, no phase refs
-- ============================================================
local _, GMT = ...

local LOGO = "Interface/AddOns/GuildMasterTools/Media/logo"
local H    = {}   -- live ref table

-- ============================================================
-- HELPERS
-- ============================================================
local function StripColor(s)
    -- Remove |cXXXXXXXX....|r and |r sequences from guild name
    if not s then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function GuildCounts()
    local total, online = GetNumGuildMembers() or 0, 0
    for i = 1, total do
        local _,_,_,_,_,_,_,_, isOnline = GetGuildRosterInfo(i)
        if isOnline then online = online + 1 end
    end
    return total, online
end

local function GroupInfo()
    if not IsInRaid() and not IsInGroup() then return 0,0,0,0,false end
    local inRaid = IsInRaid()
    local size   = GetNumGroupMembers() or 0
    local t,h,d = 0,0,0
    local pfx    = inRaid and "raid" or "party"
    for i = 1, size do
        local r = UnitGroupRolesAssigned(pfx..i)
        if r=="TANK" then t=t+1 elseif r=="HEALER" then h=h+1 elseif r=="DAMAGER" then d=d+1 end
    end
    if not inRaid then
        local r = UnitGroupRolesAssigned("player")
        if r=="TANK" then t=t+1 elseif r=="HEALER" then h=h+1 elseif r=="DAMAGER" then d=d+1 end
        size = size + 1
    end
    return size, t, h, d, inRaid
end

local function CopperToGoldStr(c)
    c = math.abs(c or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    if g > 0 then return "|cffffd700"..g.."g|r |cffaaaaaa"..s.."s|r" end
    if s > 0 then return "|cffaaaaaa"..s.."s|r" end
    return GMT.Dim("0g")
end

local function NextEvent()
    local db = GMT.DB.events
    if not db or not db.events then return nil end
    local now = time()
    local best, bestTs = nil, math.huge
    for _, ev in ipairs(db.events) do
        if (ev.ts or 0) > now and (ev.ts or 0) < bestTs then
            best = ev; bestTs = ev.ts
        end
    end
    return best
end

local function FormatCountdown(ts)
    local diff = ts - time()
    if diff < 0    then return GMT.Red("Now") end
    if diff < 3600 then return GMT.Green(math.floor(diff/60).."m") end
    if diff < 86400 then return GMT.Amber(math.floor(diff/3600).."h "..math.floor((diff%3600)/60).."m") end
    return GMT.Dim(math.floor(diff/86400).."d")
end

local function TopKey(tbl)
    local bestK, bestV = '--', 0
    for k,v in pairs(tbl or {}) do if v > bestV then bestK, bestV = k, v end end
    return bestK, bestV
end

local function GuildSnapshot()
    local classCounts, rankCounts = {}, {}
    local newestOffline = nil
    local total = GetNumGuildMembers() or 0
    for i=1,total do
        local name, rank, rankIndex, level, class, zone, note, officerNote, online = GetGuildRosterInfo(i)
        if name then
            classCounts[class or '?'] = (classCounts[class or '?'] or 0) + 1
            rankCounts[rank or '?'] = (rankCounts[rank or '?'] or 0) + 1
            if not online and not newestOffline then newestOffline = GMT.Short(name) end
        end
    end
    return classCounts, rankCounts, newestOffline or '--'
end

-- ============================================================
-- REFRESH -- all live data
-- ============================================================
local function Refresh()
    if not H.ready then return end

    --    Guild Status                                      
    local rawGuild = GetGuildInfo("player") or "No Guild"
    local guild    = StripColor(rawGuild)
    local inGuild  = IsInGuild()
    local total, onl = GuildCounts()

    H.v_guild:SetText(inGuild and guild or GMT.Dim("Not in a guild"))
    H.v_total:SetText(tostring(total))
    H.v_online:SetText(onl > 0 and GMT.Green(tostring(onl)) or GMT.Grey("0"))
    H.v_offline:SetText(GMT.Grey(tostring(math.max(0, total - onl))))

    --    Raid / Group                                       
    local gs,tk,hl,dp,inRaid = GroupInfo()
    if gs == 0 then
        H.v_gtype:SetText(GMT.Dim("Not in group"))
        H.v_gsize:SetText(GMT.Dim("--"))
        H.v_tanks:SetText(GMT.Dim("--"))
        H.v_heals:SetText(GMT.Dim("--"))
        H.v_dps:SetText(GMT.Dim("--"))
    else
        H.v_gtype:SetText(inRaid and GMT.Amber("Raid") or GMT.Green("Party"))
        H.v_gsize:SetText(GMT.Gold(tostring(gs)))
        H.v_tanks:SetText("|cff5599ff"..tk.."|r")
        H.v_heals:SetText("|cff44ee88"..hl.."|r")
        H.v_dps:SetText("|cffff9944"..dp.."|r")
    end

    --    Recruitment                                        
    local pipeline = (GMT.DB.recruitment and GMT.DB.recruitment.pipeline) or {}
    H.v_recruits:SetText(#pipeline > 0 and GMT.Green(tostring(#pipeline)) or GMT.Dim("0"))

    local rProspect, rMessaged, rInvited = 0, 0, 0
    for _, p in ipairs(pipeline) do
        if     p.status == "Prospect"  then rProspect = rProspect + 1
        elseif p.status == "Messaged"  then rMessaged = rMessaged + 1
        elseif p.status == "Invited"   then rInvited  = rInvited  + 1
        end
    end
    H.v_recBreak:SetText(
        GMT.Dim("Prospect:")..rProspect.."  "..
        GMT.Amber("Msg:")..rMessaged.."  "..
        GMT.Green("Inv:")..rInvited)

    --    Economy / Bank                                     
    local copper = GetGuildBankMoney and GetGuildBankMoney() or 0
    H.v_bankGold:SetText(copper > 0 and CopperToGoldStr(copper) or GMT.Dim("Open bank to read"))

    local contribs = 0
    if GMT.EC and GMT.EC.contribs then contribs = #GMT.EC.contribs end
    H.v_contribs:SetText(contribs > 0 and GMT.Green(tostring(contribs)) or GMT.Dim("0"))

    -- Bank item count
    local itemCnt = (GMT.EC and GMT.EC.bankItems and #GMT.EC.bankItems) or 0
    H.v_bankItems:SetText(itemCnt > 0 and GMT.Amber(tostring(itemCnt)) or GMT.Dim("--"))

    --    Logistics                                          
    local shortages, stocked = 0, 0
    if GMT.LX and GMT.LX.supplies then
        for _, e in ipairs(GMT.LX.supplies) do
            local need = tonumber(e.need or 0) or 0
            if need > 0 then
                if e.total >= need then stocked = stocked + 1 else shortages = shortages + 1 end
            end
        end
    end
    H.v_shortages:SetText(shortages > 0 and GMT.Red(tostring(shortages)) or GMT.Green("0"))
    H.v_stocked:SetText(GMT.Green(tostring(stocked)))
    local gatherers = (GMT.DB.logistics and GMT.DB.logistics.gatherers and #GMT.DB.logistics.gatherers) or 0
    local crafters  = (GMT.DB.logistics and GMT.DB.logistics.crafters  and #GMT.DB.logistics.crafters)  or 0
    H.v_gatherers:SetText(gatherers > 0 and GMT.Amber(tostring(gatherers)) or GMT.Dim("0"))
    H.v_crafters:SetText(crafters  > 0 and GMT.Amber(tostring(crafters))  or GMT.Dim("0"))

    local classCounts, rankCounts, newestOffline = GuildSnapshot()
    local topClass, topClassCount = TopKey(classCounts)
    local _, tanks, heals, dps = GroupInfo()
    if H.v_nextEvent then H.v_nextEvent:SetText(GMT.Amber(string.format('%s (%d)', GMT.Clip(topClass, 12), topClassCount or 0))) end
    if H.v_eventIn then H.v_eventIn:SetText(string.format('T:%d H:%d D:%d', tanks or 0, heals or 0, dps or 0)) end
    if H.v_eventRSVP then H.v_eventRSVP:SetText('Offline Lead: ' .. GMT.Clip(newestOffline, 18)) end
    if H.v_sysStatus then
        local latestList = (GMT.GUILDTOOLS and GMT.GUILDTOOLS.GetNewestRecipes and GMT.GUILDTOOLS.GetNewestRecipes(1)) or nil
        local latest = latestList and latestList[1] or nil
        local latestTxt = latest and (GMT.Clip(latest.recipe, 16) .. ' / ' .. GMT.Clip(latest.player, 10)) or '--'
        local syncMembers = 0
        if GMT.GS and GMT.GS.members then for _ in pairs(GMT.GS.members) do syncMembers = syncMembers + 1 end end
        H.v_sysStatus:SetText('Newest Recipe: ' .. latestTxt .. GMT.Dim('  •  ') .. GMT.Green('Sync ' .. syncMembers))
    end

    --    Banner subtitle                                    
    local name  = UnitName("player") or "Commander"
    local gname = inGuild and guild or "Unguilded"
    H.subtitle:SetText(
        GMT.Dim("Cmdr: ") .. GMT.Amber(name) ..
        GMT.Dim("   Guild: ") .. GMT.Green(gname) ..
        GMT.Dim("   ") .. GMT.Dim(GMT.Clock())
    )
end

-- ============================================================
-- BANNER  -- logo left, clean title center, no gears
-- ============================================================
local function BuildBanner(panel)
    local BW = GMT.PW - 16   -- 944
    local BH = 120

    local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    banner:SetSize(BW, BH)
    banner:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    banner:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    banner:SetBackdropColor(0.080, 0.062, 0.038, 0.98)
    banner:SetBackdropBorderColor(GMT.U(GMT.C.copper))
    GMT.Rivets(banner, 9, 7)

    -- Parchment depth
    local bg = banner:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     banner, "TOPLEFT",      4, -4)
    bg:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -4,  4)
    bg:SetTexture("Interface/AchievementFrame/UI-Achievement-Parchment")
    bg:SetDesaturated(true)
    bg:SetVertexColor(0.07, 0.054, 0.032)
    bg:SetAlpha(0.40)

    GMT.HLine(banner, 4, -4, BW - 8)
    local bRule = banner:CreateTexture(nil, "ARTWORK")
    bRule:SetSize(BW - 8, 3)
    bRule:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 4, 4)
    bRule:SetColorTexture(GMT.U(GMT.C.copper))
    bRule:SetAlpha(0.80)

    -- Logo
    local logoF = CreateFrame("Frame", nil, banner)
    logoF:SetSize(106, 106)
    logoF:SetPoint("LEFT", banner, "LEFT", 10, 0)
    local logoTex = logoF:CreateTexture(nil, "ARTWORK")
    logoTex:SetAllPoints()
    logoTex:SetTexture(LOGO)

    -- Title
    local mainTitle = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    mainTitle:SetPoint("CENTER", banner, "CENTER", 20, 22)
    mainTitle:SetText("|cffcf9030GUILD|r|cff19f580MASTER|r  |cff9a8060TOOLS|r")

    local tagline = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOP", mainTitle, "BOTTOM", 0, -5)
    tagline:SetTextColor(GMT.U(GMT.C.txtDim))
    tagline:SetText("Guild Leadership & Management Suite")

    -- Accent lines
    local aL = banner:CreateTexture(nil, "ARTWORK")
    aL:SetPoint("LEFT",  logoF,     "RIGHT",  10, 6)
    aL:SetPoint("RIGHT", mainTitle, "LEFT",  -10, 6)
    aL:SetHeight(1)
    aL:SetColorTexture(GMT.U(GMT.C.copper))
    aL:SetAlpha(0.40)

    -- Right accent line removed by request

    -- Live subtitle
    local sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("BOTTOM", banner, "BOTTOM", 0, 10)
    sub:SetText("Initializing...")
    H.subtitle = sub
end

-- ============================================================
-- STAT CARDS  (6 cards in 3x2 grid -- full data coverage)
-- PW=960, card width=(960-16-20)/3=308, card h=148
-- Row1 y=-136 (banner 120+8 offset = 136)
-- Row2 y=-136-148-8=-292
-- ============================================================
local function BuildCards(panel)
    local CW = 308
    local CH = 148
    local G  = 8   -- gap
    local X1 = 8
    local X2 = X1 + CW + G  -- 324
    local X3 = X2 + CW + G  -- 640
    local Y1 = -136          -- row 1 (banner h=120, margin=8, header gap=8)
    local Y2 = Y1 - CH - G  -- row 2

    --    Card 1: Guild Status                              
    local _, v1 = GMT.Card(panel, "  GUILD STATUS",
        {{k="Guild"},{k="Members"},{k="Online"},{k="Offline"}},
        X1, Y1, CW, CH)
    H.v_guild   = v1[1]
    H.v_total   = v1[2]
    H.v_online  = v1[3]
    H.v_offline = v1[4]

    --    Card 2: Raid Roster                               
    local _, v2 = GMT.Card(panel, "  RAID ROSTER",
        {{k="Type"},{k="Size"},{k="Tanks"},{k="Healers"},{k="DPS"}},
        X2, Y1, CW, CH)
    H.v_gtype = v2[1]
    H.v_gsize = v2[2]
    H.v_tanks = v2[3]
    H.v_heals = v2[4]
    H.v_dps   = v2[5]

    --    Card 3: Recruitment                               
    local c3, v3 = GMT.Card(panel, "  RECRUITMENT",
        {{k="Pipeline"},{k="Breakdown"},{k=""}},
        X3, Y1, CW, CH)
    H.v_recruits = v3[1]
    H.v_recBreak = v3[2]
    v3[3]:SetText("")

    local rBtn = GMT.MBtn(c3, "Open Recruitment", 148, 22)
    rBtn:SetPoint("BOTTOMLEFT", c3, "BOTTOMLEFT", 8, 8)
    rBtn:SetScript("OnClick", function() GMT_ShowTab("Recruitment") end)

    --    Card 4: Economy                                   
    local _, v4 = GMT.Card(panel, "  ECONOMY",
        {{k="Bank Gold"},{k="Stacks"},{k="Contributors"}},
        X1, Y2, CW, CH)
    H.v_bankGold  = v4[1]
    H.v_bankItems = v4[2]
    H.v_contribs  = v4[3]

    --    Card 5: Logistics                                 
    local _, v5 = GMT.Card(panel, "  LOGISTICS",
        {{k="Shortages"},{k="Stocked"},{k="Gatherers"},{k="Crafters"}},
        X2, Y2, CW, CH)
    H.v_shortages = v5[1]
    H.v_stocked   = v5[2]
    H.v_gatherers = v5[3]
    H.v_crafters  = v5[4]

    --    Card 6: Events & System                           
    -- Card 6: Events & System (4 rows - fits in CH=148)
    local c6, v6 = GMT.Card(panel, "  GUILD DASHBOARD",
        {{k="Class Distribution"},{k="Role Stats"},{k="Offline Members"},{k="Newest Recipes"}},
        X3, Y2, CW, CH)
    H.v_nextEvent = v6[1]
    H.v_eventIn   = v6[2]
    H.v_eventRSVP = v6[3]
    H.v_sysStatus = v6[4]   -- will show "vX.Y.Z  |  11 mods  |  N synced"
end

-- ============================================================
-- QUICK ACTIONS
-- ============================================================
local function BuildActions(panel)
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetSize(GMT.PW - 16, 2)
    rule:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 48)
    rule:SetColorTexture(GMT.U(GMT.C.copper))
    rule:SetAlpha(0.55)
    local rShine = panel:CreateTexture(nil, "OVERLAY")
    rShine:SetSize(GMT.PW - 16, 1)
    rShine:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 50)
    rShine:SetColorTexture(GMT.U(GMT.C.gold))
    rShine:SetAlpha(0.25)

    local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 52)
    lbl:SetTextColor(GMT.U(GMT.C.txtDim))
    lbl:SetText("QUICK NAVIGATE")

    local nav = {
        {l="Members",     t="Members"},
        {l="Recruitment",  t="Recruitment"},
        {l="Raid Prep",    t="Raid Prep"},
        {l="Guild Professions",   t="Crafting"},
        {l="Logistics",    t="Logistics"},
        {l="Events",       t="Events"},
        {l="Refresh",      a="refresh"},
        {l="Reload UI",    a="reload"},
    }
    -- 8 buttons: (960-16) / 8 = 118px each with gaps
    -- Use 108px buttons + 6px gaps: 8*108 + 7*6 = 906 fits
    local BW, BH, GAP = 108, 26, 6
    for i, d in ipairs(nav) do
        local btn = GMT.MBtn(panel, d.l, BW, BH)
        btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8 + (i-1)*(BW+GAP), 14)
        if d.t then
            btn:SetScript("OnClick", function() GMT_ShowTab(d.t) end)
        elseif d.a == "reload" then
            -- Red-amber tint for Reload
            if btn:GetNormalTexture()    then btn:GetNormalTexture():SetVertexColor(0.55, 0.18, 0.08) end
            if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetVertexColor(0.80, 0.30, 0.10, 0.55) end
            btn:GetFontString():SetTextColor(1.0, 0.55, 0.25)
            btn:SetScript("OnClick", function()
                GMT.ReloadNow("Reloading UI...")
            end)
        else
            btn:SetScript("OnClick", function()
                if IsInGuild() then C_GuildInfo.GuildRoster() end
                Refresh()
                GMT.Print("Dashboard refreshed.")
            end)
        end
    end
end

-- ============================================================
-- INIT
-- ============================================================
function GMT_Home_Init()
    local panel = GMT_GetPanel("Home")
    if not panel then return end

    BuildBanner(panel)
    BuildCards(panel)
    BuildActions(panel)
    H.ready = true

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GUILD_ROSTER_UPDATE")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_GUILD_UPDATE")
    ev:SetScript("OnEvent", Refresh)

    panel:SetScript("OnShow", function()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        Refresh()
    end)

    C_Timer.After(2, function()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        Refresh()
    end)

    C_Timer.NewTicker(60, function()
        if panel:IsShown() then Refresh() end
    end)
end
