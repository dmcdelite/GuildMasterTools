-- ============================================================
-- GuildMaster Tools  |  Theme.lua  |  v2.8.0
-- Rustbolt Goblin Engineering   full visual system
-- Palette   Primitives   Cards   Tables   Gear spinners
-- RULE: zero GetWidth/GetHeight calls   all sizes explicit
-- ============================================================
local _, GMT = ...

-- ============================================================
-- PALETTE   Goblin Engineering Instrument Panel
-- ============================================================
GMT.C = {
    --    Backgrounds                                          
    frameBg  = {0.040, 0.032, 0.020, 0.97},  -- oiled iron hull
    panelBg  = {0.058, 0.046, 0.028, 0.98},  -- dark bronze plate
    cardBg   = {0.085, 0.068, 0.040, 0.98},  -- instrument housing
    cardHead = {0.210, 0.140, 0.052, 1.00},  -- burnished header
    rowAlt   = {0.130, 0.100, 0.048, 0.55},  -- alternating row tint
    rowSel   = {0.180, 0.220, 0.060, 0.70},  -- selected row

    --    Metal accents                                         
    copper   = {0.820, 0.520, 0.220, 1.00},  -- fresh copper pipe
    brass    = {0.660, 0.530, 0.260, 1.00},  -- aged brass trim
    gold     = {0.940, 0.740, 0.120, 1.00},  -- goblin coin gold
    rivet    = {0.540, 0.475, 0.340, 1.00},  -- hex bolt
    iron     = {0.200, 0.170, 0.130, 1.00},  -- cold iron edge
    rust     = {0.520, 0.200, 0.060, 1.00},  -- oxidised danger

    --    Status LEDs (saturated, bright)                      
    green    = {0.100, 0.960, 0.500, 1.00},  -- power-on green
    amber    = {0.980, 0.720, 0.080, 1.00},  -- caution amber
    red      = {0.940, 0.200, 0.080, 1.00},  -- critical red
    grey     = {0.400, 0.380, 0.340, 1.00},  -- offline grey

    --    Typography                                           
    txtTitle = {0.990, 0.820, 0.320, 1.00},  -- bright gold label
    txtBody  = {0.860, 0.820, 0.680, 1.00},  -- warm ivory text
    txtDim   = {0.460, 0.410, 0.300, 1.00},  -- subdued label
    txtGreen = {0.100, 0.960, 0.500, 1.00},  -- live-data green
    txtAmber = {0.980, 0.720, 0.080, 1.00},  -- warning value
}

-- Unpack rgba: GMT.U(GMT.C.copper)   r,g,b,a
local function U(c) return c[1], c[2], c[3], c[4] end
GMT.U = U

-- ============================================================
-- CLASS COLORS
-- ============================================================
function GMT.ClassHex(cf)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
    if c then return string.format("|cff%02x%02x%02x", c.r*255, c.g*255, c.b*255) end
    return "|cffbbbbbb"
end
function GMT.ClassStr(cf, text)
    return GMT.ClassHex(cf) .. (text or cf) .. "|r"
end

-- ============================================================
-- STRING UTILITIES
-- ============================================================
function GMT.Short(n)  return n and n:match("^([^%-]+)") or n end
function GMT.Clip(s,n) s=tostring(s or ""); return #s>n and s:sub(1,n-2)..".." or s end
function GMT.Clock()   return date("%H:%M:%S") end

function GMT.Green(s)  return "|cff19f580"..s.."|r" end
function GMT.Amber(s)  return "|cffcf9030"..s.."|r" end
function GMT.Red(s)    return "|cffee3316"..s.."|r" end
function GMT.Grey(s)   return "|cff706858"..s.."|r" end
function GMT.Dim(s)    return "|cff6a5f48"..s.."|r" end
function GMT.Gold(s)   return "|cffdd5535"..s.."|r" end

-- ============================================================
--    PRIMITIVES                                               
-- Every function takes EXPLICIT pixel values   no GetWidth()
-- ============================================================

--    Four hex-bolt rivets on corners                          
function GMT.Rivets(frame, size, pad)
    pad  = pad  or 5
    size = size or 7
    local corners = {
        {"TOPLEFT",      pad,  -pad},
        {"TOPRIGHT",    -pad,  -pad},
        {"BOTTOMLEFT",   pad,   pad},
        {"BOTTOMRIGHT", -pad,   pad},
    }
    for _, c in ipairs(corners) do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetSize(size, size)
        t:SetPoint(c[1], frame, c[1], c[2], c[3])
        t:SetTexture("Interface/MINIMAP/UI-Minimap-ZoomButton-Up")
        t:SetVertexColor(U(GMT.C.rivet))
        t:SetAlpha(0.92)
    end
end

--    Single rivet at explicit position                        
function GMT.Rivet(frame, x, y, size)
    size = size or 7
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    t:SetPoint("CENTER", frame, "TOPLEFT", x, y)
    t:SetTexture("Interface/MINIMAP/UI-Minimap-ZoomButton-Up")
    t:SetVertexColor(U(GMT.C.rivet))
    t:SetAlpha(0.88)
    return t
end

--    Copper pipe divider (3-layer: shadow / body / highlight)  
-- w is REQUIRED
function GMT.HLine(parent, x, y, w, r, g, b, a)
    r = r or GMT.C.copper[1]
    g = g or GMT.C.copper[2]
    b = b or GMT.C.copper[3]
    a = a or 0.80
    -- Bottom shadow
    local sh = parent:CreateTexture(nil, "BACKGROUND")
    sh:SetSize(w, 1)
    sh:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 2)
    sh:SetColorTexture(0, 0, 0, 0.55)
    -- Main bar
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetSize(w, 3)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    bar:SetColorTexture(r, g, b, a)
    -- Top highlight
    local hi = parent:CreateTexture(nil, "OVERLAY")
    hi:SetSize(w, 1)
    hi:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    hi:SetColorTexture(U(GMT.C.gold))
    hi:SetAlpha(0.35)
    return bar
end

--    Thin accent line (1px, configurable)                     
function GMT.ThinLine(parent, x, y, w, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(w, 1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetColorTexture(r or U(GMT.C.copper))
    if a then t:SetAlpha(a) end
    return t
end

--    Vertical pipe rule                                       
function GMT.VLine(parent, x, y, h)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(2, h)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetColorTexture(U(GMT.C.copper))
    t:SetAlpha(0.60)
    return t
end

--    LED indicator dot                                         
-- Returns the dot texture so caller can call :SetVertexColor()
function GMT.LED(parent, x, y, size, c)
    size = size or 8
    c    = c    or GMT.C.green
    -- Dark ring
    local ring = parent:CreateTexture(nil, "ARTWORK")
    ring:SetSize(size + 4, size + 4)
    ring:SetPoint("CENTER", parent, "TOPLEFT", x, y)
    ring:SetTexture("Interface/MINIMAP/UI-Minimap-ZoomButton-Up")
    ring:SetVertexColor(0.06, 0.05, 0.03)
    ring:SetAlpha(0.90)
    -- Lit dot
    local dot = parent:CreateTexture(nil, "OVERLAY")
    dot:SetSize(size, size)
    dot:SetPoint("CENTER", parent, "TOPLEFT", x, y)
    dot:SetTexture("Interface/MINIMAP/UI-Minimap-ZoomButton-Up")
    dot:SetVertexColor(U(c))
    return dot
end

--    Animated gear spinner                                      
-- Returns the frame; caller calls :SetPoint()
function GMT.Gear(parent, size, speed, ccw, icon)
    size  = size  or 48
    speed = speed or 8
    icon  = icon  or "Interface/ICONS/Trade_Engineering"
    local sf = CreateFrame("Frame", nil, parent)
    sf:SetSize(size, size)
    local tex = sf:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(icon)
    tex:SetDesaturated(true)
    tex:SetVertexColor(U(GMT.C.copper))
    local ag  = sf:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local rot = ag:CreateAnimation("Rotation")
    rot:SetOrigin("CENTER", 0, 0)
    rot:SetDegrees(ccw and -360 or 360)
    rot:SetDuration(speed)
    rot:SetSmoothing("NONE")
    ag:Play()
    sf.ag  = ag
    sf.tex = tex
    return sf
end

--    Gear with decorative ring behind it                       
-- Returns a container frame sized to ringSize
function GMT.GearRing(parent, gearSize, ringSize, speed, ccw, icon)
    gearSize = gearSize or 48
    ringSize = ringSize or gearSize + 16
    local cf = CreateFrame("Frame", nil, parent)
    cf:SetSize(ringSize, ringSize)
    -- Ring texture
    local ring = cf:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints()
    ring:SetTexture("Interface/MINIMAP/MiniMap-TrackingBorder")
    ring:SetVertexColor(U(GMT.C.brass))
    ring:SetAlpha(0.45)
    -- Gear centered inside ring
    local g = GMT.Gear(cf, gearSize, speed, ccw, icon)
    g:SetPoint("CENTER", cf, "CENTER", 0, 0)
    cf.gear = g
    cf.ring = ring
    return cf
end

--    Metallic copper-tinted button                             
-- Returns Button; caller calls :SetPoint()
function GMT.MBtn(parent, label, w, h)
    w = w or 150
    h = h or 26
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, h)
    btn:SetText(label)
    local fs = btn:GetFontString()
    if fs then
        fs:SetWidth(math.max(1, w - 10))
        fs:SetWordWrap(true)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
    end
    local nt = btn:GetNormalTexture()
    local ht = btn:GetHighlightTexture()
    local pt = btn:GetPushedTexture()
    if nt then nt:SetVertexColor(0.620, 0.370, 0.110) end
    if ht then ht:SetVertexColor(0.900, 0.640, 0.220, 0.60) end
    if pt then pt:SetVertexColor(0.380, 0.220, 0.070) end
    btn:GetFontString():SetTextColor(U(GMT.C.gold))
    return btn
end

--    Section header text with copper underline                 
function GMT.Header(parent, text, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 14, y or -14)
    fs:SetTextColor(U(GMT.C.txtTitle))
    fs:SetText(text)
    return fs
end

--    Subdued label                                             
function GMT.Label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 14, y or -14)
    fs:SetTextColor(U(GMT.C.txtDim))
    fs:SetText(text)
    return fs
end

-- ============================================================
-- SECTION BOX   decorated container with header stripe
-- Global version usable by all modules
-- Returns the box frame
-- ============================================================
function GMT.Section(parent, title, x, y, w, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    box:SetBackdropColor(U(GMT.C.cardBg))
    box:SetBackdropBorderColor(U(GMT.C.copper))

    -- Header stripe
    local head = box:CreateTexture(nil, "BACKGROUND")
    head:SetPoint("TOPLEFT",  box, "TOPLEFT",   3, -3)
    head:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -3)
    head:SetHeight(24)
    head:SetColorTexture(U(GMT.C.cardHead))

    -- Header bottom divider (pipe)
    local hdiv = box:CreateTexture(nil, "ARTWORK")
    hdiv:SetPoint("TOPLEFT",  box, "TOPLEFT",   3, -27)
    hdiv:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -27)
    hdiv:SetHeight(2)
    hdiv:SetColorTexture(U(GMT.C.copper))
    hdiv:SetAlpha(0.85)
    local hshine = box:CreateTexture(nil, "OVERLAY")
    hshine:SetPoint("TOPLEFT",  box, "TOPLEFT",   3, -25)
    hshine:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -25)
    hshine:SetHeight(1)
    hshine:SetColorTexture(U(GMT.C.gold))
    hshine:SetAlpha(0.30)

    -- Title
    local tf = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tf:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -7)
    tf:SetTextColor(U(GMT.C.txtTitle))
    tf:SetText(title)

    GMT.Rivets(box, 6, 4)
    return box
end

-- ============================================================
-- STAT CARD   instrument panel with label/value rows
-- Returns card frame + indexed value FontString table
-- ============================================================
function GMT.Card(parent, title, rows, x, y, w, h)
    w = (w and w > 0) and w or 460
    h = (h and h > 0) and h or 150

    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(w, h)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetBackdrop({
        bgFile   = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile=true, tileSize=32, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3},
    })
    card:SetBackdropColor(U(GMT.C.cardBg))
    card:SetBackdropBorderColor(U(GMT.C.copper))

    -- Header stripe
    local hbg = card:CreateTexture(nil, "BACKGROUND")
    hbg:SetPoint("TOPLEFT",  card, "TOPLEFT",   3, -3)
    hbg:SetPoint("TOPRIGHT", card, "TOPRIGHT", -3, -3)
    hbg:SetHeight(26)
    hbg:SetColorTexture(U(GMT.C.cardHead))

    -- Header bottom: 2px copper + 1px gold shimmer
    local hd = card:CreateTexture(nil, "ARTWORK")
    hd:SetPoint("TOPLEFT",  card, "TOPLEFT",   3, -29)
    hd:SetPoint("TOPRIGHT", card, "TOPRIGHT", -3, -29)
    hd:SetHeight(2)
    hd:SetColorTexture(U(GMT.C.copper))
    hd:SetAlpha(0.90)
    local hs = card:CreateTexture(nil, "OVERLAY")
    hs:SetPoint("TOPLEFT",  card, "TOPLEFT",   3, -27)
    hs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -3, -27)
    hs:SetHeight(1)
    hs:SetColorTexture(U(GMT.C.gold))
    hs:SetAlpha(0.28)

    -- Title text
    local tf = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tf:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
    tf:SetTextColor(U(GMT.C.txtTitle))
    tf:SetText(title)

    GMT.Rivets(card, 6, 4)

    -- Rows
    local vals   = {}
    local ROW_H  = 20
    local Y0     = -36
    local LX     = 10
    local VX     = math.floor(w * 0.52)
    local LWIDTH = VX - LX - 4          -- label max width
    local VWIDTH = w - VX - 8           -- value max width

    for i, row in ipairs(rows or {}) do
        local ry = Y0 - (i-1) * ROW_H

        -- Alternating stripe
        if i % 2 == 0 then
            local stripe = card:CreateTexture(nil, "BACKGROUND")
            stripe:SetSize(w - 8, ROW_H)
            stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 4, ry)
            stripe:SetColorTexture(U(GMT.C.rowAlt))
        end

        local lbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", card, "TOPLEFT", LX, ry - 2)
        lbl:SetWidth(LWIDTH)
        lbl:SetTextColor(U(GMT.C.txtDim))
        lbl:SetText((row.k or "") .. ":")

        local val = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPLEFT", card, "TOPLEFT", VX, ry - 2)
        val:SetWidth(VWIDTH)
        val:SetJustifyH("LEFT")
        val:SetTextColor(U(GMT.C.txtGreen))
        val:SetText("--")
        vals[i] = val
    end

    return card, vals
end

-- ============================================================
-- SCROLL TABLE   header bar + scrollable row pool
-- cols = { {label, w, j},   }
-- tw, th = explicit pixel dimensions   REQUIRED
-- Returns update(data) function
-- ============================================================
function GMT.Table(parent, cols, x, y, tw, th)
    local ROW_H = 20
    local HDR_H = 22

    -- Header
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetSize(tw, HDR_H)
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(U(GMT.C.cardHead))

    -- Copper divider below header
    local hdl = hdr:CreateTexture(nil, "ARTWORK")
    hdl:SetSize(tw, 2)
    hdl:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
    hdl:SetColorTexture(U(GMT.C.copper))
    hdl:SetAlpha(0.85)
    local hsh = hdr:CreateTexture(nil, "OVERLAY")
    hsh:SetSize(tw, 1)
    hsh:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 2)
    hsh:SetColorTexture(U(GMT.C.gold))
    hsh:SetAlpha(0.22)

    local cx = 4
    for _, col in ipairs(cols) do
        local lbl = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", hdr, "LEFT", cx, 0)
        lbl:SetWidth(col.w - 6)
        lbl:SetJustifyH(col.j or "LEFT")
        lbl:SetText(col.label)
        lbl:SetTextColor(U(GMT.C.txtTitle))
        cx = cx + col.w
    end

    -- Scroll frame
    local scrollH = th - HDR_H - 4
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetSize(tw - 18, scrollH)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - HDR_H - 2)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(tw - 18, ROW_H)
    sf:SetScrollChild(content)

    local pool = {}

    local function ensureRows(n)
        for i = #pool + 1, n do
            local row = {}
            local rx  = 4
            for _, col in ipairs(cols) do
                local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", content, "TOPLEFT", rx, -((i-1)*ROW_H) - 3)
                fs:SetWidth(col.w - 8)
                fs:SetJustifyH(col.j or "LEFT")
                fs:Hide()
                rx = rx + col.w
                row[#row+1] = fs
            end
            if i % 2 == 0 then
                local rbg = content:CreateTexture(nil, "BACKGROUND")
                rbg:SetSize(tw - 22, ROW_H)
                rbg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i-1)*ROW_H))
                rbg:SetColorTexture(U(GMT.C.rowAlt))
            end
            pool[i] = row
        end
    end

    local function update(data)
        for _, row in ipairs(pool) do
            for _, fs in ipairs(row) do fs:Hide() end
        end
        if not data or #data == 0 then content:SetHeight(ROW_H); return end
        ensureRows(#data)
        for i, rowData in ipairs(data) do
            for j, fs in ipairs(pool[i]) do
                fs:SetText(rowData[j] or "")
                fs:Show()
            end
        end
        content:SetHeight(math.max(ROW_H, #data * ROW_H))
    end

    return update
end
