-- CSLua
AddCSLuaFile("cradio/shared/sh_convars.lua")

if SERVER then
    AddCSLuaFile("cradio/client/classes/cl_gui.lua")
end

AddCSLuaFile("cradio/shared/classes/sh_net.lua")
AddCSLuaFile("cradio/shared/classes/sh_core.lua")
AddCSLuaFile("cradio/shared/classes/sh_song.lua")
AddCSLuaFile("cradio/shared/classes/sh_station.lua")
AddCSLuaFile("cradio/shared/classes/sh_subplaylist.lua")
AddCSLuaFile("cradio/shared/sh_hooks.lua")
AddCSLuaFile("cradio/shared/sh_meta.lua")

-- Includes
include("cradio/shared/sh_convars.lua")

if CLIENT then
    include("cradio/client/classes/cl_gui.lua")
end

include("cradio/shared/classes/sh_net.lua")
include("cradio/shared/classes/sh_core.lua")
include("cradio/shared/classes/sh_song.lua")
include("cradio/shared/classes/sh_station.lua")
include("cradio/shared/classes/sh_subplaylist.lua")
include("cradio/shared/sh_hooks.lua")
include("cradio/shared/sh_meta.lua")

local pathFormat = "cradio/shared/stations/%s"
local stations = file.Find("cradio/shared/stations/*.lua", "LUA")

for i = 1, #stations do
    local station = stations[i]
    local stationPath = string.format(pathFormat, station)

    AddCSLuaFile(stationPath)
    include(stationPath)
end