-- PadBar: the other half of wow-pad. wow-pad turns the controller into fixed keys nobody types;
-- this binds them, per layer (L2 = Alt, R2 = Ctrl), to hidden secure buttons holding your spells,
-- and draws a small PS5 cluster of them like the Gamepad UI's. WoW never sees a gamepad, so none of
-- the Gamepad UI runs and nothing taints. Key names are learned from wow-pad (/padbar learn).
local ADDON = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

-- The order wow-pad --calibrate sends its keys in (pad.swift `calibration`): buttons, then movement.
local ORDER = { "cross", "circle", "square", "triangle", "up", "down", "left", "right",
                "l1", "r1", "l3", "r3", "create", "touch", "fwd", "back", "sleft", "sright", "walk",
                "tleft", "tright", "pup", "pdown", "run" }
local MOVES = { fwd = "MOVEFORWARD", back = "MOVEBACKWARD", sleft = "STRAFELEFT", sright = "STRAFERIGHT",
                tleft = "TURNLEFT", tright = "TURNRIGHT" }
local PITCH_SPEED = 0.5   -- right stick up/down: camera tilt speed (MoveViewUp/Down)
local INVERT_Y = true     -- stick up tilts the camera down (as flight controls do)

-- id, glyph texture (or text), x, y, size: two diamonds, bumpers above, sticks/center below
local S, M = 46, 34
local BUTTONS = {
    { "triangle", "triangle",  118,  46, S }, { "cross", "cross",  118, -46, S },
    { "square",   "square",     72,   0, S }, { "circle", "circle", 164,  0, S },
    { "up",       "arrow",    -118,  46, S, 0 }, { "down", "arrow", -118, -46, S, math.pi },
    { "left",     "arrow",    -164,   0, S, math.pi / 2 }, { "right", "arrow", -72, 0, S, -math.pi / 2 },
    { "l1",       "L1",       -118, 100, M }, { "r1", "R1",  118, 100, M },
    { "l3",       "L3",        -40, -70, M }, { "r3", "R3",   40, -70, M },
    { "create",   "CR",        -26,  30, M }, { "touch", "PAD", 26, 30, M },
}
local GLYPH_COLOR = { cross = { 0.45, 0.65, 1 }, circle = { 1, 0.4, 0.4 }, square = { 1, 0.55, 0.85 }, triangle = { 0.3, 0.9, 0.7 } }
local LAYERS = { { "", "Base" }, { "ALT-", "L2" }, { "CTRL-", "R2" }, { "ALT-CTRL-", "L2+R2" } }

local owner = CreateFrame("Frame")
-- camera tilt while the key is held (MoveView* is allowed from addon code; TurnLeftStart isn't, so
-- turning goes through WoW's TURNLEFT/TURNRIGHT bindings above)
local pitch = {}
for id, dir in pairs(INVERT_Y and { pup = "Down", pdown = "Up" } or { pup = "Up", pdown = "Down" }) do
    local b = CreateFrame("Button", "PadBarPitch" .. dir, UIParent)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetScript("OnClick", function(_, _, down)
        if down then _G["MoveView" .. dir .. "Start"](PITCH_SPEED) else _G["MoveView" .. dir .. "Stop"]() end
    end)
    pitch[id] = b
end
local pad, slots, secure = nil, {}, {}
local editLayer, pending = 1, false
-- Walk/run: WoW has only a toggle, which addons can't press. wow-pad sends what the stick wants (the
-- "walk" or "run" key); only the one that changes the mode you're in is bound to TOGGLERUN, so asking
-- for the mode you're already in does nothing. Which mode you're in is read from your speed.
local walking = false
local walkBound   -- the request key bound to TOGGLERUN right now

local function Print(msg) print("|cff7fb2ffPadBar|r: " .. msg) end
-- WoW actions the base layer starts with, like the Gamepad UI's (a dropped spell replaces one;
-- right-click turns it off)
local BACK = { type = "macrotext", back = true, icon = "act_back", name = "Back: close an NPC dialog, else stop attacking and clear target",
               text = "/stopattack\n/cleartarget" }
local DEFAULTS = { cross = "JUMP", square = "INTERACTTARGET", l1 = "TARGETNEARESTFRIEND", r1 = "TARGETNEARESTENEMY", circle = BACK }
local BINDING_ICONS = {   -- our own (media/act_*), so WoW actions don't look like spells
    JUMP = MEDIA .. "act_jump", INTERACTTARGET = MEDIA .. "act_interact",
    TARGETNEARESTFRIEND = MEDIA .. "act_friend", TARGETNEARESTENEMY = MEDIA .. "act_enemy",
}
-- what a button does: its assignment, else its default ("none": a default turned off)
local function Assign(layer, id)
    local a = PadBarDB.assign[layer] and PadBarDB.assign[layer][id]
    if a then return a.type ~= "none" and a or nil end
    local d = layer == 1 and DEFAULTS[id]
    if type(d) == "table" then return d end
    if d then return { type = "binding", cmd = d } end
end
local function Key(id)
    for i, name in ipairs(ORDER) do if name == id then return PadBarKeys and PadBarKeys[i] end end
end

local function Icon(a)
    if not a then return nil end
    if a.type == "spell" then return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(a.id) or GetSpellTexture and GetSpellTexture(a.id) end
    if a.type == "item" then return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(a.id) or GetItemIcon and GetItemIcon(a.id) end
    if a.type == "macro" then return select(2, GetMacroInfo(a.id)) end
    if a.type == "macrotext" then return MEDIA .. a.icon end
    if a.type == "binding" then return BINDING_ICONS[a.cmd] or "Interface\\Icons\\INV_Misc_QuestionMark" end
end

local function Cooldown(a)
    if not a then return end
    if a.type == "spell" and C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(a.id)
        if type(info) == "table" then return info.startTime, info.duration end
    elseif a.type == "item" then
        local get = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        if get then return get(a.id) end
    end
end

-- held L2/R2 show their layer, else the tab being edited
local function ShownLayer()
    local alt, ctrl = IsAltKeyDown(), IsControlKeyDown()
    if alt and ctrl then return 4 elseif alt then return 2 elseif ctrl then return 3 end
    return editLayer
end

local function Refresh()
    if not pad then return end
    local layer = ShownLayer()
    for _, b in ipairs(BUTTONS) do
        local s, a = slots[b[1]], Assign(layer, b[1])
        local icon = Icon(a)
        s.icon:SetTexture(icon or nil)
        s.icon:SetShown(icon ~= nil)
        s.big:SetShown(not icon)
        s.badgeBg:SetShown(icon ~= nil)
        s.badge:SetShown(icon ~= nil)
        local start, dur = Cooldown(a)
        if start then pcall(s.cd.SetCooldown, s.cd, start, dur) else s.cd:Clear() end
    end
    for i, tab in ipairs(pad.tabs) do
        local on = i == layer
        tab.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
        tab.bg:SetColorTexture(on and 0.35 or 0.05, on and 0.27 or 0.05, on and 0.05 or 0.07, on and 0.85 or 0.6)
    end
end

-- secure side: out of combat only (protected changes in combat are blocked)
local function ApplySecure(layer, id)
    local btn, a = secure[layer][id], Assign(layer, id)
    if a and a.type == "binding" then a = nil end   -- (bound straight to the key in ApplyAll)
    btn:SetAttribute("type", a and (a.type == "macrotext" and "macro" or a.type) or nil)
    btn:SetAttribute("macrotext", a and a.type == "macrotext" and a.text or nil)
    btn:SetAttribute("spell", a and a.type == "spell" and a.id or nil)
    btn:SetAttribute("item", a and a.type == "item" and ("item:" .. a.id) or nil)
    btn:SetAttribute("macro", a and a.type == "macro" and a.id or nil)
end

-- only the request that changes the mode is bound (touching just these two, so held keys stay held)
local function ApplyWalk()
    if InCombatLockdown() then pending = true return end
    local walk, run = Key("walk"), Key("run")
    walkBound = walking and run or walk
    for _, l in ipairs(LAYERS) do
        if walk then SetOverrideBinding(owner, true, l[1] .. walk, not walking and "TOGGLERUN" or nil) end
        if run then SetOverrideBinding(owner, true, l[1] .. run, walking and "TOGGLERUN" or nil) end
    end
end

-- ○'s default: with an NPC dialog open (talking, quest text, vendor, trainer, flight master, bank,
-- mail...) it ends that interaction, else its stop-attack/clear-target macro. Ending goes through the
-- game's own Close* calls: Blizzard's event handlers then hide the window, so nothing is tainted.
-- Bags and the map stay. Rebinding is out of combat only.
local DIALOGS = {
    GossipFrame = function() if C_GossipInfo and C_GossipInfo.CloseGossip then C_GossipInfo.CloseGossip() elseif CloseGossip then CloseGossip() end end,
    QuestFrame = "CloseQuest", MerchantFrame = "CloseMerchant", ClassTrainerFrame = "CloseTrainer", TaxiFrame = "CloseTaxiMap",
    BankFrame = "CloseBankFrame", MailFrame = "CloseMail", TabardFrame = "CloseTabardCreation", PetStableFrame = "ClosePetStables",
    ItemTextFrame = "CloseItemText", GuildRegistrarFrame = "CloseGuildRegistrar", PetitionFrame = "ClosePetition",
}
local function DialogOpen()
    for name in pairs(DIALOGS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end
local closer = CreateFrame("Button", "PadBarCloseDialog", UIParent)
closer:RegisterForClicks("AnyDown")
closer:SetScript("OnClick", function()
    for name, close in pairs(DIALOGS) do
        local f = _G[name]
        if f and f.IsShown and f:IsShown() then
            local fn = type(close) == "function" and close or _G[close]
            if fn then pcall(fn) end
        end
    end
end)
local backOnClose
local function UpdateBack()
    if InCombatLockdown() or not secure[1] then return end
    local key, a = Key("circle"), Assign(1, "circle")
    if not key or not (a and a.back) then return end
    local open = DialogOpen()
    if open == backOnClose then return end
    backOnClose = open
    SetOverrideBindingClick(owner, true, key, open and "PadBarCloseDialog" or secure[1].circle:GetName(), "LeftButton")
end

local function ApplyAll()
    if InCombatLockdown() then pending = true return end
    pending = false
    ClearOverrideBindings(owner)
    for layer, l in ipairs(LAYERS) do
        for _, b in ipairs(BUTTONS) do
            ApplySecure(layer, b[1])
            local key, a = Key(b[1]), Assign(layer, b[1])
            if key and a and a.type == "binding" then SetOverrideBinding(owner, true, l[1] .. key, a.cmd)
            elseif key then SetOverrideBindingClick(owner, true, l[1] .. key, secure[layer][b[1]]:GetName(), "LeftButton") end
        end
        for id, action in pairs(MOVES) do
            local key = Key(id)
            if key then SetOverrideBinding(owner, true, l[1] .. key, action) end
        end
        for id, b in pairs(pitch) do
            local key = Key(id)
            if key then SetOverrideBindingClick(owner, true, l[1] .. key, b:GetName(), "LeftButton") end
        end
    end
    ApplyWalk()
    backOnClose = nil
    UpdateBack()
end

local function SetAssign(layer, id, a)
    if InCombatLockdown() then Print("can't change buttons in combat.") return end
    PadBarDB.assign[layer] = PadBarDB.assign[layer] or {}
    PadBarDB.assign[layer][id] = a
    ApplyAll()   -- (a WoW action is bound to the key itself, a spell through its button)
    Refresh()
end

-- whatever is on the cursor (from the spellbook, bags or macros)
local function CursorAssign()
    local kind, id, _, extra = GetCursorInfo()
    if kind == "spell" then return { type = "spell", id = extra or id }
    elseif kind == "item" then return { type = "item", id = id }
    elseif kind == "macro" then return { type = "macro", id = id } end
end

local function Drop(slot)
    local a = CursorAssign()
    if not a then return end
    SetAssign(ShownLayer(), slot.id, a)   -- the layer on screen: the tab, or the one L2/R2 hold
    ClearCursor()
end

local function Tooltip(slot)
    local a = Assign(ShownLayer(), slot.id)
    GameTooltip:SetOwner(slot, "ANCHOR_TOP")
    if a and a.type == "spell" then GameTooltip:SetSpellByID(a.id)
    elseif a and a.type == "item" then GameTooltip:SetItemByID(a.id)
    elseif a and a.type == "macro" then GameTooltip:SetText(GetMacroInfo(a.id) or "Macro")
    elseif a and a.type == "binding" then GameTooltip:SetText(GetBindingText(a.cmd, "BINDING_NAME_"))
    elseif a and a.type == "macrotext" then GameTooltip:SetText(a.name)
    else GameTooltip:SetText("Drag a spell, item or macro here") end
    GameTooltip:AddLine("Layer " .. LAYERS[ShownLayer()][2] .. ": hold L2/R2 or pick a tab. Right-click clears.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- a PS glyph (texture, coloured) or a short label
local function Glyph(parent, b, size, layer)
    if b[2] == "arrow" or GLYPH_COLOR[b[2]] then
        local t = parent:CreateTexture(nil, layer or "OVERLAY")
        t:SetTexture(MEDIA .. b[2])
        t:SetSize(size, size)
        local c = GLYPH_COLOR[b[2]] or { 0.9, 0.9, 0.9 }
        t:SetVertexColor(c[1], c[2], c[3])
        if b[6] then t:SetRotation(b[6]) end
        return t
    end
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(b[2])
    return fs
end

local function Disc(parent, layer, size, r, g, bl, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(MEDIA .. "disc")
    t:SetSize(size, size)
    t:SetVertexColor(r, g, bl, a)
    return t
end

local function Build()
    pad = CreateFrame("Frame", "PadBarFrame", UIParent)
    pad:SetSize(400, 250)
    pad:SetFrameStrata("MEDIUM")
    pad:SetMovable(true)
    pad:SetClampedToScreen(true)
    local pos = PadBarDB.pos
    if pos then pad:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else pad:SetPoint("CENTER") end

    -- drag grip (top centre)
    local grip = CreateFrame("Button", nil, pad)
    grip:SetSize(70, 14)
    grip:SetPoint("CENTER", 0, 72)
    grip.t = grip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    grip.t:SetPoint("CENTER")
    grip.t:SetText("· · · ·")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() if not PadBarDB.locked then pad:StartMoving() end end)
    grip:SetScript("OnDragStop", function()
        pad:StopMovingOrSizing()
        local p, _, rp, x, y = pad:GetPoint()
        PadBarDB.pos = { p, rp, x, y }
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText("Drag to move. /padbar lock") GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)

    for _, b in ipairs(BUTTONS) do
        local size = b[5]
        local s = CreateFrame("Button", nil, pad)
        s.id = b[1]
        s:SetSize(size, size)
        s:SetPoint("CENTER", b[3], b[4])
        s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        s.bg = Disc(s, "BACKGROUND", size, 0.05, 0.05, 0.07, 0.75)
        s.bg:SetPoint("CENTER")
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(size - 4, size - 4)
        s.icon:SetPoint("CENTER")
        s.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        s.ring = s:CreateTexture(nil, "OVERLAY", nil, 1)
        s.ring:SetTexture(MEDIA .. "ring")
        s.ring:SetAllPoints()
        s.ring:SetVertexColor(0.55, 0.5, 0.4, 0.9)
        s.big = Glyph(s, b, size * 0.5, "ARTWORK")          -- the glyph alone while empty
        s.big:SetPoint("CENTER")
        local bs = size >= S and 20 or 16                    -- the glyph badge over an icon
        s.badgeBg = Disc(s, "OVERLAY", bs, 0.02, 0.02, 0.03, 0.95)
        s.badgeBg:SetDrawLayer("OVERLAY", 2)
        s.badgeBg:SetPoint("CENTER", s, "BOTTOMRIGHT", -5, 5)
        s.badge = Glyph(s, b, bs * 0.7)
        s.badge:SetDrawLayer("OVERLAY", 3)
        s.badge:SetPoint("CENTER", s.badgeBg)
        s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
        s.cd:SetPoint("CENTER")
        s.cd:SetSize(size - 4, size - 4)
        if s.cd.SetSwipeTexture then s.cd:SetSwipeTexture(MEDIA .. "disc") end
        s.flash = Disc(s, "OVERLAY", size, 1, 1, 1, 0.35)
        s.flash:SetPoint("CENTER")
        s.flash:Hide()
        s:SetScript("OnReceiveDrag", Drop)
        s:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                -- a default turns off; anything else goes back to the default (or empty)
                local layer = ShownLayer()
                local stored = PadBarDB.assign[layer] and PadBarDB.assign[layer][self.id]
                local default = layer == 1 and DEFAULTS[self.id]
                SetAssign(layer, self.id, (default and not stored) and { type = "none" } or nil)
            else Drop(self) end
        end)
        s:SetScript("OnEnter", Tooltip)
        s:SetScript("OnLeave", GameTooltip_Hide)
        slots[b[1]] = s
    end

    pad.tabs = {}
    for i, l in ipairs(LAYERS) do
        local t = CreateFrame("Button", nil, pad)
        t:SetSize(58, 22)
        t:SetPoint("CENTER", (i - 2.5) * 62, -110)
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        t:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.text:SetPoint("CENTER")
        t.text:SetText(l[2])
        t:SetScript("OnClick", function() editLayer = i Refresh() end)
        pad.tabs[i] = t
    end
    pad:SetShown(not PadBarDB.hidden)
end

local function MakeSecure()
    for layer in ipairs(LAYERS) do
        secure[layer] = {}
        for _, b in ipairs(BUTTONS) do
            local btn = CreateFrame("Button", "PadBarSecure" .. layer .. b[1], UIParent, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10, -10)
            btn:SetAlpha(0)
            btn:SetAttribute("useOnKeyDown", true)
            btn:RegisterForClicks("AnyDown")
            btn:HookScript("OnClick", function()
                local s = slots[b[1]]
                if s then s.flash:Show() C_Timer.After(0.12, function() s.flash:Hide() end) end
            end)
            secure[layer][b[1]] = btn
        end
    end
end

-- /padbar learn: the next keys pressed are wow-pad's, in ORDER (wow-pad --calibrate sends them)
local learner = CreateFrame("Frame", nil, UIParent)
learner:Hide()
learner:SetScript("OnKeyDown", function(self, key)
    if key == "LALT" or key == "RALT" or key == "LCTRL" or key == "RCTRL" or key == "LSHIFT" or key == "RSHIFT" then return end
    self.got[#self.got + 1] = key
    if #self.got == #ORDER then
        PadBarKeys = self.got
        self:Hide()
        self:EnableKeyboard(false)
        ApplyAll()
        Print("learned wow-pad's keys: " .. table.concat(PadBarKeys, " "))
    end
end)
local function Learn()
    if InCombatLockdown() then Print("not in combat.") return end
    learner.got = {}
    learner:Show()
    learner:EnableKeyboard(true)
    learner:SetPropagateKeyboardInput(false)   -- (so none of them does anything while learning)
    Print("learning: waiting for wow-pad --calibrate.")
    C_Timer.After(30, function()
        if learner:IsShown() then learner:Hide() learner:EnableKeyboard(false) Print("learning timed out.") end
    end)
end

-- the request key that changes the mode, seen as it's pressed (passed on to its binding): the mode
-- has flipped, so swap which request is bound, just after the binding has run
local watch = CreateFrame("Frame", nil, UIParent)
watch:EnableKeyboard(true)
watch:SetPropagateKeyboardInput(true)
watch:SetScript("OnKeyDown", function(_, key)
    if not walkBound or key ~= walkBound then return end   -- (in combat the binding can't follow: compare to what's bound)
    walking = not walking
    C_Timer.After(0.05, ApplyWalk)
end)

-- moving out of combat, on foot: under 4 yd/s is walking (2.5; backpedal 1.6), running is ~7 (backpedal 4.5)
local since = 0
owner:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.15 then return end
    since = 0
    if InCombatLockdown() or IsMounted() or IsSwimming() or IsFlying() or UnitOnTaxi("player") then return end
    local speed = GetUnitSpeed("player")
    if not speed or speed <= 0 then return end
    local w = speed < 4
    if w ~= walking then walking = w ApplyWalk() end
end)

owner:RegisterEvent("PLAYER_LOGIN")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("MODIFIER_STATE_CHANGED")
owner:RegisterEvent("SPELL_UPDATE_COOLDOWN")
owner:RegisterEvent("BAG_UPDATE_COOLDOWN")
owner:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        PadBarDB = PadBarDB or {}
        PadBarDB.assign = PadBarDB.assign or {}
        MakeSecure()
        Build()
        ApplyAll()
        Refresh()
        C_Timer.NewTicker(0.2, UpdateBack)
        if not PadBarKeys then Print("wow-pad's keys aren't learned yet: run wow-pad --calibrate (it types /padbar learn for you).") end
        -- settings that assume WoW sees the controller, which it no longer does: soft targeting (□'s
        -- interact with what's in front of you) was "gamepad only", and the camera swung behind you
        -- while moving, fighting the right stick. Only from those defaults, so a choice of yours stays.
        for _, c in ipairs({ { "SoftTargetInteract", "1", "3" }, { "SoftTargetEnemy", "1", "3" }, { "cameraSmoothStyle", "4", "0" } }) do
            if GetCVar(c[1]) == c[2] then SetCVar(c[1], c[3]) end
        end
        -- WoW's own controller support would read the pad too (and its Gamepad UI taints)
        if GetCVar("GamePadEnable") == "1" then
            SetCVar("GamePadEnable", "0")
            Print("turned off WoW's own controller support (wow-pad drives the controller). /reload to clear the Gamepad UI.")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then ApplyAll() Refresh() end
    else
        Refresh()
    end
end)

SLASH_PADBAR1 = "/padbar"
SlashCmdList.PADBAR = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "learn" then Learn()
    elseif msg == "reset" then
        PadBarDB.pos = nil
        pad:ClearAllPoints() pad:SetPoint("CENTER")
    elseif msg == "lock" then
        PadBarDB.locked = not PadBarDB.locked
        Print(PadBarDB.locked and "locked." or "unlocked: drag the dots above it.")
    else
        PadBarDB.hidden = not PadBarDB.hidden
        pad:SetShown(not PadBarDB.hidden)
    end
end
