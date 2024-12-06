if CLIENT then
    CreateClientConVar("cl_cradio", 1, true, false, "", 0, 1)
    CreateClientConVar("cl_cradio_prebuffer", 1, true, false, "", 0, 1)
    CreateClientConVar("cl_cradio_notification", 1, true, false, "", 0, 1)
    CreateClientConVar("cl_cradio_volume", 1.0, true, false, "", 0, 2.0)
    CreateClientConVar("cl_cradio_failuredelay", 5, true, false, "", 5, 30)
    CreateClientConVar("cl_cradio_gui_spawnmenu", 1, true, false, "Enables or disables overriding the spawnmenu.", 0, 1)

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

            print("cl_cradio_volume - any channels?", !table.IsEmpty(radioChannels))

            if table.IsEmpty(radioChannels) then
                continue
            end

            for ent, channel in pairs(radioChannels) do
                if !channel or !channel:IsValid() or math.Round(old, 3) != math.Round(channel:GetVolume(), 3) then
                    return
                end

                channel:SetVolume(new)

                -- PREBUFFER:
                local preBufferChannel = ent.acPreBuffer

                if !preBufferChannel or !preBufferChannel:IsValid() or math.Round(old, 3) != math.Round(preBufferChannel:GetVolume(), 3) then
                    return
                end

                preBufferChannel:SetVolume(new)
            end
        end
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
else
    -- server_cvars
end