if CLIENT then
    CreateClientConVar("cl_cradio", 1, true, false, "Enables/disables the radio by stopping channel creation and disallowing opening the GUI.", 0, 1)
    CreateClientConVar("cl_cradio_prebuffer", 1, true, false, "Makes the upcoming track for your current station preload.", 0, 1)
    CreateClientConVar("cl_cradio_notification", 1, true, false, 'Shows the "now playing" notification on station change or next track.', 0, 1)
    CreateClientConVar("cl_cradio_static", 0, true, false, "Enables GTA:SA-like static when switching stations.", 0, 1)
    CreateClientConVar("cl_cradio_volume", 1.0, true, false, "Sets the volume of all audio channels. Defaults to 1.0.", 0, 3.0)
    CreateClientConVar("cl_cradio_volume_lower_on_speak", 1, true, false, "Lowers the volume of the current station's audio channel when players you can hear are speaking.", 0, 1)
    CreateClientConVar("cl_cradio_gui_spawnmenu", 1, true, false, "Enables the GUI opening instead of the spawnmenu when the relevant bind is pressed.", 0, 1)

    cvars.AddChangeCallback("cl_cradio", function(name, old, new)
        if old == new or new then
            return
        end

        local stations = CRadio:GetStations(true)

        if table.IsEmpty(stations) then
            return
        end

        for i = 1, #stations do
            local station = stations[i]
            local streams = station:GetStreams()

            if table.IsEmpty(streams) then
                continue
            end

            for ent, stream in pairs(streams) do
                ent:StopRadioStream(true)
            end
        end
    end)

    concommand.Add("cl_cradio_stop_stream", function(ply, cmd, args, argStr)
        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        vehicle:StopRadioStream(true)
    end)

    concommand.Add("cl_cradio_restart_stream", function(ply, cmd, args, argStr)
        local vehicle = CLib.GetVehicle()

        if !IsValid(vehicle) then
            return
        end

        vehicle:StopRadioStream()

        local station = vehicle:GetCurrentStation()

        if !station then
            return
        end

        local stream = station:Stream(vehicle)

        if IsValid(stream) then
            stream:Play(true)
        end
    end)

    concommand.Add("cl_cradio_stop_static", function(ply, cmd, args, argStr)
        local stations = CRadio:GetStations(true)

        if table.IsEmpty(stations) then
            return
        end

        for i = 1, #stations do
            local station = stations[i]
            local streams = station:GetStreams()

            if table.IsEmpty(streams) then
                continue
            end

            for ent, stream in pairs(streams) do
                stream:StopStaticSound()
            end
        end
    end)

    local function RadioSettings(panel)
        panel:Help("Toggles")
        panel:CheckBox("Enable?", "cl_cradio")
        panel:CheckBox("Enable prebuffering?", "cl_cradio_prebuffer")
        panel:CheckBox('Enable "now playing" notification?', "cl_cradio_notification")
        panel:CheckBox("Enable GTA:SA-like static on station change?", "cl_cradio_static")
        panel:CheckBox("Enable volume lowering on player speaking?", "cl_cradio_volume_lower_on_speak")
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