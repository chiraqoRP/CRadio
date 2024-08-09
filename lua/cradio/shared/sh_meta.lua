if SERVER then
    util.AddNetworkString("CRadio.Station.NetworkPlaylist")
    util.AddNetworkString("CRadio.Core.RequestStatusChange")
end

local ENTITY = FindMetaTable("Entity")

function ENTITY:GetRadioOn()
    return self:GetNW2Bool("CRadio.RadioState", false)
end

if SERVER then
    function ENTITY:SetRadioOn(on)
        if !self:IsVehicle() then
            return
        end

        self:SetNW2Bool("CRadio.RadioState", on)
    end
end

function ENTITY:GetCurrentStation()
    local name = self:GetNW2String("CRadio.Station")

    return CRadio:GetStation(name)
end

if SERVER then
    function ENTITY:SetCurrentStation(station)
        if !self:IsVehicle() then
            return
        end

        local name = (station and station:GetName()) or nil

        self:SetNW2String("CRadio.Station", name)
    end
end

if CLIENT then
    local function StopStatic(ent)
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

    local function KillBufferHook(identifier, channel, parent)
        hook.Remove("Think", identifier)

        if channel and channel:IsValid() then
            channel:Stop()
        end

        StopStatic(parent)
    end

    local defaultVol = CreateClientConVar("cl_cradio_volume", 1.0, true, false, "", 0, 1.0)
    local failureDelay = CreateClientConVar("cl_cradio_failuredelay", 5, true, false, "", 5, 30)
    local hookBufferFormat = "CRadio_Buffer-%i"

    local function DoBuffer(parent, channel, station, time, doFade, bufferCallback)
        local identifier = nil
        local thinkHooks = hook.GetTable()["Think"]

        repeat
            -- Creates our hook's identifier. (example: CRadio_Buffer-2048)
            identifier = string.format(hookBufferFormat, math.random(1, 4096))
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

            local isValid = channel and channel:IsValid() and IsValid(parent)

            -- Detect if the audio channel was stopped.
            if wasValid and !isValid then
                KillBufferHook(identifier, channel, parent)

                -- print("ProcessChannel | Channel or parent entity invalid, buffering stopped!")

                return
            end

            local bufferedTime = channel:GetBufferedTime()
            local seekTime = math.Clamp(time + timeElapsed, 0, songLength)

            -- print("DoBuffering | bufferedTime: ", bufferedTime)
            -- print("DoBuffering | seekTime: ", seekTime)

            -- COMMENT
            if bufferedTime == lastBufferedTime and bufferedTime < seekTime then
                stalledTime = stalledTime or CurTime()

                if (CurTime() - stalledTime) >= failureDelay:GetFloat() then
                    -- MsgC(Color(203, 26, 219), "ProcessChannel | Channel buffering stalled, seeking stopped!\n")

                    KillBufferHook(identifier, channel, parent)

                    return
                end
            end

            -- If our audio has buffered enough, we can seek to the desired time.
            if bufferedTime >= seekTime then
                channel:SetTime(seekTime, true)
                channel:Play()

                if doFade then
                    channel:DoFade(0.5, 0, defaultVol:GetFloat())
                else
                    channel:SetVolume(defaultVol:GetFloat())
                end

                if isfunction(bufferCallback) then
                    bufferCallback(channel, parent, station)
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

    local shouldNotification = CreateClientConVar("cradio_notification", 1, true, false, "", 0, 1)

    local function ProcessChannel(parent, channel, station, time, enable3D, doFade, callback, bufferCallback)
        if !IsValid(channel) then
            StopStatic(parent)

            return
        end

        if !IsValid(parent) then
            channel:Stop()

            return
        end

        if channel:Is3D() then
            channel:Set3DEnabled(true)
        end

        -- print("ProcessChannel | Buffering?: ", time > 2)

        if time > 1.5 then
            DoBuffer(parent, channel, station, time, doFade, bufferCallback)
        else
            channel:Play()

            if doFade then
                channel:DoFade(0.5, 0, 1.0)
            end
        end

        -- Cache the station object for comparison. 
        channel:SetStation(station)

        local curSong = station:GetCurrentSong()

        -- COMMENT
        channel:SetSong(curSong)

        -- COMMENT
        curSong:SetRadioChannel(channel)

        -- COMMENT
        if !parent.IsCRadioEnt and shouldNotification:GetBool() then
            local cGUI = CRadio:GetGUI()

            -- COMMENT
            cGUI:DoPlayNotification(curSong)
        end

        -- COMMENT
        parent:SetRadioChannel(channel)

        local radioChannels = station:GetRadioChannels()

        -- COMMENT
        radioChannels[parent] = channel

        if isfunction(callback) then
            callback(channel, parent, station)
        end
    end

    local _3dFlags = "3d mono %s"
    local urlFlags = "noplay noblock"
    local fileFlags = "noplay"

    function ENTITY:RadioChannel(station, enable3D, doFade, playStatic, callback, bufferCallback)
        -- Enforce station validity.
        if !station or !station:IsValid() then
            return
        end

        local curSong = station:GetCurrentSong()

        -- Song must not be nil and be valid (have both name and url).
        if !curSong or !curSong:IsValid() then
            return
        end

        local curSongTime = curSong:GetCurTime()
        local url = curSong:GetURL()
        local fileValid, audioFile = curSong:GetFileExists(), curSong:GetFile()

        -- print("ENTITY:RadioChannel | curSongTime: ", curSongTime)
        -- MsgC("Do we already have a static sound active?", Color(0, 255, 0), self.StaticSound, "\n")

        -- COMMENT
        if playStatic and !self.StaticSound then
            local staticSnd = CreateSound(self, "cradio/radio_change_static_looped.wav")
            staticSnd:SetSoundLevel(120)
            staticSnd:Play()

            -- print("ENTITY:RadioChannel | staticSnd: ", staticSnd)

            self.StaticSound = staticSnd
        end

        -- COMMENT
        local urlValid = string.Left(url, 4) == "http"

        -- If the song's CurTime is below a reasonable margin (0-1.5 seconds), do not use noblock.
        -- Doing this saves bandwidth and some performance (no need for a buffer callback).
        local channelFlags = urlValid and curSongTime > 1.5 and urlFlags or fileFlags

        -- COMMENT
        if enable3D then
            channelFlags = string.format(_3dFlags, channelFlags)
        end

        -- MsgC("ENTITY:RadioChannel | channelFlags: ", Color(0, 255, 0), channelFlags, "\n")

        -- COMMENT
        if audioFile then
            sound.PlayFile(audioFile, channelFlags, function(channel, errorID, errorName)
                ProcessChannel(self, channel, station, curSongTime, doFade, callback, bufferCallback)
            end)
        -- COMMENT
        elseif urlValid then
            sound.PlayURL(url, channelFlags, function(channel, errorID, errorName)
                ProcessChannel(self, channel, station, curSongTime, doFade, callback, bufferCallback)
            end)
        -- We have no audio file and there is no valid URL provided, so halt.
        else
            StopStatic(self)

            return
        end
    end

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

    function ENTITY:StopRadioChannel(doFade, fadeLength)
        local channel = self.acRadioChannel

        if channel and channel:IsValid() then
            local song = channel:GetSong()

            -- COMMENT
            if song and song:IsValid() then
                song:SetRadioChannel(nil)
            end

            -- COMMENT
            channel:SetStation(nil)
            channel:SetSong(nil)

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
    local channelSongs = {}

    function AUDIOCHANNEL:GetStation()
        return channelStations[self]
    end

    function AUDIOCHANNEL:SetStation(station)
        channelStations[self] = station
    end

    function AUDIOCHANNEL:GetSong()
        return channelSongs[self]
    end

    function AUDIOCHANNEL:SetSong(song)
        channelSongs[self] = song
    end

    local hookFadeFormat = "CRadio_Fade-%i"

    function AUDIOCHANNEL:DoFade(length, from, to, callback)
        if !length then
            return
        end

        local identifier = nil
        local thinkHooks = hook.GetTable().Think

        repeat
            -- Creates our hook's identifier. (example: CRadio_Fade-2048)
            identifier = string.format(hookFadeFormat, math.random(1, 4096))
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
    net.Receive("CRadio.Station.NetworkPlaylist", function(len)
		local cNet = CRadio:GetNet()

		cNet:ReceivePlaylist(len)
	end)

    cvars.AddChangeCallback("cl_cradio_volume", function(name, old, new)
        if old == new then
            return
        end

        local vehicle = CLib.GetVehicle(LocalPlayer():GetVehicle())

        if !IsValid(vehicle) then
            return
        end

        local radioChannel = vehicle:GetRadioChannel()

        if !radioChannel or !radioChannel:IsValid() or math.Round(old, 1) != math.Round(radioChannel:GetVolume(), 1) then
            return
        end

        radioChannel:SetVolume(new)
    end)
else
	net.Receive("CRadio.Core.RequestStatusChange", function(len, ply)
		local cNet = CRadio:GetNet()

		cNet:ReceivePlayRequest(len, ply)
	end)
end