if SERVER then
    hook.Add("PlayerFullLoad", "CRadio.NetworkPlaylists", function(ply)
        if ply:IsBot() then return end

        if !CRadio:IsInitialized() then
            CRadio:Initialize()
        end

        MsgC(color_white, "[", Color(200, 0, 0), "CRadio", color_white, "] - PlayerFullLoad ran!", "\n")

        local cNet = CRadio:GetNet()

        -- Networks all playlists to the connected player.
        cNet:Initialize(ply)
    end)

    hook.Add("PlayerEnteredVehicle", "CRadio.Core.ControlRadio", function(ply, veh, role)
        -- Get the real vehicle entity in case we're using simfphys/LVS.
        veh = CLib.GetVehicle(veh)

        local plyTable = ply:GetTable()
        local wasEngineActive = veh:IsEngineActive()

        plyTable.m_LastVehicleEnter = CurTime()

        timer.Simple(FrameTime() + 0.1, function()
            if !IsValid(ply) or !IsValid(veh) then
                return
            end

            local engineActive = veh:IsEngineActive()

            if ply:IsDriver(veh) and (!wasEngineActive and engineActive) then
                veh:SetRadioOn(true)
            end
        end)
    end)

    hook.Add("PlayerLeaveVehicle", "CRadio.Core.ControlRadio", function(ply, veh)
        -- Get the real vehicle entity in case we're using simfphys/LVS.
        veh = CLib.GetVehicle(veh)

        local plyTable = ply:GetTable()
        local exitTime = CurTime()
        local wasDriver = veh:GetDriver() == ply

        plyTable.m_LastVehicleExit = exitTime

        timer.Simple(FrameTime() + 0.1, function()
            if !IsValid(veh) then
                return
            end

            if wasDriver and !veh:IsEngineActive() then
                veh:SetRadioOn(false)
            end
        end)
    end)

    -- FIXME: Has issues with simfphys
    hook.Add("simfphysOnEngine", "CRadio.Core.ControlRadio", function(veh, active, ignoresettings)
        local driver = veh:GetDriver()
        local plyTable = driver:GetTable()
        local curTime = CurTime()

        -- If the driver enters/exits the vehicle within the last half-second, the vehicle hooks will handle the engine's status.
        if curTime > (plyTable.m_LastVehicleEnter or 0) + 0.5 or curTime > (plyTable.m_LastVehicleExit or 0) + 0.5 then
            return
        end

        veh:SetRadioOn(active)
    end)
else
    hook.Add("PlayerEnteredVehicle", "CRadio.Core.ControlRadio", function(ply, veh)
        -- Get the real vehicle entity in case we're using simfphys/LVS.
        veh = CLib.GetVehicle(veh)

        local plyTable = ply:GetTable()
        local wasEngineActive = veh:IsEngineActive()

        plyTable.m_LastVehicleEnter = CurTime()

        timer.Simple(engine.ServerFrameTime() + 0.01, function()
            if !IsValid(veh) then return end

            local switchedSeats = CurTime() < (plyTable.m_LastVehicleExit or 0) + 0.5
            local engineActive = veh:IsEngineActive()

            if !switchedSeats and (wasEngineActive and engineActive) then
                local currentStation = veh:GetCurrentStation()

                -- The radio is set to off.
                if !currentStation then return end

                currentStation:RadioChannel(veh, false, true)
            end
        end)
    end)

    hook.Add("PlayerLeaveVehicle", "CRadio.Core.ControlRadio", function(ply, veh)
        local cGUI = CRadio:GetGUI()

        cGUI:Close()

        -- Get the real vehicle entity in case we're using simfphys/LVS.
        veh = CLib.GetVehicle(veh)

        local plyTable = ply:GetTable()
        local exitTime = CurTime()

        plyTable.m_LastVehicleExit = exitTime

        timer.Simple(engine.ServerFrameTime() + 0.01, function()
            if !IsValid(veh) then return end

            local inVehicle = ply:InVehicle()
            local switchedSeats = inVehicle and CurTime() < exitTime + 0.5

            if !inVehicle or !switchedSeats then
                veh:StopRadioChannel(true)
            end
        end)
    end)

    local function StationVarChanged(ent, name, old, new)
        local ply = LocalPlayer()
        local isCustomEnt = ent.IsCRadioEnt

        -- If we're not in the vehicle, don't play/stop any radio channel.
        if !isCustomEnt and CLib.GetVehicle(ply:GetVehicle()) != ent then
            return
        end

        local station = CRadio:GetStation(new)
        local oldRadioChannel = ent:GetRadioChannel()

        -- If we have a valid audio channel active and it's station is the same as the new one, stop.
        if oldRadioChannel and oldRadioChannel:GetStation() == station then
            return
        end

        -- Stop the vehicle's existing audio channel if present.
        ent:StopRadioChannel(true)

        if !station then
            return
        end

        -- print("StationVarChanged | station: ", station)

        station:RadioChannel(ent, false, true, true)
    end

    local function RadioStateVarChanged(ent, name, old, new)
        local ply = LocalPlayer()

        -- If we're not in the vehicle, don't play/stop any audio channel.
        if CLib.GetVehicle(ply:GetVehicle()) != ent then
            return
        end

        local currentStation = CRadio:GetStation(ent:GetCurrentStation())

        if new and !currentStation then
            return
        end

        if !new then
            ent:StopRadioChannel(true, 0.25)
        else
            currentStation:RadioChannel(ent, false, true, true)
        end
    end

    local stationVar = "CRadio.Station"
    local radioVar = "CRadio.RadioState"

    hook.Add("EntityNetworkedVarChanged", "CRadio.Core.RadioChange", function(ent, name, old, new)
        -- print("isOurVar? ", name == stationVar or name == radioVar)

        -- If the var changed isn't our NW2 var, we do nothing.
        if name == stationVar then
            -- Handles the "CRadio.Station" NW2 var.
            StationVarChanged(ent, name, old, new)
        elseif name == radioVar then
            -- Handles the "CRadio.RadioState" NW2 var.
            RadioStateVarChanged(ent, name, old, new)
        end
    end)

    hook.Add("EntityRemoved", "CRadio.Core.ClearSounds", function(ent, fullUpdate)
        if fullUpdate or !ent:IsVehicle() then
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

        veh:StopRadioChannel()
    end)

    hook.Add("PlayerButtonUp", "CRadio.GUI.Release", function(ply, button)
        if !(button == KEY_SLASH and IsFirstTimePredicted()) then return end

        local cGUI = CRadio:GetGUI()

        cGUI:Close()
    end)

    hook.Add("PlayerButtonDown", "CRadio.GUI.Press", function(ply, button)
        if !(button == KEY_SLASH and IsFirstTimePredicted()) then return end

        local cGUI = CRadio:GetGUI()

        cGUI:Open()
    end)

    local overrideCVar = CreateClientConVar("cl_cradio_gui_spawnmenu", 1, true, false, "Enables or disables overriding the spawnmenu.", 0, 1)

    hook.Add("OnSpawnMenuOpen", "CRadio_GUI_Open", function()
        if !overrideCVar:GetBool() then
            return
        end

        local cGUI = CRadio:GetGUI()

        cGUI:Open()
    end)

    hook.Add("OnSpawnMenuClose", "CRadio_GUI_Close", function()
        if !overrideCVar:GetBool() then
            return
        end

        local cGUI = CRadio:GetGUI()

        cGUI:Close()
    end)

    hook.Add("SpawnMenuOpen", "CRadio_GUI_Spawnmenu", function()
        if !overrideCVar:GetBool() then
            return
        end

        local ply = LocalPlayer()

        if !ply:InVehicle() or !ply:IsDriver() then
            return
        end

        return false
    end)
end