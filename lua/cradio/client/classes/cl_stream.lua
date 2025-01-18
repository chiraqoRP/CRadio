-- MIT License

-- Copyright (c) 2024 StyledStrike

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local StreamClass = {}
StreamClass.__index = StreamClass

local shouldStatic = GetConVar("cl_cradio_static")
local streamInstances = {}
local streamsGenerated = 0

function StreamClass:__constructor(streamStruct)
    self.Station = streamStruct.Station

    if !IsValid(self.Station) then
        return
    end

    self:SetEntity(streamStruct.Entity)

    if !IsValid(self.Entity) then
        return
    end

    local curSong = self:GetCurrentSong()

    if !IsValid(curSong) then
        return
    end

    self.bIsPlaying = false
    self.ShouldEmitStatic = streamStruct.ShouldEmitStatic

    -- Never play static if the client has it disabled.
    if !shouldStatic:GetBool() then
        self.ShouldEmitStatic = false
    end

    self.OnProcess = streamStruct.OnProcess

    -- Our ID doesn't need to be cryptographically secure, it's only used for __eq operations.
    self.ID = streamsGenerated + 1
    streamsGenerated = self.ID

    for key, val in pairs(streamStruct) do
        if self[key] != nil then
            continue
        end

        self[key] = val
    end

    streamInstances[self.ID] = self

    self:MakeChannel(curSong)

    if self.IsDestroyed then
        return
    end

    if self.ShouldEmitStatic then
        self:MakeStatic()
    end

    self:QueuePreBuffer()

    return true
end

local formatString = "[Stream Object] | %s - %s"
local nullString = "[Stream Object] | NULL"

function StreamClass:__tostring()
    if !self:IsValid() then
        return nullString
    end

    return string.format(formatString, self:GetStation():GetName(), self:GetCurrentSong():GetName())
end

function StreamClass:__eq(other)
    return self:GetID() == other:GetID()
end

function StreamClass:IsValid()
    if self.Destroyed or !self:GetID() then
        return false
    end

    return true
end

function StreamClass:GetID()
    return self.ID
end

function StreamClass:New(name)
    local newStream = setmetatable({}, self)

    return newStream
end

local dbgDestroyFormat = "Destroyed stream instance %s belonging to %s."

function StreamClass:Destroy()
    local channel = self:GetChannel()

    if IsValid(channel) then
        channel:Stop()
    end

    local ent = self:GetEntity()
    local station = self:GetStation()

    CRadio:DebugPrint(string.format(dbgDestroyFormat, tostring(self), tostring(ent)))

    if IsValid(ent) then
        -- Our entity can have another stream set depending on FadeOut, so we make sure the reference is still the same.
        if self == ent:GetRadioStream() then
            ent:SetRadioStream(nil)
        end

        if IsValid(station) then
            local streams = station:GetStreams()
            streams[ent] = nil
        end
    end

    self:StopStaticSound()
    self:StopPreBuffer()

    streamInstances[self:GetID()] = nil

    self.Destroyed = true
end

function StreamClass:GetStation()
    return self.Station
end

function StreamClass:SetStation(station)
    self.Station = station
end

function StreamClass:GetCurrentSong()
    local station = self:GetStation()

    if !IsValid(station) then
        return
    end

    local playlist = station:GetPlaylist()

    return playlist[1]
end

function StreamClass:GetNextSong()
    local station = self:GetStation()

    if !IsValid(station) then
        return
    end

    local playlist = station:GetPlaylist()

    return playlist[2]
end

function StreamClass:GetEntity()
    return self.Entity
end

function StreamClass:SetEntity(ent)
    self.Entity = ent

    local streams = self:GetStation():GetStreams()
    streams[ent] = self
end

function StreamClass:IsPlaying()
    local channel = self:GetChannel()

    if !self.ShouldPlay or !IsValid(channel) then
        return false
    end

    return channel:GetState() == 1
end

function StreamClass:Play(doFade)
    self.ShouldPlay = true
    self.ShouldFade = doFade

    local channel = self:GetChannel()

    if IsValid(channel) then
        channel:SetIsQueuedForPlay(true)
    end
end

function StreamClass:Pause(shouldFade)
    self.ShouldPlay = false

    local channel = self:GetChannel()

    if !IsValid(channel) then
        return
    end

    if shouldFade then
        channel:FadeOut(0.5, function(fChannel)
            fChannel:Pause()
        end)
    else
        channel:Pause()
    end

    channel:SetIsQueuedForPlay(false)

    local staticSound = self:GetStaticSound()

    if !IsValid(staticSound) then
        return
    end

    staticSound:FadeOut(0.5, function(sSound)
        sSound:Pause()
    end)
end

local playPreFormat = "Playing %s for stream %s!"

function StreamClass:Update()
    if !self:IsValid() then
        return
    end

    local channel = self:GetChannel()

    if IsValid(channel) then
        channel:Stop()
    end

    -- WORKAROUND: Prevents the new song from fading in, which is something we only want on stream initialization.
    self.DidUpdate = true

    local cGUI = CRadio:GetGUI()
    local nextSong = self:GetCurrentSong()
    local preBufferChannel = self:GetPreBufferChannel()

    if IsValid(preBufferChannel) then
        self:SetChannel(preBufferChannel)
        self:SetPreBufferChannel(nil)
        self:QueuePreBuffer()

        cGUI:DoPlayNotification(nextSong, preBufferChannel, self:GetEntity())
        CRadio:DebugPrint(string.format(playPreFormat, tostring(preBufferChannel), tostring(self)))

        return
    end

    self:MakeChannel(nextSong, function(nChannel, errorID, errorName)
        self:SetChannel(nChannel)
        self:ProcessChannel(nChannel, nextSong)
        self:QueuePreBuffer()

        cGUI:DoPlayNotification(nextSong, nChannel, self:GetEntity())
    end)
end

function StreamClass:GetChannel()
    return self.Channel
end

function StreamClass:SetChannel(channel)
    self.Channel = channel
end

function StreamClass:MakeChannel(song, callback)
    if !self:IsValid() then
        return
    end

    song = song or self:GetCurrentSong()

    local playSong, path = song:GetPlayMethod()

    -- We have no audio file and there is no valid URL provided, so halt and print an error.
    if !playSong then
        ErrorNoHalt(self, " - No file present or valid URL for ", tostring(song), ".")

        self:Destroy()

        return
    end

    local channelFlags = song:GetChannelFlags(enable3D)

    playSong(path, channelFlags, callback or function(channel, errorID, errorName)
        self:SetChannel(channel)
        self:ProcessChannel(channel, song)
    end)
end

function StreamClass:ProcessChannel(channel, song)
    channel = channel or self:GetChannel()
    song = song or self:GetCurrentSong()

    local entity = self:GetEntity()
    local channelValid = IsValid(channel)

    if !channelValid or !IsValid(entity) then
        if !channelValid then
            ErrorNoHalt(self, " - Channel for ", tostring(song), " invalid after initialization. Ensure file/URL is accessible.")
        end

        self:Destroy()

        return
    end

    if !self:IsValid() then
        channel:Stop()

        return
    end

    channel:SetStream(self)
    channel:SetIsQueuedForPlay(true)
    entity:SetRadioStream(self)

    if isfunction(self.OnProcess) then
        self.OnProcess(self, channel, entity)
    end
end

local cPlayFormat = "%s played for %s."

function StreamClass:PlayChannel(channel)
    local ent = self:GetEntity()

    if !IsValid(ent) or !IsValid(channel) then
        return
    end

    CRadio:DebugPrint(string.format(cPlayFormat, tostring(channel), tostring(self)))

    local curSong = self:GetCurrentSong()
    local shouldBuffer = channel:IsOnline() and !channel:IsBlockStreamed() or curSong:GetCurTime() > 0.5
    local shouldFade = !self.DidUpdate and self.ShouldFade

    -- If our stream has static enabled (self.ShouldEmitStatic), then we start the channel muted if we haven't updated.
    local startSilenced = !self.DidUpdate and self.ShouldEmitStatic

    -- WORKAROUND: We only don't fade when transitioning to another song (self.DidUpdate).
    -- SEE: Stream:Update().
    if shouldBuffer then
        channel:Buffer(ent, function(bChannel)
            bChannel:Play()

            if startSilenced then
                bChannel:SetVolume(0)

                return
            end

            if shouldFade then
                bChannel:FadeIn(1.0)
            end

            self:StopStaticSound()
        end)
    else
        channel:Play()

        if !startSilenced then
            if shouldFade then
                channel:FadeIn(1.0)
            end
    
            self:StopStaticSound()
        end
    end

    channel:SetIsQueuedForPlay(false)
end

function StreamClass:GetPreBufferChannel()
    return self.PreBufferChannel
end

function StreamClass:SetPreBufferChannel(channel)
    self.PreBufferChannel = channel
end

local preBufferFormat = "CRadio.PreBuffer_%i"

function StreamClass:IsPreBuffered()
    local pChannel = self:GetPreBufferChannel()

    if IsValid(pChannel) then
        pChannel:Stop()
    end

    local timerName = string.format(preBufferFormat, self:GetID())

    return timer.Exists(timerName)
end

local enabled = GetConVar("cl_cradio")
local shouldPreBuffer = GetConVar("cl_cradio_prebuffer")

function StreamClass:QueuePreBuffer()
    if !enabled:GetBool() or !shouldPreBuffer:GetBool() then
        return
    end

    local curSong = self:GetCurrentSong()
    local preBufferDelay = math.max(curSong:GetTimeLeft() - 3, 1)
    local timerName = string.format(preBufferFormat, self:GetID())

    timer.Create(timerName, preBufferDelay, 1, function()
        local nextSong = self:GetNextSong()

        -- Song must not be nil and be valid (have both name and url).
        if curSong != self:GetCurrentSong() or !IsValid(nextSong) then
            return
        end

        self:MakeChannel(nextSong, function(channel, errorID, errorName)
            self:SetPreBufferChannel(channel)
            self:ProcessChannel(channel, nextSong)
        end)
    end)
end

function StreamClass:StopPreBuffer()
    local pChannel = self:GetPreBufferChannel()

    if IsValid(pChannel) then
        pChannel:Stop()
    end

    local timerName = string.format(preBufferFormat, self:GetID())

    timer.Remove(timerName)
end

function StreamClass:GetVolume()
    local channel = self:GetChannel()

    if !IsValid(channel) then
        return
    end

    return channel:GetVolume()
end

function StreamClass:GetPan()
    local channel = self:GetChannel()

    if !IsValid(channel) then
        return
    end

    return channel:GetPan()
end

local defaultVol = GetConVar("cl_cradio_volume")
local lastViewPos = Vector()
local lastViewAng = Angle()
local dir = Vector()
local FADE_DIST = 2048

function StreamClass:CalculateVolume(eyeRight)
    local ent = self:GetEntity()
    local oVol = defaultVol:GetFloat()

    -- We pan and adjust volume to make the sound have a fake position in the world, but only when 3D is enabled.
    if !IsValid(ent) or !self:Get3DEnabled() then
        -- If any players are audibly speaking, we lower the channels volume.
        if self:GetPlayersSpeaking() then
            return math.max(oVol * 0.5, 0.1), 0
        end

        return oVol, 0
    end

    local vol = 1.0
    local pan = 0

    -- Calculate direction and distance from the camera
    local origin = ent:GetPos()
    dir:Set(origin)
    dir:Sub(lastViewPos)

    local dist = dir:Length()

    -- Attenuate depending on distance
    vol = vol * (0.5 - math.Clamp(dist / FADE_DIST, 0, 0.5))

    eyeRight = eyeRight or lastViewAng:Right()

    dir:Normalize()
    pan = eyeRight:Dot(dir)

    return oVol * vol, pan
end

function StreamClass:GetPlayersSpeaking()
    return self.bPlayersSpeaking
end

-- If any players are audibly speaking, we can use this to smoothly lower the channels volume.
function StreamClass:SetPlayersSpeaking(bSpeaking)
    self.bPlayersSpeaking = bSpeaking

    local channel = self:GetChannel()

    if !IsValid(channel) or self:Get3DEnabled() then
        return
    end

    local oVol = defaultVol:GetFloat()

    if bSpeaking then
        local newVol = math.max(oVol * 0.5, 0.1)
        channel:FadeTo(newVol, 0.5)
    else
        channel:FadeIn(0.5, newVol)
    end
end

function StreamClass:GetStaticSound()
    return self.StaticSound
end

function StreamClass:SetStaticSound(channel)
    self.StaticSound = channel
end

function StreamClass:StopStaticSound()
    local staticSound = self:GetStaticSound()

    if !IsValid(staticSound) then
        return
    end

    staticSound:FadeOut(1.0, function(sChannel)
        if IsValid(self) and sChannel == self:GetStaticSound() then
            self:SetStaticSound(nil)
        end

        sChannel:Stop()
    end)
end

local function StaticCallback(stream, channel)
    if !IsValid(stream) or stream:IsPlaying() then
        channel:Stop()

        return
    end

    local vol, pan = stream:CalculateVolume()
    channel:SetStream(stream)
    channel:EnableLooping(true)
    channel:SetVolume(vol)
    channel:SetPan(pan)
    channel:FadeIn(0.5)
    channel:Play()
    stream:SetStaticSound(channel)

    stream.StaticStart = SysTime()
end

function StreamClass:MakeStatic()
    sound.PlayFile("sound/cradio/radio_change_static_looped.wav", "noplay noblock", function(channel, errorID, error)
        StaticCallback(self, channel)
    end)

    self.StaticStart = 0
    self.StaticEnforced = true
end

function StreamClass:ManageStatic(vol, pan)
    if self.DidUpdate or !self.ShouldEmitStatic then
        return
    end

    local staticSound = self:GetStaticSound()

    if IsValid(staticSound) then
        if !staticSound:IsFading() then
            staticSound:SetVolume(vol)
        end
    
        staticSound:SetPan(pan)
    end

    if !self.StaticEnforced then
        return
    end

    local channel = self:GetChannel()

    if !IsValid(channel) then
        return
    end

    local emitLength = self.StaticStart + 2

    if SysTime() <= emitLength or channel:IsBuffering() then
        channel:SetVolume(0)
    elseif self.StaticEnforced then
        if self.ShouldFade then
            channel:FadeIn(1.0)
        end

        self:StopStaticSound()
        self.StaticEnforced = false
    end
end

function StreamClass:Is3D()
    return self.bIs3D
end

function StreamClass:Get3DEnabled()
    return self.bIs3D
end

function StreamClass:Set3DEnabled(bEnabled)
    self.bIs3D = bEnabled
end

function StreamClass:Think(eyeRight)
    local ent = self:GetEntity()

    if !IsValid(ent) then
        return
    end

    local channel = self:GetChannel()

    if !IsValid(channel) or !self.ShouldPlay then
        return
    end

    local vol, pan = self:CalculateVolume(eyeRight)

    -- Only update the channels volume if we aren't fading.
    if !channel:IsFading() then
        channel:SetVolume(vol)
    end

    channel:SetPan(pan)

    -- Manages our stream's static sound, if self.ShouldEmitStatic is true.
    -- It also fades in our stream's initial channel if needed.
    self:ManageStatic(vol, pan)

    -- Check if we need to start playing our current channel.
    if !channel:IsQueuedForPlay() or channel:IsBuffering() or channel:GetState() == 1 then
        return
    end

    -- This buffers our channel if needed, then plays it if we don't emit static (self.ShouldEmitStatic).
    -- Otherwise, it starts the channel muted and lets Stream:ManageStatic handle the fade-in.
    -- SEE: Stream:ManageStatic.
    self:PlayChannel(channel)
end

setmetatable(StreamClass, {
    __call = function(tbl, ...)
        local newStream = StreamClass:New(...)
        local passed = newStream:__constructor(...)

        if !passed then
            newStream:Destroy()
        end

        return newStream
    end
})

CRadioStreamClass = StreamClass

local gEyePos = EyePos
local gEyeAngles = EyeAngles

-- `PreDrawEffects` seems like a good place to get values from EyePos/EyeAngles reliably.
-- `PreDrawOpaqueRenderables`/`PostDrawOpaqueRenderables` were being called twice when there was water.
-- `PreRender`/`PostRender` were causing `EyeAngles` to return incorrect angles.
hook.Add("PreDrawEffects", "CRadio.CachePlayerView", function(bDepth, bSkybox, b3DSkybox)
    if bDepth or bSkybox or b3DSkybox then
        return
    end

    lastViewPos = gEyePos()
    lastViewAng = gEyeAngles()
end)

local next = next
local pairs = pairs

hook.Add("Tick", "CRadio.ProcessRadioStreams", function()
    if next(streamInstances) == nil then
        return
    end

    local eyeRight = lastViewAng:Right()

    for _, stream in pairs(streamInstances) do
        -- Let the stream do it's thing.
        stream:Think(eyeRight)
    end
end)