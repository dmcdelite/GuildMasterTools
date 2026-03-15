-- GuildMasterTools UI.lua
-- Builds the main frame, tab bar, and panel container.

local L = GMT.L
local C = GMT.C
local F = GMT.F

-- Tab definitions  (name used as panel key and display label)
local TABS = {
    { id="Home",         label="Home"         },
    { id="Members",      label="Members"      },
    { id="Recruitment",  label="Recruitment"  },
    { id="RaidReadiness",label="Raid Readiness"},
    { id="RaidPerf",     label="Raid Perf"    },
    { id="TalentMap",    label="Talent Map"   },
    { id="Logistics",    label="Logistics"    },
    { id="Economy",      label="Economy"      },
    { id="Events",       label="Events"       },
    { id="GuildSync",    label="Guild Sync"   },
    { id="Options",      label="Options"      },
}

local panels = {}   -- id → ScrollFrame/content frame
local tabBtns = {}  -- id → Button

-- ── Helper: create a labelled section header inside a panel ───────────────
function GMT_SectionHeader(parent, text, yOff)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff or 0)
    fs:SetText("|cff" .. C.gold .. text .. "|r")
    return fs
end

-- ── Create a scrollable content panel ─────────────────────────────────────
local function makePanel(id)
    local sf = CreateFrame("ScrollFrame", "GMT_Panel_" .. id,
                           GMT_ContentArea, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     GMT_ContentArea, "TOPLEFT",  0, 0)
    sf:SetPoint("BOTTOMRIGHT", GMT_ContentArea, "BOTTOMRIGHT", -L.scrollW, 0)
    sf:Hide()

    local content = CreateFrame("Frame", "GMT_PanelContent_" .. id, sf)
    content:SetSize(GMT_ContentArea:GetWidth() - L.scrollW - 4, 1200)
    sf:SetScrollChild(content)

    panels[id] = sf
    sf._content = content
    return sf
end

-- ── Switch visible tab ─────────────────────────────────────────────────────
local function selectTab(id)
    for tid, panel in pairs(panels) do
        if tid == id then
            panel:Show()
        else
            panel:Hide()
        end
    end
    for tid, btn in pairs(tabBtns) do
        if tid == id then
            btn:SetNormalFontObject("GameFontHighlightSmall")
            btn:GetNormalTexture():SetColorTexture(
                C.accent.r, C.accent.g, C.accent.b, 0.35)
        else
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:GetNormalTexture():SetColorTexture(0, 0, 0, 0)
        end
    end
end

-- ── Public: get panel content frame by id ─────────────────────────────────
function GMT_GetPanel(id)
    local sf = panels[id]
    if sf then return sf._content end
    return nil
end

-- ── Public: get the scroll frame itself ───────────────────────────────────
function GMT_GetScrollFrame(id)
    return panels[id]
end

-- ── Build everything ───────────────────────────────────────────────────────
function GMT_BuildUI()
    -- ── Main frame ──────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "GMT_MainFrame", UIParent,
                          "BackdropTemplate")
    f:SetSize(L.frameW, L.frameH)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    GMT.ApplyBackdrop(f)

    -- ── Title bar ───────────────────────────────────────────────────────
    local titleBar = f:CreateTexture(nil, "BACKGROUND")
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  2, -2)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    titleBar:SetHeight(30)
    GMT.SetBGColor(titleBar, C.bgMid)

    local titleTxt = f:CreateFontString(nil, "OVERLAY")
    titleTxt:SetFont("Fonts/FRIZQT__.TTF", F.title, "OUTLINE")
    titleTxt:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleTxt:SetText(
        "|cff" .. C.gold  .. "Guild" ..
        "|cff" .. C.green .. "Master" ..
        "|r Tools  |cff" .. C.grey .. "v" .. GMT.VERSION .. "|r")

    -- ── Close button ────────────────────────────────────────────────────
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ── Tab bar ─────────────────────────────────────────────────────────
    local tabBar = CreateFrame("Frame", "GMT_TabBar", f)
    tabBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  2, -32)
    tabBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -32)
    tabBar:SetHeight(L.tabH)
    local tabBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBg:SetAllPoints()
    GMT.SetBGColor(tabBg, C.bgMid)

    local xOff = 4
    for _, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", "GMT_Tab_" .. tab.id, tabBar)
        btn:SetHeight(L.tabH - 4)
        btn:SetPoint("LEFT", tabBar, "LEFT", xOff, 0)

        -- measure text width
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(tab.label)
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        local tw = fs:GetStringWidth() + L.tabPad * 2
        btn:SetWidth(tw)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        btn:SetNormalTexture(bg)

        btn:SetFontString(fs)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")

        local tabId = tab.id
        btn:SetScript("OnClick", function() selectTab(tabId) end)

        tabBtns[tab.id] = btn
        xOff = xOff + tw + 2
    end

    -- ── Content area ────────────────────────────────────────────────────
    local ca = CreateFrame("Frame", "GMT_ContentArea", f)
    ca:SetPoint("TOPLEFT",     f, "TOPLEFT",     L.panelPad,       -(32 + L.tabH + L.panelPad))
    ca:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -L.panelPad,       L.panelPad)

    -- ── Build a panel for every tab ──────────────────────────────────────
    for _, tab in ipairs(TABS) do
        makePanel(tab.id)
    end

    -- Show first tab by default
    selectTab(TABS[1].id)

    f:Hide()
end
