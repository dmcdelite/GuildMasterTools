-- ============================================================
-- GuildMaster Tools  |  UI.lua  |  v2.8.1
-- Rustbolt Goblin Engineering   Main frame + Tab system
-- FIX v2.8.1: replaced bare U() calls with GMT.U() throughout
-- RULE: panels have explicit SetSize()   GetWidth() is safe
-- ============================================================
local _, GMT = ...

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================
local FW     = 980   -- frame width
local FH     = 640   -- frame height
local TBAR_H = 60    -- title bar height
local TAB_H  = 32    -- tab row height
local PAD    = 10    -- outer pad

local PX = PAD
local PY = -(TBAR_H + TAB_H + PAD)   -- -102
local PW = FW - PAD * 2              -- 960
local PH = FH - TBAR_H - TAB_H - PAD * 2  -- 528

GMT.PW = PW
GMT.PH = PH

local panels    = {}
local tabBtns   = {}
local tabLines  = {}
local current   = nil

local TABS = {
    { key="Home",        label="Home"        },
    { key="Members",     label="Members"     },
    { key="Recruitment", label="Recruitment" },
    { key="Raid Prep",   label="Raid Prep"   },
    { key="Crafting",    label="Guild Professions"  },
    { key="Logistics",   label="Logistics"   },
    { key="Economy",     label="Economy"     },
    { key="Raid Perf",   label="Raid Perf"   },
    { key="Events",      label="Events"      },
    { key="Guild Sync",  label="Sync"        },
    { key="Settings",    label="Settings"    },
}

-- ============================================================
-- PUBLIC API
-- ============================================================
function GMT_GetPanel(key)  return panels[key] end
function GMT_ActivePanel()  return current     end

function GMT_ShowTab(key)
    if not panels[key] then return end
    if GMT.CanAccessTab and not GMT.CanAccessTab(key) then
        GMT.Warn((key or "Tab") .. " is restricted by guild access settings.")
        return
    end
    for k, p in pairs(panels) do
        p:Hide()
        if tabBtns[k] then
            local fs = tabBtns[k]:GetFontString()
            if fs then fs:SetTextColor(GMT.U(GMT.C.amber)) end
            local nt = tabBtns[k]:GetNormalTexture()
            if nt then nt:SetVertexColor(0.55, 0.33, 0.11) end
        end
        if tabLines[k] then tabLines[k]:Hide() end
    end
    panels[key]:Show()
    current = key
    if tabBtns[key] then
        local fs = tabBtns[key]:GetFontString()
        if fs then fs:SetTextColor(GMT.U(GMT.C.green)) end
        local nt = tabBtns[key]:GetNormalTexture()
        if nt then nt:SetVertexColor(0.20, 0.16, 0.06) end
    end
    if tabLines[key] then tabLines[key]:Show() end
end

-- ============================================================
-- BUILD MAIN FRAME
-- ============================================================
function GMT_BuildUI()
    if GMT_MainFrame then return end

    local f = CreateFrame("Frame", "GMT_MainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FW, FH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GMT_MainFrame")
    f:Hide()

    -- Dark iron hull backdrop
    f:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        tile=true, tileSize=32, edgeSize=30,
        insets={left=7,right=7,top=7,bottom=7},
    })
    f:SetBackdropColor(GMT.C.frameBg[1],GMT.C.frameBg[2],GMT.C.frameBg[3],GMT.C.frameBg[4])
    f:SetBackdropBorderColor(GMT.U(GMT.C.copper))

    -- Inner depth overlay
    local inner = f:CreateTexture(nil, "BACKGROUND")
    inner:SetPoint("TOPLEFT",     f, "TOPLEFT",      9, -9)
    inner:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -9,  9)
    inner:SetColorTexture(0, 0, 0, 0.22)

    --    TITLE BAR                                          
    local TBAR_W = FW - 16

    local tBg = f:CreateTexture(nil, "BACKGROUND")
    tBg:SetSize(TBAR_W, TBAR_H)
    tBg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    tBg:SetColorTexture(GMT.U(GMT.C.cardHead))

    -- Parchment depth texture
    local tDetail = f:CreateTexture(nil, "ARTWORK")
    tDetail:SetSize(TBAR_W, TBAR_H)
    tDetail:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    tDetail:SetTexture("Interface/AchievementFrame/UI-Achievement-Parchment")
    tDetail:SetDesaturated(true)
    tDetail:SetVertexColor(0.08, 0.062, 0.038)
    tDetail:SetAlpha(0.45)

    -- Bottom copper pipe edge
    local tEdge = f:CreateTexture(nil, "ARTWORK")
    tEdge:SetSize(TBAR_W, 3)
    tEdge:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(8 + TBAR_H))
    tEdge:SetColorTexture(GMT.U(GMT.C.copper))
    tEdge:SetAlpha(0.90)

    local tShine = f:CreateTexture(nil, "OVERLAY")
    tShine:SetSize(TBAR_W, 1)
    tShine:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(8 + TBAR_H - 2))
    tShine:SetColorTexture(GMT.U(GMT.C.gold))
    tShine:SetAlpha(0.40)

    --    TITLE TEXT                                         
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("LEFT", f, "TOPLEFT", 18, -(8 + TBAR_H/2) + 10)
    title:SetText("|cffcf9030Guild|r|cff19f580Master|r|cff9a8060 Tools|r")

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("LEFT", f, "TOPLEFT", 20, -(8 + TBAR_H/2) - 12)
    sub:SetTextColor(0.75, 0.62, 0.38, 1.0)
    sub:SetText("Guild Leadership & Management Suite")

    local ver = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, -(8 + TBAR_H/2) - 4)
    ver:SetTextColor(GMT.U(GMT.C.txtDim))
    ver:SetText("v" .. GMT.VERSION)

    GMT.Rivets(f, 9, 14)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    --    TAB BAR                                            
    local TAB_W = math.floor((FW - PAD * 2) / #TABS)
    local TAB_Y = -(8 + TBAR_H + 3)

    for i, def in ipairs(TABS) do
        local tb = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        tb:SetSize(TAB_W, TAB_H - 2)
        tb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * TAB_W, TAB_Y)
        tb:SetText(def.label)

        if tb:GetNormalTexture()    then tb:GetNormalTexture():SetVertexColor(0.55, 0.33, 0.11) end
        if tb:GetHighlightTexture() then tb:GetHighlightTexture():SetVertexColor(0.88, 0.58, 0.22, 0.55) end
        if tb:GetPushedTexture()    then tb:GetPushedTexture():SetVertexColor(0.36, 0.22, 0.07) end
        tb:GetFontString():SetTextColor(GMT.U(GMT.C.amber))

        -- Active indicator line
        local indicator = f:CreateTexture(nil, "OVERLAY")
        indicator:SetSize(TAB_W - 4, 3)
        indicator:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 2, 0)
        indicator:SetColorTexture(GMT.U(GMT.C.green))
        indicator:SetAlpha(0.90)
        indicator:Hide()

        -- Content panel   explicit SetSize so GetWidth() is valid
        local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        panel:SetSize(PW, PH)
        panel:SetPoint("TOPLEFT", f, "TOPLEFT", PX, PY)
        panel:SetBackdrop({
            bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile=true, tileSize=32, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        panel:SetBackdropColor(GMT.U(GMT.C.panelBg))
        panel:SetBackdropBorderColor(GMT.U(GMT.C.brass))
        panel:Hide()

        GMT.Rivets(panel, 7, 5)

        panels[def.key]   = panel
        tabBtns[def.key]  = tb
        tabLines[def.key] = indicator

        tb:SetScript("OnClick", function() GMT_ShowTab(def.key) end)
    end

    -- Tab-bar bottom pipe divider
    local divY = -(8 + TBAR_H + TAB_H + 2)
    GMT.HLine(f, PAD, divY, FW - PAD * 2)

    local defTab = (GMT.DB and GMT.DB.settings and GMT.DB.settings.defaultTab) or "Home"
    GMT_ShowTab(defTab)

    GMT.Debug("UI built v2.8.1  PW=" .. PW .. " PH=" .. PH)
end
