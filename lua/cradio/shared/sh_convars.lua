if CLIENT then
    CreateClientConVar("cl_cradio_notification", 1, true, false, "", 0, 1)
    CreateClientConVar("cl_cradio_volume", 1.0, true, false, "", 0, 2.0)
    CreateClientConVar("cl_cradio_failuredelay", 5, true, false, "", 5, 30)
    CreateClientConVar("cl_cradio_gui_spawnmenu", 1, true, false, "Enables or disables overriding the spawnmenu.", 0, 1)

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

            for _, channel in pairs(radioChannels) do
                if !channel or !channel:IsValid() or math.Round(old, 2) != math.Round(channel:GetVolume(), 2) then
                    return
                end
        
                channel:SetVolume(new)
            end
        end
    end)
else
    -- server_cvars
end