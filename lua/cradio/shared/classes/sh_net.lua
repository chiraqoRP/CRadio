local NetClass = {}
NetClass.__index = NetClass

function NetClass:Initialize(ply)
	if CLIENT then
		return
	end

	-- print("[Net Object] - CRadio | Initialized!")

	local stations = CRadio:GetStations(true)

	self:NetworkAllPlaylists(stations, ply)
end

local classString = "[Net Object] - CRadio"

function NetClass:__tostring()
	return classString
end

-- CLIENT --> SERVER
-- Networks a play request (start/stop station) to the server.
function NetClass:SendPlayRequest(station, ent)
	if SERVER then
		return
	end

	local isValid = station and station:IsValid()

	if isValid and !station:IsStation() then
		return
	end

	local isEnabling = isValid or false

	-- print("[NetClass] - SendPlayRequest | isEnabling: ", isEnabling)

	-- Request net message
	net.Start("CRadio.Core.RequestStatusChange")
	net.WriteBool(isEnabling)

	local isCustomEnt = isentity(ent)

	-- COMMENT:
	net.WriteBool(isCustomEnt)

	if isCustomEnt then
		net.WriteEntity(ent)
	end

	if isEnabling then
		net.WriteString(station:GetName())
	end

	net.SendToServer()
end

-- SERVER
-- Receives a play request (start/stop station) from a client.
function NetClass:ReceivePlayRequest(len, ply)
	if CLIENT then return end

	local isEnabling = net.ReadBool()
	local station = nil

	if isEnabling then
		station = CRadio:GetStation(net.ReadString())
	end

	-- COMMENT:
	local ent = ply:GetVehicle()
	local isCustomEnt = net.ReadBool()

	if isCustomEnt then
		ent = net.ReadEntity()
	end

	-- COMMENT
	if isCustomEnt and !ent.IsCRadioEnt then
		return
	end

	if isCustomEnt then
		local processPlayRequest = ent.ProcessPlayRequest

		-- COMMENT
		if isfunction(processPlayRequest) then
			processPlayRequest(ent, ply, station)
		end
	else
		-- Fuck off skid.
		if !ply:IsDriver() then
			return
		end

		-- COMMENT
		local vehicle = CLib.GetVehicle(ent)

		-- If the vehicle's engine isn't active, the radio can't be on.
		if !vehicle:IsEngineActive() then
			return
		end

		vehicle:SetCurrentStation(station or nil)
	end
end

-- SERVER --> CLIENT
-- Networks every playlist to clients.
function NetClass:NetworkAllPlaylists(stations, ply)
	if CLIENT then return end

	local stationCount = #stations

	-- Playlist net message
	net.Start("CRadio.Station.NetworkPlaylist")
	net.WriteUInt(stationCount, 8)

	local anyValidPlaylists = false

	for i = 1, stationCount do
		local station = stations[i]
		local playlist = station:GetPlaylist()
		local songCount = #playlist

		net.WriteString(station:GetName())

		local curSong = station:GetCurrentSong()
		local songEndTime = (curSong and curSong:GetEndTime()) or CurTime()

		net.WriteFloat(songEndTime)
		net.WriteUInt(songCount, 10)

		for k = 1, songCount do
			local song = playlist[k]

			net.WriteUInt(song:GetID(), 16)
		end

		if !anyValidPlaylists then
			anyValidPlaylists = !table.IsEmpty(playlist)
		end
	end

	if !anyValidPlaylists then
		net.Abort()

		print("[CRadio] | None of your stations have songs in their playlists!")

		return
	end

	if ply then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

-- SERVER --> CLIENT
-- Networks a playlist to clients.
function NetClass:NetworkPlaylist(station)
	if CLIENT then return end

	-- Playlist net message
	net.Start("CRadio.Station.NetworkPlaylist")
	net.WriteUInt(1, 8)

	local playlist = station:GetPlaylist()
	local songCount = #playlist

	net.WriteString(station:GetName())

	local curSong = station:GetCurrentSong()
	local songEndTime = (curSong and curSong:GetEndTime()) or CurTime()

	net.WriteFloat(songEndTime)
	net.WriteUInt(songCount, 10)

	for k = 1, songCount do
		local song = playlist[k]

		net.WriteUInt(song:GetID(), 16)
	end

	net.Broadcast()
end

-- CLIENT
-- Receives networked playlist(s).
function NetClass:ReceivePlaylist(len)
	if SERVER then return end

	local songs = CRadio:GetSongs()
	local stationCount = net.ReadUInt(8)

	for i = 1, stationCount do
		local station = CRadio:GetStation(net.ReadString())
		local playlist = station:GetPlaylist()
		local songEndTime = net.ReadFloat() - CurTime()
		local songCount = net.ReadUInt(10)

		for k = 1, songCount do
			local song = songs[net.ReadUInt(16)]

			playlist[k] = song
		end

		local firstSong = playlist[1]

		if firstSong then
			firstSong:SetStartTime(songEndTime - firstSong:GetLength())
		end

		-- print("ReceivePlaylist | NextPlaylistRefresh: ", songEndTime)

		station:SetNextPlaylistRefresh(songEndTime)

		-- COMMENT
		station:UpdateRadioChannels()
	end
end

CRadioNetClass = NetClass