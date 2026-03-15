local _, GMT = ...

local refs = { rosterRows = {}, boardLines = {}, logLines = {} }
local STATE = { mode = 'online', selected = 1, data = nil }
local ROW_H = 20

local function Section(parent, title, x, y, w, h)
    local box = CreateFrame('Frame', nil, parent, 'BackdropTemplate')
    box:SetSize(w, h)
    box:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
    box:SetBackdrop({ bgFile='Interface/DialogFrame/UI-DialogBox-Background-Dark', edgeFile='Interface/Tooltips/UI-Tooltip-Border', tile=true, tileSize=32, edgeSize=10, insets={left=3,right=3,top=3,bottom=3} })
    box:SetBackdropColor(GMT.U(GMT.C.cardBg)); box:SetBackdropBorderColor(GMT.U(GMT.C.copper))
    local head = box:CreateTexture(nil, 'BACKGROUND'); head:SetPoint('TOPLEFT',3,-3); head:SetPoint('TOPRIGHT',-3,-3); head:SetHeight(22); head:SetColorTexture(GMT.U(GMT.C.cardHead))
    local fs = box:CreateFontString(nil, 'OVERLAY', 'GameFontNormal'); fs:SetPoint('TOPLEFT',10,-7); fs:SetTextColor(GMT.U(GMT.C.txtTitle)); fs:SetText(title)
    GMT.Rivets(box, 6, 4)
    return box
end

local function Label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, 'OVERLAY', font or 'GameFontHighlightSmall')
    fs:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
    fs:SetTextColor(GMT.U(GMT.C.txtDim)); fs:SetText(text or '')
    return fs
end

local function Value(parent, x, y, w)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    fs:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y)
    fs:SetWidth(w or 160); fs:SetJustifyH('LEFT'); fs:SetTextColor(GMT.U(GMT.C.txtBody)); fs:SetText('--')
    return fs
end

local function SafeGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
end

local function BuildData()
    local data = { rows={}, total=0, online=0, offline=0, mobile=0, avg=0, max=0, officers=0, classCounts={}, rankCounts={}, zoneCounts={}, offlineRows={} }
    local total, levelSum = GetNumGuildMembers() or 0, 0
    data.total = total
    for i=1,total do
        local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if name then
            local row = {
                name = name, short = GMT.Short(name), rank = rank or 'Unknown', rankIndex = tonumber(rankIndex) or 99,
                level = tonumber(level) or 0, class = class or '?', classFileName = classFileName, zone = zone or 'Unknown',
                online = online and true or false, isMobile = isMobile and true or false, note = note or '', officernote = officernote or '',
                guid = guid,
            }
            levelSum = levelSum + row.level
            data.max = math.max(data.max, row.level)
            if row.isMobile then data.mobile = data.mobile + 1 end
            if row.online then data.online = data.online + 1 else data.offline = data.offline + 1; data.offlineRows[#data.offlineRows+1]=row end
            if row.rankIndex <= 1 then data.officers = data.officers + 1 end
            data.classCounts[row.class] = (data.classCounts[row.class] or 0) + 1
            data.rankCounts[row.rank] = (data.rankCounts[row.rank] or 0) + 1
            data.zoneCounts[row.zone] = (data.zoneCounts[row.zone] or 0) + 1
            if GMT.GS and GMT.GS.members and GMT.GS.members[row.short] then row.layer = GMT.GS.members[row.short].layer end
            data.rows[#data.rows+1] = row
        end
    end
    if total > 0 then data.avg = math.floor((levelSum/total)*10+0.5)/10 end
    table.sort(data.rows, function(a,b) if a.online ~= b.online then return a.online end if a.level ~= b.level then return a.level > b.level end return a.short < b.short end)
    table.sort(data.offlineRows, function(a,b) return a.short < b.short end)
    return data
end

local function TopKey(tbl)
    local k, v = '--', 0
    for kk, vv in pairs(tbl or {}) do if vv > v then k, v = kk, vv end end
    return k, v
end

local function Sorted(rows, mode)
    local copy = {}
    for i,row in ipairs(rows or {}) do copy[i] = row end
    if mode == 'online' then
        table.sort(copy, function(a,b) if a.online ~= b.online then return a.online end if a.level ~= b.level then return a.level > b.level end return a.short < b.short end)
    elseif mode == 'level' then
        table.sort(copy, function(a,b) if a.level ~= b.level then return a.level > b.level end return a.short < b.short end)
    elseif mode == 'rank' then
        table.sort(copy, function(a,b) if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end return a.short < b.short end)
    elseif mode == 'class' then
        table.sort(copy, function(a,b) if a.class ~= b.class then return a.class < b.class end if a.level ~= b.level then return a.level > b.level end return a.short < b.short end)
    elseif mode == 'zone' then
        table.sort(copy, function(a,b) if a.zone ~= b.zone then return a.zone < b.zone end if a.level ~= b.level then return a.level > b.level end return a.short < b.short end)
    end
    return copy
end

local function ScoreLine(mode, idx, row)
    local pre = string.format('|cff888880%2d.|r  ', idx)
    if mode == 'online' then return pre .. (row.online and GMT.Green('On') or GMT.Grey('Off')) .. '  ' .. GMT.ClassStr(row.classFileName, row.short) end
    if mode == 'level' then return pre .. GMT.Amber('Lv'..row.level) .. '  ' .. GMT.ClassStr(row.classFileName, row.short) end
    if mode == 'rank' then return pre .. GMT.Clip(row.rank, 14) .. '  ' .. GMT.ClassStr(row.classFileName, row.short) end
    if mode == 'class' then return pre .. GMT.ClassStr(row.classFileName, row.short) .. '  ' .. GMT.Dim('Lv'..row.level) end
    return pre .. GMT.Clip(row.zone, 14) .. '  ' .. GMT.ClassStr(row.classFileName, row.short)
end

local function RenderCard(data)
    local row = data.rows[STATE.selected] or data.rows[1]
    if not row then return end
    refs.cardName:SetText(GMT.ClassStr(row.classFileName, row.short))
    refs.cardMeta:SetText(string.format('Level %d  •  %s', row.level or 0, row.rank or '--'))
    refs.cardZone:SetText('Zone: ' .. GMT.Clip(row.zone or '--', 24))
    refs.cardStatus:SetText('Status: ' .. (row.isMobile and GMT.Amber('Mobile') or (row.online and GMT.Green('Online') or GMT.Grey('Offline'))))
    refs.cardLayer:SetText('Layer: ' .. GMT.Clip(row.layer or '--', 26))
    refs.cardNote:SetText('Note: ' .. GMT.Clip((row.note and row.note ~= '' and row.note) or '--', 28))
    local details = {
        'Guild Rank Index: ' .. tostring(row.rankIndex or '--'),
        'Presence: ' .. (row.online and 'Available' or 'Offline'),
        'Mobile App: ' .. (row.isMobile and 'Yes' or 'No'),
        'Officer Note: ' .. GMT.Clip((row.officernote and row.officernote ~= '' and row.officernote) or '--', 28),
        'Guid: ' .. GMT.Clip((row.guid and tostring(row.guid)) or '--', 24),
    }
    local bodyText = table.concat(details, '\n')
    refs.cardBody:SetText(bodyText)
    local lines = 1
    for _ in bodyText:gmatch('\n') do lines = lines + 1 end
    refs.cardBody:SetHeight(math.max(96, lines * 14 + 10))
    if refs.cardScrollChild then
        refs.cardScrollChild:SetHeight(math.max(110, refs.cardBody:GetHeight() + 8))
    end
end

local function RefreshSummary(data)
    local topClass, topClassCount = TopKey(data.classCounts)
    local topZone, topZoneCount = TopKey(data.zoneCounts)
    local topRank, topRankCount = TopKey(data.rankCounts)
    refs.sumTotal:SetText(GMT.Amber(data.total))
    refs.sumOnline:SetText(GMT.Green(data.online))
    refs.sumOffline:SetText(GMT.Grey(data.offline))
    refs.sumMax:SetText(GMT.Amber(data.max))
    refs.sumAvg:SetText(GMT.Amber(data.avg))
    refs.sumOff:SetText(GMT.Amber(data.officers))
    refs.sumMob:SetText(GMT.Amber(data.mobile))
    refs.sumClass:SetText(string.format('%s (%d)', GMT.Clip(topClass, 12), topClassCount or 0))
    refs.sumZone:SetText(string.format('%s (%d)', GMT.Clip(topZone, 14), topZoneCount or 0))
    refs.sumRank:SetText(string.format('%s (%d)', GMT.Clip(topRank, 14), topRankCount or 0))
end

local function RefreshRoster(data)
    for i,row in ipairs(refs.rosterRows) do row:Hide() end
    for i,entry in ipairs(data.rows) do
        local row = refs.rosterRows[i]
        if not row then
            row = CreateFrame('Button', nil, refs.rosterContent)
            row:SetPoint('TOPLEFT', refs.rosterContent, 'TOPLEFT', 0, -((i-1)*ROW_H))
            row:SetSize(600, ROW_H)
            row.bg = row:CreateTexture(nil,'BACKGROUND'); row.bg:SetAllPoints()
            row.cells = {}
            local widths = {150,90,42,118,110,70}
            local x = 4
            for c,w in ipairs(widths) do
                local fs = row:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); fs:SetPoint('LEFT', row, 'LEFT', x, 0); fs:SetWidth(w); fs:SetJustifyH(c==3 and 'CENTER' or 'LEFT'); row.cells[c]=fs; x=x+w end
            refs.rosterRows[i] = row
        end
        row.bg:SetColorTexture(STATE.selected == i and 0.18 or 0.07, STATE.selected == i and 0.22 or 0.05, 0.04, STATE.selected == i and 0.70 or (i%2==0 and 0.26 or 0.10))
        row.cells[1]:SetText(GMT.ClassStr(entry.classFileName, GMT.Clip(entry.short, 18)))
        row.cells[2]:SetText(GMT.Clip(entry.class, 14))
        row.cells[3]:SetText(tostring(entry.level))
        row.cells[4]:SetText(GMT.Clip(entry.rank, 16))
        row.cells[5]:SetText(GMT.Clip(entry.zone, 16))
        row.cells[6]:SetText(entry.isMobile and GMT.Amber('Mobile') or (entry.online and GMT.Green('Online') or GMT.Grey('Offline')))
        row:SetScript('OnClick', function() STATE.selected = i; RenderCard(STATE.data); RefreshRoster(STATE.data) end)
        row:Show()
    end
    refs.rosterContent:SetHeight(math.max(ROW_H, #data.rows * ROW_H))
end


local function CleanGuildLogName(value)
    local s = tostring(value or '')
    local low = s:lower()
    if s == '' or low == 'join' or low == 'joined' or low == 'leave' or low == 'left' or low == 'kick' or low == 'remove' or low == 'removed' then
        return nil
    end
    return GMT.Short(s)
end

local function RefreshGuildLog()
    local events = (GMT.GUILDTOOLS and GMT.GUILDTOOLS.GetGuildLog and GMT.GUILDTOOLS.GetGuildLog()) or {}
    local maxRows = math.min(6, #events)
    for i=1,maxRows do
        local fs = refs.logLines[i]
        if not fs then fs = refs.logContent:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); fs:SetPoint('TOPLEFT', refs.logContent, 'TOPLEFT', 4, -((i-1)*20)-2); fs:SetWidth(588); fs:SetJustifyH('LEFT'); refs.logLines[i]=fs end
        local ev = events[i]
        local actor = CleanGuildLogName(ev.actor) or CleanGuildLogName(ev.target) or '?'
        local target = CleanGuildLogName(ev.target) or CleanGuildLogName(ev.actor) or '?'
        local detail = ''
        if ev.kind == 'join' then detail = string.format('%s joined the guild', actor)
        elseif ev.kind == 'leave' then detail = string.format('%s left the guild', actor)
        elseif ev.kind == 'kick' then
            if actor == target then
                detail = string.format('%s was removed from the guild', actor)
            else
                detail = string.format('%s removed %s', actor, target)
            end
        else
            detail = table.concat(ev.raw or {}, ' | ')
        end
        fs:SetText(GMT.Dim(date('%H:%M', ev.ts or time())) .. '  ' .. GMT.Clip(detail, 78)); fs:Show()
    end
    for i=maxRows+1,#refs.logLines do refs.logLines[i]:Hide() end
    refs.logContent:SetHeight(math.max(20, maxRows*20+6))
end

local function RefreshAll()
    SafeGuildRoster()
    STATE.data = BuildData()
    if STATE.selected > #STATE.data.rows then STATE.selected = 1 end
    RefreshRoster(STATE.data)
    RefreshSummary(STATE.data)
    RenderCard(STATE.data)
    RefreshGuildLog()
    refs.status:SetText(string.format('Roster synced: %d total, %d online, %d offline', STATE.data.total, STATE.data.online, STATE.data.offline))
end

function GMT_Members_Init()
    local panel = GMT_GetPanel('Members')
    if not panel or panel._gmtMembersBuilt then return end
    panel._gmtMembersBuilt = true
    GMT.Header(panel, 'Guild Members & Intelligence', 14, -14)
    GMT.HLine(panel, 8, -36, GMT.PW - 16)

    local rosterBox = Section(panel, 'Guild Roster', 8, -40, 624, 332)
    local logBox = Section(panel, 'Guild Log', 8, -378, 624, 146)
    local intelBox = Section(panel, 'Guild Snapshot', 640, -40, 312, 216)
    local cardBox = Section(panel, 'Player Card', 640, -262, 312, 334)

    -- roster header
    local cols = {'Name','Class','Lv','Rank','Zone','Status'}
    local widths = {150,90,42,118,110,70}
    local x=12
    for i,c in ipairs(cols) do local fs=rosterBox:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); fs:SetPoint('TOPLEFT',rosterBox,'TOPLEFT',x,-30); fs:SetTextColor(GMT.U(GMT.C.txtTitle)); fs:SetText(c); x=x+widths[i] end
    local sf = CreateFrame('ScrollFrame', nil, rosterBox, 'UIPanelScrollFrameTemplate'); sf:SetSize(600, 274); sf:SetPoint('TOPLEFT', rosterBox, 'TOPLEFT', 10, -48)
    local content = CreateFrame('Frame', nil, sf); content:SetSize(600, 20); sf:SetScrollChild(content); refs.rosterContent = content
    local refreshBtn = GMT.MBtn(rosterBox, 'Refresh', 70, 18); refreshBtn:SetPoint('TOPRIGHT', rosterBox, 'TOPRIGHT', -10, -6); refreshBtn:SetScript('OnClick', RefreshAll)

    -- summary values
    Label(intelBox,'Total',10,-34); refs.sumTotal=Value(intelBox,82,-34,64)
    Label(intelBox,'Online',10,-52); refs.sumOnline=Value(intelBox,82,-52,64)
    Label(intelBox,'Offline',10,-70); refs.sumOffline=Value(intelBox,82,-70,64)
    Label(intelBox,'Max Level',10,-88); refs.sumMax=Value(intelBox,82,-88,64)
    Label(intelBox,'Avg Level',160,-34); refs.sumAvg=Value(intelBox,238,-34,64)
    Label(intelBox,'Officers',160,-52); refs.sumOff=Value(intelBox,238,-52,64)
    Label(intelBox,'Mobile',160,-70); refs.sumMob=Value(intelBox,238,-70,64)
    Label(intelBox,'Top Class',10,-112); refs.sumClass=Value(intelBox,82,-112,210)
    Label(intelBox,'Top Zone',10,-130); refs.sumZone=Value(intelBox,82,-130,210)
    Label(intelBox,'Top Rank',10,-148); refs.sumRank=Value(intelBox,82,-148,210)


    refs.status = Label(cardBox, 'Roster ready.', 12, -154)

    refs.cardName = cardBox:CreateFontString(nil,'OVERLAY','GameFontHighlightLarge'); refs.cardName:SetPoint('TOPLEFT', cardBox, 'TOPLEFT', 12, -32); refs.cardName:SetWidth(288); refs.cardName:SetJustifyH('LEFT')
    refs.cardMeta = cardBox:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); refs.cardMeta:SetPoint('TOPLEFT', cardBox, 'TOPLEFT', 12, -54); refs.cardMeta:SetWidth(288); refs.cardMeta:SetJustifyH('LEFT')
    refs.cardZone = Label(cardBox, '--', 12, -76)
    refs.cardStatus = Label(cardBox, '--', 12, -94)
    refs.cardLayer = Label(cardBox, '--', 12, -112)
    refs.cardNote = Label(cardBox, '--', 12, -130)
    refs.cardTitle2 = cardBox:CreateFontString(nil,'OVERLAY','GameFontNormal')
    refs.cardTitle2:SetPoint('TOPLEFT', cardBox, 'TOPLEFT', 12, -178)
    refs.cardTitle2:SetTextColor(GMT.U(GMT.C.txtTitle))
    refs.cardTitle2:SetText('Member Details')
    refs.cardScroll = CreateFrame('ScrollFrame', nil, cardBox, 'UIPanelScrollFrameTemplate')
    refs.cardScroll:SetPoint('TOPLEFT', cardBox, 'TOPLEFT', 10, -196)
    refs.cardScroll:SetSize(286, 100)
    refs.cardScrollChild = CreateFrame('Frame', nil, refs.cardScroll)
    refs.cardScrollChild:SetSize(266, 110)
    refs.cardScroll:SetScrollChild(refs.cardScrollChild)
    refs.cardBody = refs.cardScrollChild:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    refs.cardBody:SetPoint('TOPLEFT', refs.cardScrollChild, 'TOPLEFT', 2, -2)
    refs.cardBody:SetWidth(258)
    refs.cardBody:SetJustifyH('LEFT')
    refs.cardBody:SetJustifyV('TOP')
    local prevBtn = GMT.MBtn(cardBox,'Prev',56,18); prevBtn:SetPoint('BOTTOMLEFT', cardBox, 'BOTTOMLEFT', 12, 10)
    local nextBtn = GMT.MBtn(cardBox,'Next',56,18); nextBtn:SetPoint('LEFT', prevBtn, 'RIGHT', 6, 0)
    local refreshCardBtn = GMT.MBtn(cardBox,'Refresh',64,18); refreshCardBtn:SetPoint('LEFT', nextBtn, 'RIGHT', 8, 0)
    refreshCardBtn:SetScript('OnClick', RefreshAll)
    prevBtn:SetScript('OnClick', function() if not STATE.data or #STATE.data.rows == 0 then return end STATE.selected = STATE.selected - 1 if STATE.selected < 1 then STATE.selected = #STATE.data.rows end RenderCard(STATE.data); RefreshRoster(STATE.data) end)
    nextBtn:SetScript('OnClick', function() if not STATE.data or #STATE.data.rows == 0 then return end STATE.selected = STATE.selected + 1 if STATE.selected > #STATE.data.rows then STATE.selected = 1 end RenderCard(STATE.data); RefreshRoster(STATE.data) end)

    local sf3 = CreateFrame('ScrollFrame', nil, logBox, 'UIPanelScrollFrameTemplate'); sf3:SetSize(600, 108); sf3:SetPoint('TOPLEFT', logBox, 'TOPLEFT', 10, -28)
    local c3 = CreateFrame('Frame', nil, sf3); c3:SetSize(600, 20); sf3:SetScrollChild(c3); refs.logContent = c3

    local ev = CreateFrame('Frame')
    ev:RegisterEvent('GUILD_ROSTER_UPDATE')
    ev:RegisterEvent('PLAYER_GUILD_UPDATE')
    ev:RegisterEvent('GUILD_EVENT_LOG_UPDATE')
    ev:SetScript('OnEvent', function() if panel:IsShown() then RefreshAll() end end)
    panel:SetScript('OnShow', RefreshAll)
end
