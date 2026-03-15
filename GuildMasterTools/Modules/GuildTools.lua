local _, GMT = ...

GMT.GUILDTOOLS = GMT.GUILDTOOLS or {}
local GT = GMT.GUILDTOOLS

local function ensureDB()
    GMT.DB.guildTools = GMT.DB.guildTools or {}
    local db = GMT.DB.guildTools
    db.guildLog = db.guildLog or { events = {}, seen = {} }
    return db
end

local function safeQueryGuildEventLog()
    if QueryGuildEventLog then pcall(QueryGuildEventLog) end
end

local function makeKey(ev)
    return table.concat({ tostring(ev.kind or '?'), tostring(ev.actor or '?'), tostring(ev.target or '?'), tostring(ev.detail or '?'), tostring(ev.ts or 0) }, '|')
end

local function addGuildEvent(ev)
    local db = ensureDB().guildLog
    local key = makeKey(ev)
    if db.seen[key] then return end
    db.seen[key] = true
    table.insert(db.events, 1, ev)
    while #db.events > 80 do table.remove(db.events) end
end

local function normName(name)
    return GMT.Short(name or '')
end

local function parseGuildEvent(index)
    if not GetGuildEventInfo then return nil end
    local a,b,c,d,e,f,g,h,i,j = GetGuildEventInfo(index)
    local vals = {a,b,c,d,e,f,g,h,i,j}
    local textParts = {}
    for _,v in ipairs(vals) do textParts[#textParts+1] = tostring(v) end
    local blob = table.concat(textParts, ' | '):lower()
    local kind = 'activity'
    local actor, target, detail = nil, nil, nil
    local candidates = {}
    for _,v in ipairs(vals) do
        if type(v) == 'string' and v ~= '' then candidates[#candidates+1] = v end
    end
    actor = candidates[1]
    target = candidates[2]
    detail = candidates[#candidates]
    if blob:find('joined') or blob:find('join') then kind = 'join'
    elseif blob:find('removed') or blob:find('kick') or blob:find('gkick') then kind = 'kick'
    elseif blob:find('left') or blob:find('quit') then kind = 'leave'
    elseif blob:find('promot') then kind = 'promote'
    elseif blob:find('demot') then kind = 'demote' end
    if kind == 'activity' and #candidates == 0 then return nil end
    return {
        kind = kind,
        actor = normName(actor),
        target = normName(target),
        detail = tostring(detail or ''),
        ts = time(),
        raw = textParts,
    }
end

function GT.GetGuildLog()
    return ensureDB().guildLog.events
end

function GT.LatestGuildEvent()
    return ensureDB().guildLog.events[1]
end

function GT.GetNewestRecipes(limit)
    local out = {}
    local db = GMT.DB and GMT.DB.talentMap
    local sp = db and db.syncProfiles or {}
    for player, profile in pairs(sp or {}) do
        for profName, prof in pairs(profile.professions or {}) do
            for _, recipe in ipairs(prof.recipes or {}) do
                out[#out+1] = {
                    player = GMT.Short(player),
                    profession = profName,
                    recipe = recipe.name or recipe.link or tostring(recipe.id or '?'),
                    scannedAt = tonumber(prof.scannedAt or profile.lastSeen or 0) or 0,
                }
            end
        end
    end
    table.sort(out, function(a,b) return (a.scannedAt or 0) > (b.scannedAt or 0) end)
    local n = math.min(limit or 5, #out)
    local trimmed = {}
    for i=1,n do trimmed[i] = out[i] end
    return trimmed
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('GUILD_EVENT_LOG_UPDATE')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:SetScript('OnEvent', function(_, event)
    if event == 'PLAYER_LOGIN' then
        C_Timer.After(2, safeQueryGuildEventLog)
    else
        for i=1, 25 do
            local ev = parseGuildEvent(i)
            if ev then addGuildEvent(ev) end
        end
    end
end)

function GMT_GuildTools_Init()
    ensureDB()
    safeQueryGuildEventLog()
end
