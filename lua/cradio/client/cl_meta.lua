local function GetHookIdentifier(format)
    local identifier = nil
    local tickHooks = hook.GetTable().Tick

    repeat
        -- Creates our hook's identifier. (example: CRadio.Fade-2048)
        identifier = string.format(format, math.random(1, 32768))
    -- If there's already a tick hook with this identifier, retry.
    until !tickHooks[identifier]

    return identifier
end

local ENTITY = FindMetaTable("Entity")

function ENTITY:GetRadioStream()
    return self.acRadioStream
end

function ENTITY:SetRadioStream(stream)
    self.acRadioStream = stream
end

function ENTITY:StopRadioStream(doFade, fadeLength)
    local stream = self.acRadioStream

    if !IsValid(stream) then
        return
    end

    local channel = stream:GetChannel()

    if doFade and IsValid(channel) then
        channel:FadeOut(fadeLength or 0.5, function(fChannel)
            stream:Destroy()
        end)
    else
        stream:Destroy()
    end
end

local AUDIOCHANNEL = FindMetaTable("IGModAudioChannel")

-- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
local channelQueued = {}

function AUDIOCHANNEL:IsQueuedForPlay()
    return channelQueued[self]
end

function AUDIOCHANNEL:SetIsQueuedForPlay(bQueued)
    channelQueued[self] = bQueued
end

-- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
local channelStreams = {}

function AUDIOCHANNEL:GetStream()
    return channelStreams[self]
end

function AUDIOCHANNEL:SetStream(stream)
    channelStreams[self] = stream
end

-- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
local bufferingChannels = {}

local function KillBufferHook(identifier, channel, parent)
    hook.Remove("Tick", identifier)

    if IsValid(channel) then
        bufferingChannels[channel] = nil
    end

    if !IsValid(parent) then
        return
    end

    local staticSnd = parent.StaticSound

    if staticSnd then
        staticSnd:FadeOut(0.5)

        timer.Simple(0.5, function()
            if staticSnd then
                staticSnd:Stop()
            end

            parent.StaticSound = nil
        end)
    end
end

function AUDIOCHANNEL:IsBuffering()
    return bufferingChannels[self]
end

local hookBufferFormat = "CRadio.Buffer-%i"

function AUDIOCHANNEL:Buffer(parent, callback)
    local identifier = GetHookIdentifier(hookBufferFormat)
    local stream = self:GetStream()

    if !IsValid(parent) or !IsValid(stream) or !stream:IsValid() then
        return
    end

    bufferingChannels[self] = true

    local station = stream:GetStation()
    local curSong = station:GetCurrentSong()

    -- Sanity check, Audio:Buffer can sometimes be calling in Stream:PlayChannel for block-streamed channels due to Song:GetCurTime difference.
    if self:IsOnline() and self:IsBlockStreamed() then
        if isfunction(callback) then
            callback(self)
        end

        KillBufferHook(identifier, self, parent)

        return
    end

    hook.Add("Tick", identifier, function()
        local isValid = stream and self and self:IsValid() and IsValid(parent)

        -- Detect if the audio channel was stopped.
        if !isValid then
            KillBufferHook(identifier, self, parent)

            return
        end

        local bufferedTime = self:GetBufferedTime()
        local seekTime = curSong:GetCurTime()

        -- If our audio has buffered enough, we can seek to the desired time.
        if bufferedTime >= seekTime then
            self:SetTime(seekTime, true)

            -- WORKAROUND: Some streams don't support seeking with dont_decode set to true, this serves as a sanity check for that.
            -- We try with dont_decode set to true first because decoding freezes the game for a moment.
            if seekTime > 0 and self:GetTime() == 0 then
                self:SetTime(seekTime, false)
            end

            if isfunction(callback) then
                callback(self)
            end

            KillBufferHook(identifier, self, parent)

            return
        end
    end)
end

-- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
local fadingChannels = {}

function AUDIOCHANNEL:IsFading()
    return fadingChannels[self]
end

local function KillFadeHook(channel, identifier)
    if IsValid(channel) then
        fadingChannels[channel] = nil
    end

    hook.Remove("Tick", identifier)
end

local hookFadeFormat = "CRadio.Fade-%i"

function AUDIOCHANNEL:StopFade()
    local identifier = fadingChannels[self]

    if !identifier then
        return
    end

    fadingChannels[self] = nil

    hook.Remove("Tick", identifier)
end

function AUDIOCHANNEL:FadeIn(length, callback)
    local stream = self:GetStream()

    if !IsValid(stream) or !stream:IsValid() then
        return
    end

    self:StopFade()
    self:SetVolume(0)
    self:FadeTo(1, length, callback, function(fChannel)
        if !IsValid(stream) or !stream:IsValid() then
            return 1
        end

        local vol, _ = stream:CalculateVolume()

        return vol
    end)
end

function AUDIOCHANNEL:FadeOut(length, callback)
    local stream = self:GetStream()

    if !IsValid(stream) or !stream:IsValid() then
        return
    end

    self:StopFade()
    self:FadeTo(0, length, callback)
end

function AUDIOCHANNEL:FadeTo(to, length, callback, volCallback)
    if !to or !length then
        return
    end

    local identifier = GetHookIdentifier(hookFadeFormat)
    fadingChannels[self] = identifier

    local from = self:GetVolume()
    local startTime = SysTime()

    hook.Add("Tick", identifier, function()
        local curTime = SysTime()
        local isValid = self and self:IsValid()

        -- Detect if the audio channel was stopped.
        if !isValid then
            KillFadeHook(self, identifier)

            return
        end

        if isfunction(volCallback) then
            to = volCallback(self)
        end

        local newVolume = Lerp((curTime - startTime) / length, from, to)
        self:SetVolume(newVolume)

        if startTime + length < curTime then
            if isfunction(callback) then
                callback(self)
            end

            KillFadeHook(self, identifier)
        end
    end)
end