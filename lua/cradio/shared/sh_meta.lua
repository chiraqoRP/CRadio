local ENTITY = FindMetaTable("Entity")

function ENTITY:GetRadioOn()
    return self:GetNW2Bool("CRadio.RadioState", false)
end

if SERVER then
    function ENTITY:SetRadioOn(on)
        self:SetNW2Bool("CRadio.RadioState", on)
    end
end

function ENTITY:GetCurrentStation()
    local name = self:GetNW2String("CRadio.Station")

    return CRadio:GetStation(name)
end

if SERVER then
    function ENTITY:SetCurrentStation(station)
        local name = (station and station:GetName()) or nil

        self:SetNW2String("CRadio.Station", name)
    end
end

if CLIENT then
    function ENTITY:GetRadioChannel()
        return self.acRadioChannel
    end

    function ENTITY:SetRadioChannel(channel)
        -- Prevent any existing audio channel from being discarded and continuing to play.
        if self.acRadioChannel then
            self:StopRadioChannel()
        end

        self.acRadioChannel = channel
    end


    local channelSongs = {}

    function ENTITY:StopRadioChannel(doFade, fadeLength)
        local channel = self.acRadioChannel

        if channel and channel:IsValid() then
            -- COMMENT
            channel:SetStation(nil)

            if doFade then
                channel:DoFade(fadeLength or 0.5, channel:GetVolume(), 0, function(fChannel)
                    fChannel:Stop()
                end)
            else
                channel:Stop()
            end

            -- print("ENTITY:StopRadioChannel | channel stopped!")
        end

        self.acRadioChannel = nil
    end

    local AUDIOCHANNEL = FindMetaTable("IGModAudioChannel")

    -- HACK: COMMENT
    local channelStations = {}

    function AUDIOCHANNEL:GetStation()
        return channelStations[self]
    end

    function AUDIOCHANNEL:SetStation(station)
        channelStations[self] = station
    end

    local function KillBufferHook(identifier, channel, parent)
        hook.Remove("Think", identifier)

        if channel and channel:IsValid() then
            channel:Stop()
        end

        if !IsValid(ent) then
            return
        end

        local staticSnd = ent.StaticSound

        if staticSnd then
            staticSnd:FadeOut(0.5)

            timer.Simple(0.5, function()
                if staticSnd then
                    staticSnd:Stop()
                end

                ent.StaticSound = nil
            end)
        end
    end

    local defaultVol = CreateClientConVar("cl_cradio_volume", 1.0, true, false, "", 0, 1.0)
    local failureDelay = CreateClientConVar("cl_cradio_failuredelay", 5, true, false, "", 5, 30)
    local hookBufferFormat = "CRadio.Buffer-%i"

    function AUDIOCHANNEL:DoBuffer(parent, station, time, doFade, bufferCallback)
        local identifier = nil
        local thinkHooks = hook.GetTable().Think

        repeat
            -- Creates our hook's identifier. (example: CRadio.Buffer-2048)
            identifier = string.format(hookBufferFormat, math.random(1, 32768))
        -- If there's already a think hook with this identifier, retry.
        until !thinkHooks[identifier]

        local startTime = CurTime()
        local lastCheck, stalledTime = 0, nil
        local curSong = station:GetCurrentSong()
        local timeElapsed, songLength = 0, curSong:GetLength()
        local wasValid, lastBufferedTime = false, 0

        hook.Add("Think", identifier, function()
            local curTime = CurTime()

            if (lastCheck or 0) + 0.05 > curTime then
                return
            end

            lastCheck = curTime
            timeElapsed = curTime - startTime

            -- print("DoBuffering | timeElapsed: ", timeElapsed)

            local isValid = self and self:IsValid() and IsValid(parent)

            -- Detect if the audio channel was stopped.
            if wasValid and !isValid then
                KillBufferHook(identifier, self, parent)

                -- print("ProcessChannel | Channel or parent entity invalid, buffering stopped!")

                return
            end

            local bufferedTime = self:GetBufferedTime()
            local seekTime = math.Clamp(time + timeElapsed, 0, songLength)

            -- print("DoBuffering | bufferedTime: ", bufferedTime)
            -- print("DoBuffering | seekTime: ", seekTime)

            -- COMMENT
            if bufferedTime == lastBufferedTime and bufferedTime < seekTime then
                stalledTime = stalledTime or CurTime()

                if (CurTime() - stalledTime) >= failureDelay:GetFloat() then
                    -- MsgC(Color(203, 26, 219), "ProcessChannel | Channel buffering stalled, seeking stopped!\n")

                    KillBufferHook(identifier, self, parent)

                    return
                end
            end

            -- If our audio has buffered enough, we can seek to the desired time.
            if bufferedTime >= seekTime then
                self:SetTime(seekTime, true)
                self:Play()

                if doFade then
                    self:DoFade(0.5, 0, defaultVol:GetFloat())
                else
                    self:SetVolume(defaultVol:GetFloat())
                end

                if isfunction(bufferCallback) then
                    bufferCallback(self, parent, station)
                end

                -- print("ProcessChannel | Buffering finished, time set to ", time, "!")

                -- COMMENT
                KillBufferHook(identifier, nil, parent)

                return
            end

            wasValid = isValid
            lastBufferedTime = bufferedTime
        end)
    end

    local hookFadeFormat = "CRadio.Fade-%i"

    function AUDIOCHANNEL:DoFade(length, from, to, callback)
        if !length then
            return
        end

        local identifier = nil
        local thinkHooks = hook.GetTable().Think

        repeat
            -- Creates our hook's identifier. (example: CRadio.Fade-2048)
            identifier = string.format(hookFadeFormat, math.random(1, 32768))
        -- If there's already a think hook with this identifier, retry.
        until !thinkHooks[identifier]

        local startTime = CurTime()
        local wasValid = false
        local didFade = false

        hook.Add("Think", identifier, function()
            local curTime = CurTime()
            local isValid = self and self:IsValid()

            -- Detect if the audio channel was stopped.
            if wasValid and !isValid then
                hook.Remove("Think", identifier)

                return

                -- print("AUDIOCHANNEL:DoFade | Channel invalid, fade stopped!")
            end

            local newVolume = Lerp((curTime - startTime) / length, from, to)

            -- print("AUDIOCHANNEL:DoFade | newVolume: ", newVolume)

            -- COMMENT
            if isValid and !didFade then
                self:SetVolume(newVolume)
            end

            if startTime + length < curTime then
                if isValid and isfunction(callback) then
                    callback(self)
                end

                didFade = true

                -- print("AUDIOCHANNEL:DoFade | Length higher, ", identifier, " removed!")

                hook.Remove("Think", identifier)
            end

            wasValid = isValid
        end)
    end
end

if CLIENT then
    cvars.AddChangeCallback("cl_cradio_volume", function(name, old, new)
        if old == new then
            return
        end

        local stations = CRX:GetStations()

        if table.IsEmpty(stations) then
            return
        end

        for i = 1, #stations do
            local station = stations[i]
            local radioChannels = station:GetRadioChannels()

            if table.IsEmpty(radioChannels) then
                continue
            end

            for _, channel in pairs(radioChannels) do
                if !channel or !channel:IsValid() or math.Round(old, 1) != math.Round(channel:GetVolume(), 1) then
                    return
                end
        
                channel:SetVolume(new)
            end
        end
    end)
end