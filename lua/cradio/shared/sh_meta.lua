local ENTITY = FindMetaTable("Entity")

function ENTITY:GetRadioOn()
    return self:GetNW2Bool("CRadio.RadioState", false)
end

function ENTITY:SetRadioOn(on)
    self:SetNW2Bool("CRadio.RadioState", on)
end

function ENTITY:GetCurrentStation()
    local name = self:GetNW2Int("CRadio.Station")

    return CRadio:GetStation(name)
end

function ENTITY:SetCurrentStation(station)
    local id = (station and station:GetID()) or nil

    self:SetNW2Int("CRadio.Station", id)
end

if CLIENT then
    function ENTITY:GetRadioChannel()
        return self.acRadioChannel
    end

    function ENTITY:SetRadioChannel(channel)
        -- Prevent any existing audio channel from being dereferenced and continuing to play.
        if self.acRadioChannel then
            self:StopRadioChannel()
        end

        self.acRadioChannel = channel
    end

    function ENTITY:StopRadioChannel(doFade, fadeLength, skipPreBuffer)
        local channel = self.acRadioChannel

        if channel and channel:IsValid() then
            channel:SetStation(nil)

            if doFade then
                channel:DoFade(fadeLength or 0.5, channel:GetVolume(), 0, function(fChannel)
                    fChannel:Stop()
                end)
            else
                channel:Stop()
            end
        end

        local preBufferChannel = self.acPreBuffer

        if !skipPreBuffer then
            if preBufferChannel and preBufferChannel:IsValid() then
                preBufferChannel:Stop()
            end

            self.acPreBuffer = nil
        end

        self.acRadioChannel = nil

        timer.Remove("CRadio.PreBuffer")
    end

    local AUDIOCHANNEL = FindMetaTable("IGModAudioChannel")

    -- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
    local channelStations = {}

    function AUDIOCHANNEL:GetStation()
        return channelStations[self]
    end

    function AUDIOCHANNEL:SetStation(station)
        channelStations[self] = station
    end

    local function KillBufferHook(identifier, channel, parent)
        hook.Remove("Tick", identifier)

        if channel and channel:IsValid() then
            channel:Stop()
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

    local defaultVol = GetConVar("cl_cradio_volume")
    local hookBufferFormat = "CRadio.Buffer-%i"

    function AUDIOCHANNEL:DoBuffer(parent, station, doFade, bufferCallback)
        local identifier = nil
        local tickHooks = hook.GetTable().Tick

        repeat
            -- Creates our hook's identifier. (example: CRadio.Buffer-2048)
            identifier = string.format(hookBufferFormat, math.random(1, 32768))
        -- If there's already a tick hook with this identifier, retry.
        until !tickHooks[identifier]

        local curSong = station:GetCurrentSong()

        hook.Add("Tick", identifier, function()
            local isValid = self and self:IsValid() and IsValid(parent)

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
                if self:GetTime() == 0 then
                    self:SetTime(seekTime, false)
                end

                self:Play()

                if doFade then
                    self:DoFade(0.5, 0, defaultVol:GetFloat())
                else
                    self:SetVolume(defaultVol:GetFloat())
                end

                if isfunction(bufferCallback) then
                    bufferCallback(self, parent, station)
                end

                -- We don't want to kill the channel, so we feed it nil/false where the channel arg is.
                KillBufferHook(identifier, false, parent)

                return
            end
        end)
    end

    -- WORKAROUND: IGModAudioChannel can't be indexed like a table, so we have to do this.
    local fadingChannels = {}

    function AUDIOCHANNEL:IsFading()
        return fadingChannels[self]
    end

    local hookFadeFormat = "CRadio.Fade-%i"

    function AUDIOCHANNEL:DoFade(length, from, to, callback)
        if !length or from == to then
            return
        end

        fadingChannels[self] = true

        local identifier = nil
        local tickHooks = hook.GetTable().Tick

        repeat
            -- Creates our hook's identifier. (example: CRadio.Fade-2048)
            identifier = string.format(hookFadeFormat, math.random(1, 32768))
        -- If there's already a tick hook with this identifier, retry.
        until !tickHooks[identifier]

        local startTime = SysTime()
        local didFade = false

        hook.Add("Tick", identifier, function()
            local curTime = SysTime()
            local isValid = self and self:IsValid()

            -- Detect if the audio channel was stopped.
            if !isValid then
                hook.Remove("Tick", identifier)

                return
            end

            local newVolume = Lerp((curTime - startTime) / length, from, to)

            -- Hooks can sometimes execute after removal, so we check if the fading is already complete.
            if isValid and !didFade then
                self:SetVolume(newVolume)
            end

            if startTime + length < curTime then
                if isValid and isfunction(callback) then
                    callback(self)
                end

                didFade = true

                fadingChannels[self] = nil

                hook.Remove("Tick", identifier)
            end
        end)
    end
end