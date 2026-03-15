local _, GMT = ...

local state = { active = false }

local function enabled()
    return GMT.DB and GMT.DB.settings and GMT.DB.settings.autoCombatLog
end

local function isRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == 'raid'
end

local function setLogging(on)
    if type(LoggingCombat) ~= 'function' then return end
    local current = LoggingCombat()
    if on and not current then
        pcall(LoggingCombat, true)
        GMT.Print('Auto combat logging enabled for raid instance.')
    elseif (not on) and current and state.active then
        pcall(LoggingCombat, false)
        GMT.Print('Auto combat logging disabled after leaving raid instance.')
    end
    state.active = on and true or false
end

local function refresh()
    if not enabled() then return end
    setLogging(isRaidInstance())
end

function GMT_CombatLog_Init()
    local f = CreateFrame('Frame')
    f:RegisterEvent('PLAYER_ENTERING_WORLD')
    f:RegisterEvent('ZONE_CHANGED_NEW_AREA')
    f:RegisterEvent('GROUP_ROSTER_UPDATE')
    f:SetScript('OnEvent', refresh)
    C_Timer.After(3, refresh)
end
