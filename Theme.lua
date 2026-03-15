-- GuildMasterTools Theme.lua
-- Centralised colour / font / sizing constants

GMT.C = {
    -- Primary palette
    gold        = "ffcf9030",
    green       = "ff00ff98",
    red         = "ffff4444",
    white       = "ffffffff",
    grey        = "ff888888",
    darkGrey    = "ff444444",
    blue        = "ff4488ff",
    purple      = "ffaa44ff",

    -- Backgrounds
    bgDark      = { r=0.05, g=0.05, b=0.08, a=0.95 },
    bgMid       = { r=0.08, g=0.08, b=0.13, a=0.90 },
    bgLight     = { r=0.13, g=0.13, b=0.18, a=0.85 },

    -- Borders
    border      = { r=0.25, g=0.20, b=0.10, a=1.0 },
    borderHover = { r=0.80, g=0.57, b=0.19, a=1.0 },

    -- Accents
    accent      = { r=0.81, g=0.56, b=0.19, a=1.0 },
    accentGreen = { r=0.00, g=1.00, b=0.60, a=1.0 },
}

-- Font sizes
GMT.F = {
    tiny    = 9,
    small   = 11,
    normal  = 13,
    large   = 15,
    title   = 18,
    header  = 22,
}

-- Layout constants (pixels)
GMT.L = {
    frameW      = 860,
    frameH      = 600,
    tabH        = 32,
    tabPad      = 12,
    panelPad    = 10,
    btnH        = 24,
    btnW        = 120,
    rowH        = 20,
    scrollW     = 16,
}

-- ── Convenience colour-wrap ────────────────────────────────────────────────
function GMT.Col(hex, text)
    return "|c" .. hex .. text .. "|r"
end

-- ── Set a texture/region background colour from a GMT.C table entry ────────
function GMT.SetBGColor(region, col)
    if not region or not col then return end
    region:SetColorTexture(col.r, col.g, col.b, col.a)
end

-- ── Apply standard backdrop to a frame ────────────────────────────────────
function GMT.ApplyBackdrop(frame, bgCol, borderCol)
    bgCol     = bgCol     or GMT.C.bgDark
    borderCol = borderCol or GMT.C.border

    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left=3, right=3, top=3, bottom=3 },
    })
    frame:SetBackdropColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
    frame:SetBackdropBorderColor(borderCol.r, borderCol.g, borderCol.b, borderCol.a)
end
