if SERVER then
    hook.Add("PlayerFullLoad", "CRadio.NetworkPlaylists", function(ply)
        if ply:IsBot() then
            return
        end

        if !CRadio:IsInitialized() then
            CRadio:Initialize()
        end

        local cNet = CRadio:GetNet()

        -- Networks all playlists to the connected player.
        cNet:Initialize(ply)
    end)

    hook.Add("PlayerEnteredVehicle", "CRadio.ControlRadio", function(ply, veh, role)
        -- WORKAROUND: We ignore Sit Anywhere seats as they cause lua errors, probably because of race conditions.
        -- REFERENCE: https://github.com/Xerasin/Sit-Anywhere/blob/master/sit/lua/sitanywhere/server/sit.lua#L76
        if veh.playerdynseat then
            return
        end

        -- Get the real vehicle entity in case we're using a custom base.
        veh = CLib.GetVehicle(veh)

        -- We handle RadioOn logic for custom bases elsewhere.
        if !IsValid(veh) or veh.LVS or veh.IsGlideVehicle or veh.IsSimfphyscar then
            return
        end

        timer.Simple(FrameTime() + 0.75, function()
            if !IsValid(ply) or !IsValid(veh) then
                return
            end

            if ply:IsDriver(veh) and veh:IsEngineActive() then
                veh:SetRadioOn(true)
            end
        end)
    end)

    hook.Add("PlayerLeaveVehicle", "CRadio.ControlRadio", function(ply, veh)
        -- WORKAROUND: We ignore Sit Anywhere seats as they cause lua errors, probably because of race conditions.
        -- REFERENCE: https://github.com/Xerasin/Sit-Anywhere/blob/master/sit/lua/sitanywhere/server/sit.lua#L76
        if veh.playerdynseat then
            return
        end

        -- Get the real vehicle entity in case we're using a custom base.
        veh = CLib.GetVehicle(veh)

        -- We handle RadioOn logic for custom bases elsewhere.
        if !IsValid(veh) or veh.LVS or veh.IsGlideVehicle or veh.IsSimfphyscar then
            return
        end

        local wasDriver = veh:GetDriver() == ply

        timer.Simple(FrameTime() + 0.1, function()
            if !IsValid(veh) then
                return
            end

            if wasDriver and !veh:IsEngineActive() then
                veh:SetRadioOn(false)
            end
        end)
    end)

    hook.Add("simfphysOnEngine", "CRadio.ControlRadio", function(veh, active, ignoresettings)
        veh:SetRadioOn(active)
    end)

    hook.Add("LVS.OnVehicleDestroyed", "CRadio.DisableRadio", function(veh, attacker, inflictor)
        veh:SetRadioOn(false)
    end)

    -- HACK: We cannot avoid this, even modifying base classes doesn't work because of inheritance hell.
    hook.Add("OnEntityCreated", "CRadio.CustomEngineNotify", function(ent)
        timer.Simple(0, function()
            if !IsValid(ent) or !(ent.LVS or ent.IsGlideVehicle) then
                return
            end

            if ent.IsGlideVehicle then
                ent:NetworkVarNotify("EngineState", function(gEnt, name, old, new)
                    if old == new then
                        return
                    end

                    local gType = gEnt.VehicleType
                    local isAircraft = gType == Glide.VEHICLE_TYPE.HELICOPTER or gType == Glide.VEHICLE_TYPE.PLANE

                    if (isAircraft and new >= 1) or new == 2 then
                        gEnt:SetRadioOn(true)
                    else
                        gEnt:SetRadioOn(false)
                    end
                end)
            elseif ent.LVS then
                ent:NetworkVarNotify("EngineActive", function(lvEnt, name, old, new)
                    if old == new then
                        return
                    end

                    lvEnt:SetRadioOn(new)
                end)
            end
        end)
    end)
else
    local function OnPlayerEnteredVehicle(ply, veh)
        -- Get the real vehicle entity in case we're using a custom base.
        veh = CLib.GetVehicle(veh)

        local switchedSeats = CurTime() < (ply.m_flLastVehicleExit or 0) + 0.5
        local stream = veh:GetRadioStream()

        if IsValid(stream) then
            stream:Set3DEnabled(false)
        end

        if !switchedSeats and !IsValid(stream) and veh:GetRadioOn() then
            local currentStation = veh:GetCurrentStation()

            -- The radio is set to off.
            if !IsValid(currentStation) then
                return
            end

            local nStream = currentStation:Stream(veh)

            if !IsValid(nStream) then
                return
            end

            nStream:Play(true)
        end
    end

    local should3D = GetConVar("cl_cradio_3d")

    local function OnPlayerLeaveVehicle(ply, veh)
        local exitTime = CurTime()

        ply.m_flLastVehicleExit = exitTime

        local cGUI = CRadio:GetGUI()

        cGUI:Close()

        -- Get the real vehicle entity in case we're using a custom base.
        veh = CLib.GetVehicle(veh)

        if !IsValid(veh) then
            return
        end

        local cStream = veh:GetRadioStream()

        if !IsValid(cStream) then
            return
        end

        timer.Simple(engine.ServerFrameTime() + 0.1, function()
            if !IsValid(veh) then
                return
            end

            local inVehicle = ply:InVehicle()
            local switchedSeats = inVehicle and CurTime() < exitTime + 0.5

            if !IsValid(cStream) or inVehicle or switchedSeats then
                return
            end

            local curSong = cStream:GetCurrentSong()

            if !should3D:GetBool() or !IsValid(curSong) or curSong:GetPlayMethod() == sound.PlayURL then
                veh:StopRadioStream(true)

                return
            end

            cStream:Set3DEnabled(true)
        end)
    end

    local PLAYER = FindMetaTable("Player")
    local vClient = nil
    local hasEntered = false
    local wasInVehicle, lastVehicle = false, nil
    local plyInVehicle, plyGetVehicle = PLAYER.InVehicle, PLAYER.GetVehicle

    hook.Add("Tick", "CRadio.VehicleHandler", function()
        vClient = vClient or LocalPlayer()

        if vClient == NULL then
            vClient = nil

            return
        end

        local inVehicle = plyInVehicle(vClient)

        if inVehicle and !hasEntered then
            local vehicle = plyGetVehicle(vClient)

            OnPlayerEnteredVehicle(vClient, vehicle)

            hasEntered = true
            wasInVehicle, lastVehicle = true, vehicle
        end

        if hasEntered and wasInVehicle and !inVehicle then
            OnPlayerLeaveVehicle(vClient, lastVehicle)

            hasEntered = false
            wasInVehicle, lastVehicle = false, nil
        end
    end)

    local function StationVarChanged(ent, name, old, new)
        local oldStream = ent:GetRadioStream()

        -- If the ent's radio is off, don't play/stop any radio stream.
        if !ent:GetRadioOn()  then
            return
        end

        local station = CRadio:GetStation(new)

        -- If we have a valid stream active and it's station is the same as the new one, stop.
        if IsValid(oldStream) and oldStream:GetStation() == station then
            return
        end

        -- Stop the vehicle's existing audio channel if present.
        ent:StopRadioStream(true)

        if !IsValid(station) then
            return
        end

        local isOurVehicle = ent == CLib.GetVehicle() and !ent.CRadio
        local curSong = station:GetCurrentSong()

        -- If we're not in the vehicle and the station uses URLs, don't start a stream.
        if !isOurVehicle and (!should3D:GetBool() or curSong:GetPlayMethod() == sound.PlayURL) then
            return
        end

        local stream = station:Stream(ent, true, function(cStream, channel, sEnt)
            -- We only want this to run on the first channel's initialization.
            if !isOurVehicle or cStream.DidUpdate or channel == cStream:GetPreBufferChannel() then
                return
            end

            local cCurSong = cStream:GetCurrentSong()
            local cGUI = CRadio:GetGUI()

            cGUI:DoPlayNotification(cCurSong, channel, sEnt)
        end)

        if !IsValid(stream) then
            return
        end

        -- Not our vehicle? Set the stream to 3D.
        if !isOurVehicle then
            stream:Set3DEnabled(true)
        end

        stream:Play(true)
    end

    local function RadioStateVarChanged(ent, name, old, new)
        local currentStation = ent:GetCurrentStation()

        if new and !IsValid(currentStation) then
            return
        end

        if !new then
            ent:StopRadioStream(true, 0.25)

            return
        end

        local isOurVehicle = ent == CLib.GetVehicle() and !ent.CRadio
        local curSong = currentStation:GetCurrentSong()

        -- If we're not in the vehicle and the station uses URLs, don't start a stream.
        if !isOurVehicle and (!should3D:GetBool() or curSong:GetPlayMethod() == sound.PlayURL) then
            return
        end

        local stream = currentStation:Stream(ent, true)

        if !IsValid(stream) then
            return
        end

        -- Not our vehicle? Set the stream to 3D.
        if !isOurVehicle then
            stream:Set3DEnabled(true)
        end

        stream:Play(true)
    end

    local stationVar = "CRadio.Station"
    local radioVar = "CRadio.RadioState"

    hook.Add("EntityNetworkedVarChanged", "CRadio.RadioChange", function(ent, name, old, new)
        -- If the var changed isn't our NW2 var, we do nothing.
        if name == stationVar then
            -- Handles the "CRadio.Station" NW2 var.
            StationVarChanged(ent, name, old, new)
        elseif name == radioVar then
            -- Handles the "CRadio.RadioState" NW2 var.
            RadioStateVarChanged(ent, name, old, new)
        end
    end)

    local seatClass = "prop_vehicle_prisoner_pod"
    local dbgTransmitFormat = "%s changed transmit state to %s."

    hook.Add("NotifyShouldTransmit", "CRadio.PVSHandler", function(ent, shouldTransmit)
        if !IsValid(ent) then
            return
        end

        local isVehicle = ent:IsVehicle()

        if !isVehicle and !ent.IsGlideVehicle and !ent.LVS then
            return
        end

        -- Check if we're a seat for custom vehicle.
        if isVehicle and ent:GetClass() == seatClass then
            return
        end

        local veh = CLib.GetVehicle(ent)

        if !IsValid(veh) then
            return
        end

        CRadio:DebugPrint(string.format(dbgTransmitFormat, tostring(ent), tostring(shouldTransmit)))

        local cStream = ent:GetRadioStream()

        if !shouldTransmit and IsValid(cStream) then
            ent:StopRadioStream(true, 0.25)

            return
        end

        local currentStation = ent:GetCurrentStation()

        if !ent:GetRadioOn() or !IsValid(currentStation) then
            return
        end

        local isOurVehicle = ent == CLib.GetVehicle() and !ent.CRadio
        local curSong = currentStation:GetCurrentSong()

        -- If we're not in the vehicle and the station uses URLs, don't start a stream.
        if !isOurVehicle and (!should3D:GetBool() or curSong:GetPlayMethod() == sound.PlayURL) then
            return
        end

        local stream = currentStation:Stream(ent)

        if !IsValid(stream) then
            return
        end

        -- Not our vehicle? Set the stream to 3D.
        if !isOurVehicle then
            stream:Set3DEnabled(true)
        end

        stream:Play()
    end)

    hook.Add("EntityRemoved", "CRadio.ClearSounds", function(ent, fullUpdate)
        if fullUpdate or !IsValid(ent) then
            return
        end

        local isVehicle = ent:IsVehicle()

        if !isVehicle and !ent.LVS then
            return
        end

        -- Check if we're a seat for custom vehicle.
        if isVehicle and ent:GetClass() == seatClass then
            return
        end

        local veh = CLib.GetVehicle(ent)

        if !IsValid(veh) then
            return
        end

        local staticSnd = veh.StaticSound

        if staticSnd then
            staticSnd:Stop()
        end

        veh:StopRadioStream(true, 0.5)

        local ourVehicle = CLib.GetVehicle()

        -- Our vehicle is destroyed, so close the GUI to prevent errors.
        if IsValid(ourVehicle) and veh == ourVehicle then
            local cGUI = CRadio:GetGUI()

            cGUI:Close()
        end
    end)

    local loopback = GetConVar("voice_loopback")
    local shouldLower = GetConVar("cl_cradio_volume_lower_on_speak")
    local playersSpeaking = 0

    hook.Add("PlayerStartVoice", "CRadio.LowerVolume", function(ply)
        local client = LocalPlayer()

        if ply == client and !loopback:GetBool() then
            return
        end

        playersSpeaking = playersSpeaking + 1

        if playersSpeaking <= 0 or !shouldLower:GetBool() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        local stream = vehicle:GetRadioStream()

        if !IsValid(stream) then
            return
        end

        stream:SetPlayersSpeaking(true)
    end)

    hook.Add("PlayerEndVoice", "CRadio.ResetVolume", function(ply)
        local client = LocalPlayer()

        if ply == client and !loopback:GetBool() then
            return
        end

        playersSpeaking = math.max(0, playersSpeaking - 1)

        if playersSpeaking != 0 or !shouldLower:GetBool() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        local stream = vehicle:GetRadioStream()

        if !IsValid(stream) then
            return
        end

        stream:SetPlayersSpeaking(false)
    end)

    concommand.Add("+cradio_gui", function(ply, cmd, args, argsStr)
        local cGUI = CRadio:GetGUI()

        cGUI:Open()
    end)

    concommand.Add("-cradio_gui", function(ply, cmd, args, argsStr)
        local cGUI = CRadio:GetGUI()

        cGUI:Close()
    end)

    local overrideMenu = GetConVar("cl_cradio_gui_spawnmenu")

    hook.Add("OnSpawnMenuOpen", "CRadio.GUI.Open", function()
        if !overrideMenu:GetBool() then
            return
        end

        local cGUI = CRadio:GetGUI()

        cGUI:Open()
    end)

    hook.Add("OnSpawnMenuClose", "CRadio.GUI.Close", function()
        if !overrideMenu:GetBool() then
            return
        end

        local cGUI = CRadio:GetGUI()

        cGUI:Close()
    end)

    local enabled = GetConVar("cl_cradio")

    hook.Add("SpawnMenuOpen", "CRadio.GUI.DisableSpawnMenu", function()
        if !enabled:GetBool() or !overrideMenu:GetBool() then
            return
        end

        local ply = LocalPlayer()

        if !ply:InVehicle() or !ply:IsDriver() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !vehicle:GetRadioOn() then
            return
        end

        return false
    end)
end