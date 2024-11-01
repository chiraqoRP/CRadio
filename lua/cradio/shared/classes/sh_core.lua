local CoreClass = {}
CoreClass.__index = CoreClass

function CoreClass:__constructor()
	self.Initialized = false

	-- Stores all of the station objects.
	self.Stations = {}

	-- Stores all of the station objects sequentially.
	self.SequentialStations = {}

	-- Stores all created songs with ID keys.
	self.Songs = {}

	self.Net = CRadioNetClass

	if CLIENT then
		self.GUI = CRadioGUIClass
	end
end

function CoreClass:Initialize()
	-- print("[Core Object] - CRadio | Initialize called!")

	if SERVER then
		for i = 1, #self.SequentialStations do
			local station = self.SequentialStations[i]

			if !station:IsValid() then
				continue
			end

			station:RefreshPlaylist(true)

			-- print("[Core Object] - CRadio | station ", station:GetName(), " initialized!")
		end
	end

	self.Initialized = true
end

local classString = "[Core Object] - CRadio"

function CoreClass:__tostring()
	return classString
end

function CoreClass:IsInitialized()
	return self.Initialized
end

function CoreClass:GetNet()
	return self.Net
end

function CoreClass:GetGUI()
	return self.GUI
end

function CoreClass:GetStations(sequential)
	return (sequential and self.SequentialStations) or self.Stations
end

function CoreClass:GetStation(name)
	if !string.IsValid(name) then
		return
	end

	return self.Stations[name]
end

function CoreClass:Station(name)
	-- Without a name, we can't possibly know what category the invoker wants.
	if !string.IsValid(name) then
		return
	end

	local fetchedStation = self:GetStation(name)

	-- If a station with the same name already exists, return it.
	if fetchedStation and fetchedStation:IsValid() then
		return fetchedStation
	end

	-- Create our new station and set it's name.
	local newStation = CRadioStationClass(name)

	-- Adds station to our core class tables.
	self.Stations[name] = newStation

	table.insert(self.SequentialStations, newStation)

	return newStation
end

function CoreClass:GetSongs()
	return self.Songs
end

function CoreClass:GetSong(id)
	-- Without an id, we can't possibly know which song to index.
	if !isnumber(id) then
		return
	end

	return self.Songs[id]
end

function CoreClass:Song(name)
	-- Without a name, the song cannot possibly be valid.
	if !string.IsValid(name) then
		return
	end

	-- Create our new song and set it's name.
	local newSong = CRadioSongClass(name)

	-- Add the song to our core song table.
	self.Songs[newSong:GetID()] = newSong

	return newSong
end

function CoreClass:SubPlaylist(name)
	-- Without a name, the sub-playlist cannot possibly be valid.
	if !string.IsValid(name) then
		return
	end

	-- Create our new sub-playlist and set it's name.
	local newSubPlaylist = CRadioSubPlaylistClass(name)

	return newSubPlaylist
end

local greenColor = Color(0, 255, 0)
local blueColor = Color(0, 180, 255)

function CoreClass:PrintInfo()
	local count = #self.SequentialStations

	for i = 1, count do
		local station = self.SequentialStations[i]

		if !station:IsValid() then
			continue
		end

		MsgC(color_white, "-----------------------\n")
		MsgC(blueColor, station, color_white, ":\n")
		MsgC(color_white, "Current Song: ", blueColor, station:GetCurrentSong(), "\n")
		MsgC(color_white, "Time until NextPlaylistRefresh: ", greenColor, math.abs(CurTime() - station:GetNextPlaylistRefresh()), color_white, " seconds!\n")
		
		if i == count then
			MsgC(color_white, "-----------------------\n")
		end
	end
end

CoreClass:__constructor()

CRadio = CoreClass