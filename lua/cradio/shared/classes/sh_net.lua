local NetClass = {}
NetClass.__index = NetClass

function NetClass:Initialize(ply)
	if CLIENT then
		return
	end

	local stations = CRadio:GetStations(true)

	self:NetworkAllPlaylists(stations, ply)
end

local classString = "[Net Object] - CRadio"

function NetClass:__tostring()
	return classString
end

local STATION_ID_BITS = 8

--- CLIENT --> SERVER
--- Networks a play request (start/stop station) to the server.
function NetClass:SendPlayRequest(station, ent)
	if SERVER then
		return
	end

	local isValid = station and station:IsValid()

	if isValid and !station:IsStation() then
		return
	end

	local isEnabling = isValid or false

	-- Request net message
	net.Start("CRadio.RequestStatusChange")
	net.WriteBool(isEnabling)

	if isEnabling then
		net.WriteUInt(station:GetID(), STATION_ID_BITS)
	end

	local isCustomEnt = isentity(ent)

	net.WriteBool(isCustomEnt)

	if isCustomEnt then
		net.WriteEntity(ent)
	end

	net.SendToServer()
end

local REQUEST_COOLDOWN = 0.5
local lastRequest = {}

--- SERVER
--- Receives a play request (start/stop station) from a client.
function NetClass:ReceivePlayRequest(len, ply)
	local curTime = CurTime()

	if CLIENT or !IsValid(ply) or (lastRequest[ply] or 0) + REQUEST_COOLDOWN >= curTime then
		return
	end

	lastRequest[ply] = curTime

	local isEnabling = net.ReadBool()
	local station = nil
	local id = net.ReadUInt(STATION_ID_BITS)

	if isEnabling then
		station = CRadio:GetStation(id)
	end

	local ent = ply:GetVehicle()
	local isCustomEnt = net.ReadBool()

	if isCustomEnt then
		ent = net.ReadEntity()
	end

	-- Fuck off skid.
	if isCustomEnt and !ent.CRadio then
		return
	end

	if isCustomEnt then
		local processPlayRequest = ent.ProcessPlayRequest

		-- Make sure the custom entity actually defines a proper play method.
		if isfunction(processPlayRequest) then
			processPlayRequest(ent, ply, station)
		end
	else
		-- Fuck off skid.
		if !ply:IsDriver() then
			return
		end

		local vehicle = CLib.GetVehicle(ent)

		-- If the vehicle's engine isn't active, the radio can't be on.
		if !vehicle:IsEngineActive() then
			return
		end

		vehicle:SetCurrentStation(station or nil)
	end
end

--- SERVER --> CLIENT
--- Networks all playlists to client(s).
function NetClass:NetworkAllPlaylists(stations, ply)
	if CLIENT then
		return
	end

	local stationCount = #stations

	-- Playlist net message
	net.Start("CRadio.NetworkPlaylist")
	net.WriteUInt(stationCount, STATION_ID_BITS)

	local anyValidPlaylists = false

	for i = 1, stationCount do
		local station = stations[i]
		local playlist = station:DoNetwork(true)

		if !anyValidPlaylists then
			anyValidPlaylists = !table.IsEmpty(playlist)
		end
	end

	if !anyValidPlaylists then
		net.Abort()

		CRadio:DebugPrint("None of your stations have songs in their playlists!")

		return
	end

	if ply then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

local SONG_ID_BITS = 16
local SONG_COUNT_BITS = 10

--- CLIENT
--- Receives networked playlist(s).
function NetClass:ReceivePlaylist(len)
	if SERVER then
		return
	end

	local songs = CRadio:GetSongs()
	local stationCount = net.ReadUInt(STATION_ID_BITS)

	for i = 1, stationCount do
		local station = CRadio:GetStation(net.ReadUInt(STATION_ID_BITS))
		local playlist = station:GetPlaylist()
		local songEndTime = net.ReadFloat()
		local songCount = net.ReadUInt(SONG_COUNT_BITS)

		for k = 1, songCount do
			local id = net.ReadUInt(SONG_ID_BITS)
			local song = songs[id]

			playlist[k] = song
		end

		local firstSong = playlist[1]

		if firstSong then
			firstSong:SetStartTime(songEndTime - firstSong:GetLength())
		end

		station:SetNextPlaylistRefresh(songEndTime)

		-- Calling this on CLIENT in a timer will result in nothing happening (because the playlist is empty!) and the station just doing nothing.
		-- This fixes that, albeit by introducing some unavoidable delay to the song transition.
		station:UpdateStreams()
	end
end

CRadioNetClass = NetClass

if CLIENT then
    net.Receive("CRadio.NetworkPlaylist", function(len)
		local cNet = CRadio:GetNet()

		cNet:ReceivePlaylist(len)
	end)
else
    util.AddNetworkString("CRadio.RequestStatusChange")
    util.AddNetworkString("CRadio.NetworkPlaylist")

	net.Receive("CRadio.RequestStatusChange", function(len, ply)
		local cNet = CRadio:GetNet()

		cNet:ReceivePlayRequest(len, ply)
	end)
end