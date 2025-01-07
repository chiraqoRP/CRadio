local GUIClass = {}
GUIClass.__index = GUIClass

local classString = "[GUI Object] - CRadio"

function GUIClass:__tostring()
    return classString
end

local enabled = GetConVar("cl_cradio")
local gradientLeft, gradientRight = Color(0, 255, 80), Color(0, 210, 220)

function GUIClass:Open()
    if !enabled:GetBool() then
        return
    end

    local ply = LocalPlayer()

    -- Non-drivers cannot control the radio.
    if self.MenuOpen or !ply:IsDriver() then
        return
    end

    -- Caches our current vehicle to save on performance.
    self.Vehicle = CLib.GetVehicle()

    if !self.Vehicle:IsEngineActive() or !self.Vehicle:GetRadioOn() then
        return
    end

    -- If we don't have any stations installed, the menu has no use.
    if table.IsEmpty(CRadio:GetStations(true)) then
        return
    end

    surface.PlaySound("cradio/gui/ui_open.wav")

    -- Mark the menu as open to prevent panel spam.
    self.MenuOpen = true

    -- Sets our hovered station to nil to prevent text "ghosting".
    self.HoveredStation = nil

    local scrW, scrH = ScrW(), ScrH()

    -- Caches the center coordinates which are used commonly.
    self.CenterX = scrW / 2
    self.CenterY = scrH / 2

    -- Creates the base frame that the GUI is made of.
    self.Frame = self:BuildFrame()

    -- Builds the panels for each station.
    self:BuildStationPanels(self.Frame)
end

function GUIClass:Close(immediate)
    if !self.MenuOpen or !IsValid(self.Frame) then
        return
    end

    self:DoCloseRequest()

    if immediate then
        self.Frame:Close()
    else
        self.Frame:FancyClose()
    end

    surface.PlaySound("cradio/gui/ui_open.wav")

    self.MenuOpen = false
end

function GUIClass:DoCloseRequest()
    if !IsValid(self.Vehicle) then
        return
    end

    local currentStation = self.Vehicle:GetCurrentStation()

    -- This happens when the GUI is opened and closed with no mouse movement from the player.
    local nothingHovered = !self.IsOffHovered and !IsValid(self.HoveredStation)

    if nothingHovered or currentStation == self.HoveredStation then
        return
    end

    local cNet = CRadio:GetNet()

    if self.IsOffHovered and IsValid(currentStation) then
        cNet:SendPlayRequest(false)
    else
        cNet:SendPlayRequest(self.HoveredStation)
    end
end

function GUIClass:GetHovered(elementCount)
    local mx, my = gui.MousePos()

    -- Gets the angle between our cursor and the center of the screen. 
    local ang = 180 - math.deg(math.atan2(self.CenterY - my, self.CenterX - mx))

    -- Add 90 degrees to the angle.
    -- Without this, hover detection is shifted 90 degrees to the right. 
    ang = ang + 90

    -- Clamp the angle within the range of 0 to 360 degrees.
    ang = ang % 360

    -- Gets our hovered element by remapping the angle to our total element count.
    local hoveredElement = math.floor(math.Remap(ang, 0, 360, 0, elementCount))

    return hoveredElement
end

local circles = include("circles.lua")
local hideHUD = false
local blurMat = Material("pp/blurscreen")
local offString = "Radio Off"
local iconSize = 64
local lastHovered = 0

function GUIClass:BuildFrame()
    local motherFrame = vgui.Create("DFrame")
    motherFrame:SetSize(self.CenterX * 2, self.CenterY * 2)
    motherFrame:Center()
    motherFrame:SetDraggable(false)
    motherFrame:ShowCloseButton(false)
    motherFrame:ParentToHUD()
    motherFrame:MakePopup()
    motherFrame:SetKeyboardInputEnabled(false)
    motherFrame.lblTitle:SetText("")

    function motherFrame:PostInit()
        self:SetCursor("blank")

        self.Elements = {}

        self:SetAlpha(0)
        self:AlphaTo(255, 0.15)

        -- Makes GM:HUDShouldDraw return false.
        hideHUD = true
    end

    motherFrame:PostInit()

    function motherFrame:FancyClose()
        self:AlphaTo(0, 0.15, 0, function(data, pnl)
            if IsValid(pnl) then
                pnl:Close()
            end

            hideHUD = false
        end)
    end

    function motherFrame:BlurBackground(dark)
        self.BlurDynamic = self.BlurDynamic or 0

        local layers, density = 1, 1
        local x, y = self:LocalToScreen(0, 0)
        local frameTime, Num = 1 / RealFrameTime(), 5

        surface.SetDrawColor(255, 255, 255, 100)
        surface.SetMaterial(blurMat)

        for i = 1, Num do
            blurMat:SetFloat("$blur", (i / layers) * density * self.BlurDynamic)
            blurMat:Recompute()
            render.UpdateScreenEffectTexture()
            surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
        end

        surface.SetDrawColor(0, 0, 0, (dark or 150) * self.BlurDynamic)
        surface.DrawRect(0, 0, self:GetSize())

        self.BlurDynamic = math.Clamp(self.BlurDynamic + (1 / frameTime) * 7, 0, 1)
    end

    local cX, cY = self.CenterX, self.CenterY

    function motherFrame:Paint(w, h)
        self:BlurBackground(0)

        -- If no station is hovered/playing, this prints "Radio Off" instead.
        draw.SimpleTextOutlined(self.StationName or offString, "CRadio.Main", cX, cY - 25, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)

        -- If we have a station hovered/playing this will print the song's artist/name.
        -- Invisible otherwise.
        if self.SongArtist then
            draw.SimpleTextOutlined(self.SongArtist, "CRadio.Main", cX, cY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        end

        if self.SongName then
            draw.SimpleTextOutlined(self.SongName, "CRadio.Main", cX, cY + 25, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        end
    end

    -- We set this to an obviously unreachable integer to prevent hoveredElement == lastHovered on GUI open.
    lastHovered = 512

    function motherFrame:DoElementHover()
        -- This gets the currently hovered element by checking the angle of the mouse's position.
        local hoveredElement = GUIClass:GetHovered(self.ElementCount) or lastHovered

        if hoveredElement != lastHovered then
            -- We have to add 4 to the child index because of DFrame's internal child panels.
            local hoveredPanel = self:GetChild(hoveredElement + 4)

            if IsValid(hoveredPanel) then
                -- Set our bool to true before calling our OnHovered method.
                hoveredPanel.isHovered = true

                -- Manually calling PANEL:OnCursorEntered is hacky, so we call a custom OnHovered function instead.
                hoveredPanel:OnHovered()
            end

            -- We have to add 4 to the child index because of DFrame's internal child panels.
            local lastHoveredPanel = self:GetChild(lastHovered + 4)

            if IsValid(lastHoveredPanel) then
                -- Manually calling PANEL:OnCursorExited is hacky, so we call a custom OnUnhover function instead.
                lastHoveredPanel:OnUnhover()
            end

            local children = self:GetChildren()
            local childCount = 5 + self.ElementCount

            -- HACK: All station panels other than the currently hovered one are set to NOT hovered.
            -- This is because of a problem with the way we set the default hovered panel in BuildStationPanels.
            for i = 5, childCount do
                local child = children[i]

                if !IsValid(child) or child == hoveredPanel then
                    continue
                end

                child.isHovered = false
            end

            lastHovered = hoveredElement
        end
    end

    local vehicle = self.Vehicle
    local lastStation = nil

    function motherFrame:InvalidateText()
        local currentStation = vehicle:GetCurrentStation()
        local station = GUIClass.HoveredStation or currentStation

        if GUIClass.IsOffHovered then
            self.StationName =  nil
            self.SongArtist = nil
            self.SongName = nil

            lastStation = nil

            return
        elseif station == lastStation then
            return
        end

        local stationValid = IsValid(station)
        local song = stationValid and station:GetCurrentSong()
        local songValid = IsValid(song)

        self.StationName = stationValid and station:GetName()
        self.SongArtist = songValid and song:GetArtist()
        self.SongName = songValid and song:GetName()

        lastStation = station
    end

    function motherFrame:Think()
        -- Calculates which element is currently selected.
        self:DoElementHover()

        local sysTime = SysTime()

        if (nextThink or 0) > sysTime then
            return
        end

        nextThink = sysTime + 0.1

        -- Caches our station/song strings when needed, this reduces __index calls.
        self:InvalidateText()
    end

    function motherFrame:OnCursorMoved(x, y)
        local cursorNearCenter = GUIClass:IsCursorNearCenter(x, y)

        if cursorNearCenter then
            return true
        end

        local isWithinBounds = GUIClass:KeepCursorWithinBounds(x, y)

        if !isWithinBounds then
            return true
        end
    end

    return motherFrame
end

function GUIClass:IsCursorNearCenter(x, y)
    local mouseX, mouseY = x, y
    local centerX, centerY = self.CenterX, self.CenterY

    -- Radius of the (center) circle.
    local centerRadius = (300 + (iconSize * 2.4)) - 64

    -- Calculate the distance between our cursor and the circle's center.
    local distance = math.sqrt((mouseX - centerX) ^ 2 + (mouseY - centerY) ^ 2)

    -- If our cursor is inside or directly on the circle, adjust its position.
    if distance <= centerRadius then
        -- Calculate the new cursor position outside of the circle.
        local angle = math.atan2(mouseY - centerY, mouseX - centerX)
        local newX = centerX + centerRadius * math.cos(angle)
        local newY = centerY + centerRadius * math.sin(angle)

        -- Set our new cursor position.
        input.SetCursorPos(newX, newY)

        return true
    end

    return false
end

function GUIClass:KeepCursorWithinBounds(x, y)
    -- Radius of the wheel plus the station panels approximate size (iconSize * 2.2).
    local circleRadius = 300 + (iconSize * 2.4)
    local centerX, centerY = self.CenterX, self.CenterY

    -- Calculate the distance between our cursor and the circle's center.
    local distance = math.sqrt((centerX - x) ^ 2 + (centerY - y) ^ 2)

    -- If our cursor is outside the circle, constrain it within the circle.
    if distance > circleRadius then
        -- Calculate angle between our cursor's position and the circle's center.
        local angle = math.atan2(y - centerY, x - centerX)

        -- Calculate the clamped cursor's position on the circle's boundary.
        local clampedX = centerX + circleRadius * math.cos(angle)
        local clampedY = centerY + circleRadius * math.sin(angle)

        -- Set our cursor's position to the new clamped position.
        input.SetCursorPos(clampedX, clampedY)

        return true
    end

    return false
end

local minIcon = 16

local function CalcElementSize(count)
    if count > 12 then
        iconSize = 64 - (minIcon - minIcon / (count - 12))

        -- This rounds the size up/down to the closest power of two integer.
        iconSize = 2 ^ math.floor(math.log(iconSize, 2) + 0.5)
    else
        iconSize = 64
    end
end

function GUIClass:BuildElements()
    local stations = CRadio:GetStations(true)
    local count = #stations + 1

    -- No stations installed, so halt.
    if count - 1 <= 0 then
        notification.AddLegacy("You have not installed any radio stations.", NOTIFY_GENERIC, 3)
        surface.PlaySound("buttons/button14.wav")

        return
    end

    -- Resizes our iconSize variable as needed based off our station count.
    CalcElementSize(count)

    local radius = 300

    -- Angle for the bottom element.
    local bottomAng = math.pi / 2

    -- Total angle to distribute the elements.
    local arcRadians = (2 * math.pi) / count

    -- Calculate the position of our bottom element.
    local bottomX = math.Round(self.CenterX - math.cos(bottomAng) * radius)
    local bottomY = math.Round(self.CenterY + math.sin(bottomAng) * radius)

    -- Construct the bottom element.
    self.OffElement = {x = bottomX, y = bottomY, radius = iconSize}

    -- Construct the station elements based on the bottom (off) element.
    for i = 2, count do
        local ang = bottomAng + (i - 1) * arcRadians
        local x = math.Round(self.CenterX - math.cos(ang) * radius)
        local y = math.Round(self.CenterY + math.sin(ang) * radius)

        table.insert(self.Frame.Elements, {x = x, y = y})
    end
end

local function CalcCircle(x, y, radius)
    local filledCircle = circles.New(CIRCLE_FILLED, radius, x, y)
    filledCircle:SetDistance(1)
    filledCircle:SetMaterial(true)

    return filledCircle
end

local function CalcOutlineCircle(x, y, radius, thickness, color, mat)
    local outlineCircle = circles.New(CIRCLE_OUTLINED, radius, x, y, thickness)
    outlineCircle:SetDistance(1)
    outlineCircle:SetColor(color)
    outlineCircle:SetMaterial(mat)

    -- HACK: https://github.com/SneakySquid/Circles/blob/master/circles.lua#L244
    -- Setting this to false seems to not affect visuals at all and MASSIVELY reduces the cost of drawing.
    -- Doing this brings the call count in PANEL:Paint from 10k function calls averaging ~0.010ms per call to not even breaking into the top 10 in FProfiler.
    outlineCircle:SetChildCircle(false)

    return outlineCircle
end

local function DrawIcon(x, y, alpha, size, mat)
    surface.SetDrawColor(255, 255, 255, alpha)
    surface.SetMaterial(mat)

    local centerX, centerY = (x * 2) * 0.5 - size * 0.5, (y * 2) * 0.5 - size * 0.5

    surface.DrawTexturedRect(centerX, centerY, size, size)
end

local timerFormat = "cradio_gui_%s"
local offMatPath = "cradio/gui/radio_off.png"
local gradientLeftMat, gradientRightMat = Material("vgui/gradient-l"), Material("vgui/gradient-r")
local panelsGenerated = 0

function GUIClass:BuildStationPanel(station, element, isOffButton)
    if !element then
        return
    end

    local radius_m = iconSize * 2.2
    local stationPanel = vgui.Create("DPanel", self.Frame)
    stationPanel:SetSize(radius_m, radius_m)
    stationPanel:SetPos(element.x - radius_m / 2, element.y - radius_m / 2)
    stationPanel:NoClipping(true)

    function stationPanel:PostInit()
        self:SetCursor("blank")

        self.Station = station

        local iconPath = (isOffButton and offMatPath) or station:GetIcon()

        -- Calculates and caches our circles so their vertices aren't recalculated every frame.
        self.Circle = CalcCircle(radius_m / 2, radius_m / 2, iconSize)
        self.OutlineLeftCircle = CalcOutlineCircle(radius_m / 2, radius_m / 2, iconSize + 4, 4, gradientLeft, gradientLeftMat)
        self.OutlineRightCircle = CalcOutlineCircle(radius_m / 2, radius_m / 2, iconSize + 4, 4, gradientRight, gradientRightMat)

        -- Creates our station's icon material, deleted when GUIClass:Close is called.
        -- If no valid string is provided, the var is the default material.
        self.Icon = isstring(iconPath) and Material(iconPath, "smooth mips") or iconPath

        -- If the station has no name (ie: isOffButton == true), then we use the number of generated panels for the timer.
        local stationName = station and station:GetName() or tostring(panelsGenerated)

        self.TimerName = string.format(timerFormat, stationName)
        self.InitTime = SysTime()

        panelsGenerated = panelsGenerated + 1
    end

    stationPanel:PostInit()

    function stationPanel:CalculateFade(speed, customHover)
        local hovered = self:IsHovered()

        -- This is a bool that can be provided for panels that have a custom hover method.
        if customHover != nil then
            hovered = customHover
        end

        local buf, step = self.__hoverBuf or 0, RealFrameTime() * speed

        if hovered and buf < 1 then
            buf = math.min(1, step + buf)
        elseif !hovered and buf > 0 then
            buf = math.max(0, buf - step)
        end

        self.__hoverBuf = buf
        buf = math.EaseInOut(buf, 0.2, 0.2)

        return buf
    end

    function stationPanel:Paint(w, h)
        -- Returns a ascending/descending float to use with lerp for alpha fade.
        local buf = self:CalculateFade(2, self.isHovered)
        local alpha, clr = Lerp(buf, 150, 100), Lerp(buf, 20, 40)
        local iconAlpha = Lerp(buf, 75, 255)

        surface.SetDrawColor(clr, clr, clr, alpha)

        -- Draws our primary circle.
        self.Circle()

        -- Draws our icon as a textured rect.
        DrawIcon(radius_m / 2, radius_m / 2, iconAlpha, math.Round(iconSize * 1.4), self.Icon)

        local outlineAlpha = Lerp(buf, 0, 170)

        gradientLeft.a = outlineAlpha
        gradientRight.a = outlineAlpha

        -- Draws our outline circle. This is done twice because gradients are made of two materials.
        -- This is only done when the outline alpha is above 0 because it's expensive.
        if outlineAlpha > 0 then
            self.OutlineLeftCircle()
            self.OutlineRightCircle()
        end

        return true
    end

    local vehicle = self.Vehicle

    function stationPanel:CreateTimer()
        timer.Create(self.TimerName, 1.5, 0, function()
            local isHovered = IsValid(self) and IsValid(vehicle) and self.isHovered

            -- If we aren't hovered or the frame was closed, do nothing.
            if !isHovered then
                return
            end

            local cNet = CRadio:GetNet()

            -- If true, stops this vehicle's audio channel for all listeners.
            local shouldStop = isOffButton and false

            -- If we don't stop playback, switches all listeners audio channels to one for this station. 
            cNet:SendPlayRequest(shouldStop or station)
        end)
    end

    function stationPanel:KillTimer()
        timer.Remove(self.TimerName)
    end

    function stationPanel:OnHovered()
        local currentStation = vehicle:GetCurrentStation()

        -- Sets our hovered station.
        GUIClass.HoveredStation = station

        -- There can only be one "off" button so we make it a separate var.
        GUIClass.IsOffHovered = isOffButton

        -- WORKAROUND: Prevent the hover sound from overlapping the open sound triggered in our class' Open method.
        if (SysTime() - self.InitTime) > 0.25 then
            surface.PlaySound("cradio/gui/ui_hover.wav")
        end

        -- If this isn't a "radio off" button, we have a valid current station, and its the same as this station, do nothing.
        if !isOffButton and IsValid(currentStation) and currentStation:GetName() == station:GetName() then
            return
        end

        self:CreateTimer()
    end

    function stationPanel:OnUnhover()
        self:KillTimer()
    end

    function stationPanel:GetCenter()
        return element.x + radius_m / 2, element.y + radius_m / 2
    end

    return stationPanel
end

function GUIClass:BuildStationPanels()
    if !IsValid(self.Frame) then
        return
    end

    self:BuildElements()

    local stations = CRadio:GetStations(true)
    local count = #stations

    -- Sets our element count on the frame, used for the hover detection func.
    self.Frame.ElementCount = count + 1

    -- Builds our radio off element at the bottom of the wheel.
    local offPanel = self:BuildStationPanel(nil, self.OffElement, true)

    for i = 1, count do
        local station = stations[i]

        if !station:IsValid() then
            continue
        end

        local element = self.Frame.Elements[i]
        local stationPanel = self:BuildStationPanel(station, element)
        local currentStation = self.Vehicle:GetCurrentStation()

        -- If we don't have a current station or the current station isn't this station, continue.
        if !IsValid(currentStation) or currentStation != station then
            continue
        end

        local newX, newY = stationPanel:GetCenter()

        -- Sets our cursor to the center position of the station element.
        input.SetCursorPos(newX, newY)

        -- Forces the current station's panel to be hovered.
        stationPanel.isHovered = true

        lastHovered = math.max(0, i - 1)
    end

    -- This only happens when no stations are installed.
    if !IsValid(offPanel) then
        return
    end

    local mouseX, mouseY = input.GetCursorPos()

    -- If the cursor is still positioned at the center of the screen, we have no current station.
    if mouseX == self.CenterX and mouseY == self.CenterY then
        local newX, newY = offPanel:GetCenter()

        -- Set our cursor to the center position of the radio off element.
        input.SetCursorPos(newX + 1, newY + 1)
    end
end

local shouldNotification = GetConVar("cl_cradio_notification")

-- We only scale down the notification panel and fonts if our height is below 1440.
local screenHeight = ScrH()
local scaleMul = screenHeight / 1440 or 1.0

-- recordMat is the fallback used when a song doesn't have a valid cover.
local recordMat = Material("cradio/gui/notification_record.png", "smooth mips")
local backgroundColor = Color(40, 40, 40, 150)
local bufferTextColor = Color(255, 255, 255, 0)
local bufferFormat = "%.2f%%"

function GUIClass:DoPlayNotification(song, channel, ent)
    if !shouldNotification:GetBool() or !IsValid(channel) then
        return
    end

    -- Songs can deny notifications showing, common for continous mixes.
    if !song or !song:IsValid() or !song:ShouldNotify() then
        return
    end

    -- We don't want notifications that originate from custom entities or others vehicles showing up.
    if IsValid(ent) and (ent.CRadio or ent != CLib.GetVehicle()) then
        return
    end

    local y = 64 * scaleMul
    local oldFrame = self.NotificationPanel

    if IsValid(oldFrame) and oldFrame:IsValid() then
        -- Stop any active animations on the old notification.
        oldFrame:Stop()

        -- Kill the timers too.
        oldFrame.BeingRemoved = true

        oldFrame:MoveTo(ScrW() + 36 * scaleMul, y, 2, 0, 0.25, function(animData, pFrame)
            pFrame:Remove()

            -- Play the queued notification once the old notification is removed.
            self:DoPlayNotification(song, channel)
        end)

        self.NotificationPanel = nil

        return
    end

    local frame = vgui.Create("DPanel")
    frame:SetSize(420 * scaleMul, 144 * scaleMul)
    frame:SetPos(ScrW(), y)

    -- Move onto screen.
    frame:MoveTo(ScrW() - 420 * scaleMul - 32 * scaleMul, y, 2, 0, 0.25)

    -- Cache our song's vars.
    local name, artist, release = song:GetName(), song:GetArtist(), song:GetRelease()

    surface.SetFont("CRadio.MainBold")
    local _, nTextHeight = surface.GetTextSize(name)

    surface.SetFont("CRadio.Main")
    local _, aTextHeight = surface.GetTextSize(artist)

    if release then
        rTextWidth, _ = surface.GetTextSize(release)
    end

    -- Material expects a string, so we provide an empty (nil) one if our song has no cover.
    -- We also set it to smooth if we're scaling, as IMaterial scaling is awful and smooth improves it slightly.
    local cover, coverMat = song:GetCover(), nil

    if string.IsValid(cover) then
        coverMat, _ = Material(cover, scaleMul != 1.0 and "smooth" or "")
    end

    function frame:Paint(w, h)
        draw.RoundedBox(4, 0, 0, w, h, backgroundColor)

        -- :scammer:
        surface.SetDrawColor(255, 255, 255, 255)

        local textOffset = (128 * scaleMul) + (16 * scaleMul)
        local drawHeight = 128 * scaleMul

        if coverMat and !coverMat:IsError() then
            surface.SetMaterial(coverMat)

            -- For non-square covers, we calculate the ratio between width and height.
            local widthRatio = coverMat:Width() / coverMat:Height()
            local drawWidth = (128 * widthRatio) * scaleMul

            -- Height is enforced, but we scale our width based on the width-to-height ratio.
            surface.DrawTexturedRect(6 * scaleMul, 8 * scaleMul, drawWidth, drawHeight)

            textOffset = drawWidth + (16 * scaleMul)
        else
            local recordHeight = 112 * scaleMul

            self.RecordAngle = (self.RecordAngle or 0) + FrameTime() * 32

            DisableClipping(true)
            surface.SetMaterial(recordMat)
            surface.DrawTexturedRectRotated((14 * scaleMul) + recordHeight / 2, (16 * scaleMul) + recordHeight / 2, recordHeight, recordHeight, self.RecordAngle)
            DisableClipping(false)
        end

        surface.SetFont("CRadio.MainBold")

        local nTextOffset = textOffset

        -- Draws the song name in bold lettering.
        surface.SetTextColor(255, 255, 255)
        surface.SetTextPos(nTextOffset, 10 * scaleMul)
        surface.DrawText(name)

        -- Draws the separator between name and release/artist.
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawRect(nTextOffset - (2 * scaleMul), nTextHeight + (14 * scaleMul), w - nTextOffset - (2 * scaleMul), 6)

        surface.SetFont("CRadio.Main")

        local aTextOffset = textOffset

        -- Draws the artist in regular lettering.
        surface.SetTextColor(200, 200, 200)
        surface.SetTextPos(aTextOffset, nTextHeight + (24 * scaleMul))
        surface.DrawText(artist)

        -- Draws the release (if present) in regular lettering.
        if release then
            local rTextOffset = textOffset

            surface.SetTextColor(200, 200, 200)
            surface.SetTextPos(rTextOffset, nTextHeight + (24 * scaleMul) + aTextHeight + (4 * scaleMul))
            surface.DrawText(release)
        end

        -- Draws the buffer progress if needed, this is controlled in our :Think function.
        if self.DrawBuffering then
            local bufferProgress = self.BufferProgress or 0
            local bufferStr = nil

            if bufferProgress == 1.00 then
                bufferStr = "Loaded!"
            else
                -- We multiply the progress float to have three digits (1.00% --> 100.00%).
                bufferStr = string.format(bufferFormat, bufferProgress * 100)
            end

            local _, bTextHeight = surface.GetTextSize(bufferStr)

            -- This approaches 1.0 from 0.0, for alpha fade-in.
            local alphaMul = math.Approach(self.AlphaMult or 0, 1, FrameTime() / 0.4)

            bufferTextColor.a = 255 * alphaMul

            -- Draws our percentage string right aligned.
            draw.SimpleText(bufferStr, "DermaDefault", w - 4, h - bTextHeight - 6, bufferTextColor, TEXT_ALIGN_RIGHT)

            -- Draws our progress bar.
            surface.SetDrawColor(255, 255, 255, 50 * alphaMul)
            surface.DrawRect(0, h - (4 * scaleMul), bufferProgress * w, 4 * scaleMul)

            self.AlphaMult = alphaMul
        end
    end

    function frame:Think()
        local client = LocalPlayer()

        -- If we aren't in a vehicle or we disconnect, kill the panel instantly.
        if !IsValid(client) or !client:InVehicle() then
            self:Remove()

            return
        end

        local channelDead = !channel or !channel:IsValid()

        -- If our channel is removed, start the kill timer.
        if channelDead then
            frame:Kill(1)

            return
        end

        local sysTime = SysTime()
        local bufferedTime, seekTime = channel:GetBufferedTime(), song:GetCurTime()
        local bufferProgress = math.Clamp(bufferedTime / seekTime, 0, 1)

        self.StartTime = self.StartTime or sysTime

        local isPlaying = channel:GetState() == GMOD_CHANNEL_PLAYING

        -- If the channel is buffering, progress is below 98.00%, and 0.5s have passed we draw buffering progress.
        if (sysTime - self.StartTime) >= 0.5 and !isPlaying and bufferProgress < 0.98 then
            self.DrawBuffering = true
        end

        self.BufferProgress = bufferProgress

        -- If the channel is playing and we haven't started the kill timer, do so.
        if isPlaying and !self.StartedRemoveAnim then
            frame:Kill(4)
        end
    end

    function frame:Kill(delay)
        if self.StartedRemoveAnim then
            return
        end

        frame:MoveTo(ScrW() + 36, y, 2, delay or 0, 0.25, function(animData, pFrame)
            pFrame:Remove()
        end)

        self.StartedRemoveAnim = true
    end

    self.NotificationPanel = frame
end

-- This is here because HUDShouldDraw hooks are super expensive.
hook.Add("HUDShouldDraw", "CRadio.HideHUD", function()
    if hideHUD then
        return false
    end
end)

surface.CreateFont("CRadio.Main", {
    font = "Tahoma",
    size = 16 * scaleMul,
    weight = 500,
    extended = true
})

surface.CreateFont("CRadio.MainBold", {
    font = "Tahoma",
    size = 18 * scaleMul,
    weight = 800,
    extended = true
})

CRadioGUIClass = GUIClass