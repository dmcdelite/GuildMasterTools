local _, GMT = ...

local menuFrame = CreateFrame('Frame', 'GMT_MinimapMenu', UIParent, 'UIDropDownMenuTemplate')
local button

local function ensureDB()
    GMT.DB.settings = GMT.DB.settings or {}
    GMT.DB.settings.minimap = GMT.DB.settings.minimap or { hide = false, angle = 220 }
    return GMT.DB.settings.minimap
end

local function updatePos()
    if not button then return end
    local db = ensureDB()
    local angle = math.rad(db.angle or 220)
    local x = math.cos(angle) * 78
    local y = math.sin(angle) * 78
    button:ClearAllPoints()
    button:SetPoint('CENTER', Minimap, 'CENTER', x, y)
    button:SetShown(not db.hide)
end

local function openMenu(self)
    local items = {
        { text = 'Open GuildMasterTools', func = function() if GMT_MainFrame then GMT_MainFrame:Show() end end },
        { text = 'Home', func = function() if GMT_MainFrame then GMT_MainFrame:Show() end GMT_ShowTab('Home') end },
        { text = 'Members', func = function() if GMT_MainFrame then GMT_MainFrame:Show() end GMT_ShowTab('Members') end },
        { text = 'Guild Professions', func = function() if GMT_MainFrame then GMT_MainFrame:Show() end GMT_ShowTab('Crafting') end },
        { text = 'Sync Now', func = function() if GMT.GS and GMT.GS.RequestAllSync then GMT.GS.RequestAllSync() end end },
        { text = 'Reload UI', func = function() GMT.ReloadNow('Reloading UI...') end },
        { text = ensureDB().hide and 'Show Minimap Button' or 'Hide Minimap Button', func = function() local db=ensureDB(); db.hide=not db.hide; updatePos() end },
    }
    EasyMenu(items, menuFrame, 'cursor', 0, 0, 'MENU', 2)
end

function GMT_Minimap_Init()
    if button then updatePos(); return end
    local db = ensureDB()
    button = CreateFrame('Button', 'GMT_MinimapButton', Minimap)
    button:SetSize(32,32)
    button:SetFrameStrata('MEDIUM')
    button:RegisterForClicks('LeftButtonUp','RightButtonUp')
    button:RegisterForDrag('LeftButton')
    button:SetMovable(true)
    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetTexture('Interface/AddOns/GuildMasterTools/Media/logo')
    icon:SetTexCoord(0.08,0.92,0.08,0.92)
    icon:SetPoint('TOPLEFT', 7,-7)
    icon:SetPoint('BOTTOMRIGHT', -7,7)
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface/Minimap/UI-Minimap-TrackingBorder')
    border:SetAllPoints()
    local bg = button:CreateTexture(nil, 'BACKGROUND')
    bg:SetTexture('Interface/Minimap/UI-Minimap-Background')
    bg:SetAllPoints()
    button:SetScript('OnClick', function(self, btn)
        if btn == 'LeftButton' then
            if IsShiftKeyDown() then openMenu(self) else
                if GMT_MainFrame then
                    if GMT_MainFrame:IsShown() then GMT_MainFrame:Hide() else GMT_MainFrame:Show() end
                end
            end
        else
            openMenu(self)
        end
    end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        db.angle = math.deg(math.atan2(py - my, px - mx))
        updatePos()
    end) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:SetText('GuildMasterTools')
        GameTooltip:AddLine('Left: Toggle main window',1,1,1)
        GameTooltip:AddLine('Right: Menu',1,1,1)
        GameTooltip:AddLine('Shift-Left: Menu',1,1,1)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    updatePos()
end
