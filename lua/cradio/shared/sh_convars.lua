if CLIENT then
    CreateClientConVar("cl_cradio", 1, true, false, "Enables/disables the radio by stopping channel creation and disallowing opening the GUI.", 0, 1)
    CreateClientConVar("cl_cradio_prebuffer", 1, true, false, "Makes the upcoming track for your current station preload.", 0, 1)
    CreateClientConVar("cl_cradio_notification", 1, true, false, 'Shows the "now playing" notification on station change or next track.', 0, 1)
    CreateClientConVar("cl_cradio_volume", 1.0, true, false, "Sets the volume of all audio channels. Defaults to 1.0.", 0, 2.0)
    CreateClientConVar("cl_cradio_lower_on_speak", 1, true, false, "Lowers the volume of the current station's audio channel when players you can hear are speaking.", 0, 1)
    CreateClientConVar("cl_cradio_gui_spawnmenu", 1, true, false, "Enables the GUI opening instead of the spawnmenu when the relevant bind is pressed.", 0, 1)

    cvars.AddChangeCallback("cl_cradio", function(name, old, new)
        if old == new then
            return
        end

        local stations = CRadio:GetStations(true)

        if table.IsEmpty(stations) then
            return
        end

        for i = 1, #stations do
            local station = stations[i]
            local radioChannels = station:GetRadioChannels()

            if table.IsEmpty(radioChannels) then
                continue
            end

            for ent, channel in pairs(radioChannels) do
                if !channel or !channel:IsValid() then
                    return
                end

                channel:Stop()

                -- PREBUFFER:
                local preBufferChannel = ent.acPreBuffer

                if !preBufferChannel or !preBufferChannel:IsValid() then
                    return
                end

                preBufferChannel:Stop()
            end
        end
    end)

    cvars.AddChangeCallback("cl_cradio_volume", function(name, old, new)
        if old == new then
            return
        end

        local stations = CRadio:GetStations(true)

        if table.IsEmpty(stations) then
            return
        end

        for i = 1, #stations do
            local station = stations[i]
            local radioChannels = station:GetRadioChannels()

            if table.IsEmpty(radioChannels) then
                continue
            end

            for ent, channel in pairs(radioChannels) do
                if !channel or !channel:IsValid() or channel:IsFading() then
                    return
                end

                channel:SetVolume(new)

                -- PREBUFFER:
                local preBufferChannel = ent.acPreBuffer

                if !preBufferChannel or !preBufferChannel:IsValid() or preBufferChannel:IsFading() then
                    return
                end

                preBufferChannel:SetVolume(new)
            end
        end
    end)

    concommand.Add("cl_cradio_stop_channel", function(ply, cmd, args, argStr)
        if ply != LocalPlayer() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        vehicle:StopRadioChannel(true)
    end)

    concommand.Add("cl_cradio_restart_channel", function(ply, cmd, args, argStr)
        if ply != LocalPlayer() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        local station = vehicle:GetCurrentStation()

        if !station then
            return
        end

        station:RadioChannel(vehicle, false, true, false)
    end)

    concommand.Add("cl_cradio_stop_static", function(ply, cmd, args, argStr)
        if ply != LocalPlayer() then
            return
        end

        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        local staticSnd = vehicle.StaticSound

        if staticSnd then
            if staticSnd then
                staticSnd:Stop()
            end

            vehicle.StaticSound = nil
        end
    end)

    local function RadioSettings(panel)
        panel:Help("Toggles")
        panel:CheckBox("Enable?", "cl_cradio")
        panel:CheckBox("Enable prebuffering?", "cl_cradio_prebuffer")
        panel:CheckBox('Enable "now playing" notification?', "cl_cradio_notification")
        panel:CheckBox("Enable volume lowering on player speaking?", "cl_cradio_lower_on_speak")
        panel:CheckBox("Enable spawnmenu override?", "cl_cradio_gui_spawnmenu")
    
        panel:Help("Vars")
        panel:NumSlider("Volume", "cl_cradio_volume", 0, 2.0, 1)
    end
    
    hook.Add("PopulateToolMenu", "CRadio.Settings", function()
        spawnmenu.AddToolMenuOption("Options", "CRadio", "CRadio", "Settings", "", "", function(panel)
            panel:ClearControls()
    
            RadioSettings(panel)
        end)
    end)
else
    -- server_cvars
end