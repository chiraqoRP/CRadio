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

--- Whether CRadio has been initialized (stations created) or not.
-- @return {boolean} initialization status
function CoreClass:IsInitialized()
	return self.Initialized
end

--- Gets our CRadioNetClass object.
-- @return {cnet} our CRadioNetClass object
function CoreClass:GetNet()
	return self.Net
end

--- Gets our CRadioGUIClass object.
-- @return {cgui} our CRadioGUIClass object
function CoreClass:GetGUI()
	return self.GUI
end

--- Gets all installed stations.
-- @param {boolean} whether the table should be sequential or have name keys
-- @return {table} our station table
function CoreClass:GetStations(sequential)
	return (sequential and self.SequentialStations) or self.Stations
end

--- Gets an installed station via its name.
-- @param {string} our desired stations name
-- @return {station} the station if present, nil otherwise
function CoreClass:GetStation(name)
	if !string.IsValid(name) then
		return
	end

	return self.Stations[name]
end

--- Creates a new station.
-- @param {string} our new stations desired name, must be a valid string
-- @return {station} the station if created or the station with the same name if one is found
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

--- Gets all created songs.
-- @return {table} our song table
function CoreClass:GetSongs()
	return self.Songs
end

--- Gets a created song via its numerical id.
-- @param {integer} our desired songs id
-- @return {song} the song if present, nil otherwise
function CoreClass:GetSong(id)
	-- Without an id, we can't possibly know which song to index.
	if !isnumber(id) then
		return
	end

	return self.Songs[id]
end

--- Creates a new song.
-- @param {string} our new songs desired name, must be a valid string
-- @return {song} the song if created
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

--- Creates a new subplaylist.
-- @param {string} our new subplaylists desired name, must be a valid string
-- @return {subplaylist} the subplaylist if created
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