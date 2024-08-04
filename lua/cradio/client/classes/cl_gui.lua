local GUIClass = {}
GUIClass.__index = GUIClass

function GUIClass:__constructor()
    self.FailureDelay = GetConVar("cradio_failuredelay")
end

local classString = "[GUI Object] - CRadio"

function GUIClass:__tostring()
    return classString
end

local gradientLeft, gradientRight = Color(0, 255, 80), Color(0, 210, 220)

function GUIClass:Open()
    local ply = LocalPlayer()

    -- Non-drivers cannot control the radio.
    if self.MenuOpen or !ply:IsDriver() then
        return
    end

    -- Caches our current vehicle to save on performance.
    self.Vehicle = CLib.GetVehicle()

    if !self.Vehicle:IsEngineActive() then
        return
    end

    -- Mark the menu as open to prevent panel spam.
    self.MenuOpen = true

    -- Sets our hovered station to nil to prevent text "ghosting".
    self.HoveredStation = nil

    local scrW, scrH = ScrW(), ScrH()

    -- Caches the center coordinates since this is a very common operation.
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

    if immediate then
        self.Frame:Close()
    else
        self.Frame:FancyClose()
    end

    self.MenuOpen = false
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

local iconSize = 64

-- Prevents our cursor from being on/within a specified circular radius of the screen's center.
local function IsCursorNearCenter(self2, x, y)
    local mouseX, mouseY = x, y
    local centerX, centerY = self2.CenterX, self2.CenterY

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

-- Constrains our cursor within the bounds of a specified circular radius on the screen's center.
local function KeepCursorWithinBounds(self2, x, y)
    -- Radius of the wheel plus the station panels approximate size (iconSize * 2.2).
    local circleRadius = 300 + (iconSize * 2.4)
    local centerX, centerY = self2.CenterX, self2.CenterY

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

local offString = "Radio Off"
local circles = include("circles.lua")
local lastHovered = 0

function GUIClass:BuildFrame()
    local self2 = self

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
        -- self:SetCursor("blank")

        self.Elements = {}

        self:FadeIn(0.15)

        -- Makes GM:HUDShouldDraw return false.
        CLib.SetHideHUD(true)
    end

    motherFrame:PostInit()

    function motherFrame:FancyClose()
        self:FadeOut(0.15, function(data, pnl)
            if IsValid(pnl) then
                pnl:Close()
            end

            CLib.SetHideHUD(false)
        end)
    end

    function motherFrame:Paint(w, h)
        self:BlurBackground(0)

        -- If no station is hovered/playing, this prints "Radio Off" instead.
        draw.SimpleTextOutlined(self.StationName or offString, "CRadio.Main", self2.CenterX, self2.CenterY - 25, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)

        -- If we have a station hovered/playing this will print the song's artist/name.
        -- Invisible otherwise.
        if self.SongArtist then
            draw.SimpleTextOutlined(self.SongArtist, "CRadio.Main", self2.CenterX, self2.CenterY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        end

        if self.SongName then
            draw.SimpleTextOutlined(self.SongName, "CRadio.Main", self2.CenterX, self2.CenterY + 25, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        end
    end

    -- COMMENT
    lastHovered = 512

    function motherFrame:DoElementHover()
        -- This gets the currently hovered element by checking the angle of the mouse's position.
        local hoveredElement = self2:GetHovered(self.ElementCount) or lastHovered

        -- print("hoveredElement: ", hoveredElement)
        -- print("lastHovered: ", lastHovered)

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
                lastHoveredPanel.isHovered = false

                -- Manually calling PANEL:OnCursorExited is hacky, so we call a custom OnUnhover function instead.
                lastHoveredPanel:OnUnhover()
            end

            lastHovered = hoveredElement
        end

        -- lastHovered = hoveredElement
    end

    local lastStation = nil

    function motherFrame:InvalidateText()
        local currentStation = self2.Vehicle:GetCurrentStation()
        local station = self2.HoveredStation or currentStation

        if self2.IsOffHovered then
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

        local curTime = CurTime()

        if (nextThink or 0) > curTime then return end

        nextThink = curTime + 0.1

        -- Caches our station/song strings when needed, this reduces __index calls.
        self:InvalidateText()
    end

    function motherFrame:OnCursorMoved(x, y)
        local cursorNearCenter = IsCursorNearCenter(self2, x, y)

        if cursorNearCenter then
            return true
        end

        local isWithinBounds = KeepCursorWithinBounds(self2, x, y)

        if !isWithinBounds then
            return true
        end
    end

    return motherFrame
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

    return outlineCircle
end

local function DrawIcon(x, y, alpha, size, mat)
    surface.SetDrawColor(255, 255, 255, alpha)
    surface.SetMaterial(mat)

    local centerX, centerY = (x * 2) * 0.5 - size * 0.5, (y * 2) * 0.5 - size * 0.5

    surface.DrawTexturedRect(centerX, centerY, size, size)
end

local timerFormat = "cradio_gui_%s"
local offMatPath = "cradio/icons/radio_off.png"
local gradientLeftMat, gradientRightMat = Material("vgui/gradient-l"), Material("vgui/gradient-r")
local panelsGenerated = 0

function GUIClass:BuildStationPanel(station, element, isOffButton)
    if !element then return end

    local radius_m = iconSize * 2.2

    local stationPanel = vgui.Create("DPanel", self.Frame)
    stationPanel:SetSize(radius_m, radius_m)
    stationPanel:SetPos(element.x - radius_m / 2, element.y - radius_m / 2)
    stationPanel:NoClipping(true)

    local self2 = self

    function stationPanel:PostInit()
        -- self:SetCursor("blank")

        self.Station = station

        local iconPath = (isOffButton and offMatPath) or station:GetIcon()

        -- Calculates and caches our circles so their vertices aren't recalculated every frame.
        self.Circle = CalcCircle(radius_m / 2, radius_m / 2, iconSize)
        self.OutlineLeftCircle = CalcOutlineCircle(radius_m / 2, radius_m / 2, iconSize, 4, gradientLeft, gradientLeftMat)
        self.OutlineRightCircle = CalcOutlineCircle(radius_m / 2, radius_m / 2, iconSize, 4, gradientRight, gradientRightMat)

        -- Creates our station's icon material, deleted when GUIClass:Close is called.
        self.Icon = Material(iconPath, "smooth mips")

        -- COMMENT
        local stationName = station and station:GetName() or tostring(panelsGenerated)

        self.TimerName = string.format(timerFormat, stationName)

        panelsGenerated = panelsGenerated + 1
    end

    stationPanel:PostInit()

    function stationPanel:Paint(w, h)
        local isHovered = self.isHovered and !self.isHoverOverriden

        -- Returns a ascending/descending float to use with lerp for alpha fade.
        local buf = self:CalculateFade(2, isHovered)
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

    function stationPanel:CreateTimer()
        local vehicle = self2.Vehicle

        timer.Create(self.TimerName, 1.5, 0, function()
            local isHovered = IsValid(self) and IsValid(vehicle) and self.isHovered

            -- If we aren't hovered or the frame was closed, do nothing.
            if !isHovered then return end

            local cNet = CRadio:GetNet()

            -- If true, stops this vehicle's audio channel for all listeners.
            local shouldStop = (isOffButton and false)

            -- If we don't stop playback, switches all listeners audio channels to one for this station. 
            cNet:SendPlayRequest(shouldStop or station)
        end)
    end

    function stationPanel:KillTimer()
        -- print("stationPanel | timer killed for ", self.Station)

        timer.Remove(self.TimerName)
    end

    function stationPanel:OnHovered()
        local vehicle = self2.Vehicle
        local currentStation = vehicle:GetCurrentStation()

        -- Sets our hovered station.
        self2.HoveredStation = station

        -- COMMENT
        self2.IsOffHovered = isOffButton

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
    if !IsValid(self.Frame) then return end

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

        -- FIXME: This is never accurate on non-straight angles!
        -- Sets our cursor to the center position of the station element.
        input.SetCursorPos(newX, newY)

        -- HACK: COMMENT
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

-- COMMENT
local screenWidth = ScrW()
local scaleMul = screenWidth < 1920 and screenWidth / 1920 or 1.0

-- COMENT
local recordMat = Material("cradio/icons/notification_record.png", "smooth mips")
local armMat = Material("cradio/icons/notification_arm.png", "smooth mips")
local backgroundColor = Color(40, 40, 40, 150)
local bufferTextColor = Color(255, 255, 255, 0)
local bufferFormat = "%.2f%%"

function GUIClass:DoPlayNotification(song)
    if !song or !song:IsValid() then
        return
    end

    -- COMMENT
    local self2 = self
    local y = 64

    -- MsgC(Color(203, 26, 219), "called lmao")

    local oldFrame = self.NotificationPanel

    -- COMMENT
    if IsValid(oldFrame) then
        -- COMMENT
        oldFrame:Stop()

        -- COMMENT
        oldFrame.BeingRemoved = true

        oldFrame:MoveTo(ScrW() + 36, y, 2, 0, 0.25, function(animData, pFrame)
            pFrame:Remove()

            -- COMMENT
            self2:DoPlayNotification(song)
        end)

        self.NotificationPanel = nil

        return
    end

    local frame = vgui.Create("DPanel")
    frame:SetSize(420, 144)
    frame:SetPos(ScrW(), y)

    -- COMMENT
    frame:MoveTo(ScrW() - 420 - 32, y, 2, 0, 0.25)

    -- COMMENT
    local name, artist, release = song:GetName(), song:GetArtist(), song:GetRelease()

    -- COMMENT
    surface.SetFont("CRadio.MainBold")
    local nTextWidth, nTextHeight = surface.GetTextSize(name)

    -- COMMENT
    surface.SetFont("CRadio.Main")
    local aTextWidth, aTextHeight = surface.GetTextSize(artist)
    local rTextWidth, _ = surface.GetTextSize(release)

    -- COMMENT
    local coverMat, _ = Material(song:GetCover() or "")
    local scrollOffset = 0

    function frame:Paint(w, h)
        draw.RoundedBox(4, 0, 0, w, h, backgroundColor)

        -- :scammer:
        surface.SetDrawColor(255, 255, 255, 255)

        local textOffset = 100

        if coverMat and !coverMat:IsError() then
            surface.SetMaterial(coverMat)

            -- COMMENT
            local widthRatio = coverMat:Width() / coverMat:Height()
            local drawWidth = 128 * widthRatio

            -- COMMENT
            surface.DrawTexturedRect(6, 8, drawWidth, 128)

            -- COMMENT
            textOffset = drawWidth + 16
        else
            self.RecordAngle = (self.RecordAngle or 0) + FrameTime() * 60

            DisableClipping(true)
            surface.SetMaterial(recordMat)
            surface.DrawTexturedRectRotated(6 + 128 / 2, 8 + 128 / 2, 128, 128, self.RecordAngle)

            self.ArmAngle = (self.ArmAngle or 0) + FrameTime() * 4

            surface.SetMaterial(armMat)
            surface.DrawTexturedRectRotated(16 + 38 / 2, 16 + 94 / 2, 38, 94, self.ArmAngle)
            DisableClipping(false)

            textOffset = 128 + 16
        end

        -- COMMENT
        surface.SetFont("CRadio.MainBold")

        local textRange = 420 - (6 + textOffset)
        local nTextOffset = textOffset

        surface.SetTextColor(255, 255, 255)
        surface.SetTextPos(nTextOffset, 10)
        surface.DrawText(name)

        -- COMMENT
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawRect(nTextOffset - 2, nTextHeight + 10 + 4, 420 - nTextOffset - 2, 6)

        -- COMMENT
        surface.SetFont("CRadio.Main")

        local aTextOffset = textOffset

        surface.SetTextColor(200, 200, 200)
        surface.SetTextPos(aTextOffset, nTextHeight + 10 + 6 + 4 + 4)
        surface.DrawText(artist)

        -- COMMENT
        if release then
            local rTextOffset = textOffset

            surface.SetTextColor(200, 200, 200)
            surface.SetTextPos(rTextOffset, nTextHeight + 10 + 6 + 4 + 4 + aTextHeight + 4)
            surface.DrawText(release)
        end

        -- COMMENT
        if self.DrawBuffering then
            local bufferProgress = self.BufferProgress or 0
            local bufferStr = nil

            -- COMMENT
            if self.BufferingFailed then
                bufferStr = "Failed to load!"
            elseif bufferProgress == 1.00 then
                bufferStr = "Loaded!"
            else
                -- COMMENT
                bufferStr = string.format(bufferFormat, bufferProgress * 100)
            end

            -- COMMENT
            local _, bTextHeight = surface.GetTextSize(bufferStr)
            local alphaMul = math.Approach(self.AlphaMult or 0, 1, FrameTime() / 0.4)

            bufferTextColor.a = 255 * alphaMul

            -- COMMENT
            draw.SimpleText(bufferStr, "DermaDefault", w - 4, h - bTextHeight - 6, bufferTextColor, TEXT_ALIGN_RIGHT)

            -- COMMENT
            surface.SetDrawColor(255, 255, 255, 50 * alphaMul)
            surface.DrawRect(0, h - 4, bufferProgress * w, 4)

            -- COMMENT
            self.AlphaMult = alphaMul
        end
    end

    local stationChannel = song:GetStationChannel()

    function frame:Think()
        local client = LocalPlayer()

        -- COMMENT
        if !IsValid(client) or !client:InVehicle() then
            self:Remove()

            return
        end

        local channelDead = !stationChannel or !stationChannel:IsValid()

        -- COMMENT
        if channelDead then
            -- COMMENT
            frame:Kill()

            return
        end

        -- COMMENT
        local bufferedTime, seekTime = stationChannel:GetBufferedTime(), song:GetCurTime()
        local isPlaying = stationChannel:GetState() == GMOD_CHANNEL_PLAYING

        -- COMMENT
        if !isPlaying and bufferedTime == self.BufferedTime and bufferedTime < seekTime then
            self.StalledTime = self.StalledTime or CurTime()

            -- COMMENT
            if (CurTime() - self.StalledTime) >= math.min(4, self2.FailureDelay:GetFloat() - 1) then
                self.BufferingFailed = true

                return
            end
        end

        local sysTime = SysTime()
        local bufferProgress = math.Clamp(bufferedTime / seekTime, 0, 1)

        -- COMMENT
        self.StartTime = self.StartTime or sysTime

        -- COMMENT
        if (sysTime - self.StartTime) >= 0.5 and !isPlaying and bufferProgress < 0.98 then
            self.DrawBuffering = true
        end

        self.BufferedTime = bufferedTime
        self.BufferProgress = bufferProgress

        -- COMMENT
        if isPlaying and !self.StartedRemoveAnim then
            self.EndTime = self.EndTime or sysTime

            if (sysTime - self.EndTime) >= 4 then
                frame:Kill()
            end
        end
    end

    function frame:Kill()
        if self.StartedRemoveAnim then
            return
        end

        frame:MoveTo(ScrW() + 36, y, 2, 0, 0.25, function(animData, pFrame)
            pFrame:Remove()
        end)

        self.StartedRemoveAnim = true
    end

    -- COMMENT
    self.NotificationPanel = frame
end

surface.CreateFont("CRadio.Main", {
    font = "Tahoma",
    size = 16 * scaleMul,
    weight = 500 * scaleMul,
    extended = true
})

surface.CreateFont( "CRadio.MainBold", {
    font = "Tahoma",
    size = 18 * scaleMul,
    weight = 800 * scaleMul,
    extended = true
})

GUIClass:__constructor()

CRadioGUIClass = GUIClass

if CRadio then
    local cGUI = GUIClass

    CRadio.GUI = cGUI
end