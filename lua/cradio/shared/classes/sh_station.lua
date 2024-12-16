local StationClass = {}
StationClass.__index = StationClass

local stationsGenerated = 0

function StationClass:__constructor(name, stationStruct)
	if stationsGenerated > 255 then
		ErrorNoHaltWithStack("[CRadio] | You have hit the station limit!")

		return
	end

	-- Set our name if one is provided.
	self:SetName(name)
	self.Icon = stationStruct.Icon

	-- Playlist randomization is enabled by default.
	self.Randomize = stationStruct.Randomize

	if self.Randomize == nil then
		self.Randomize = true
	end

	self.Songs, self.SongCount = {}, 0
	self.SubPlaylists = {}
	self.Playlist = {}

	-- Stores all of the client's radio channels.
	if CLIENT then
		self.RadioChannels = {}
	end

	-- Our ID doesn't need to be cryptographically secure, it's only used for __eq operations.
	self.ID = stationsGenerated + 1

	stationsGenerated = stationsGenerated + 1

    for key, val in pairs(stationStruct) do
		if self[key] != nil then
			continue
		end

		self[key] = val
    end
end

local formatString = "[Station Object] | %s"
local nullString = "[Station Object] | NULL"

function StationClass:__tostring()
	if !self:IsValid() then return nullString end

	return string.format(formatString, self.Name)
end

function StationClass:__eq(other)
	-- If either station lacks a name, they are not equal.
	if !self:IsValid() or !other:IsValid() then
		return false
	end

	return self.Name == other:GetName()
end

function StationClass:IsValid()
	return string.IsValid(self.Name)
end

function StationClass:New()
	local newStation = setmetatable({}, self)

	return newStation
end

function StationClass:Remove()
	local stations = CRadio:GetStations()

	-- Remove our station from the core class tables.
	stations[self.Name] = nil

	local seqStations = CRadio:GetStations(true)

	table.remove(seqStations, self.ID)

	-- TODO: Does this even do what I think it does?
	setmetatable(self, nil)
end

function StationClass:GetName()
	return self.Name
end

function StationClass:GetSanitizedName()
	return self.SanitizedName
end

local timerFormat = "CRadio.Playlist-%s"
local dangerousPattern = '[.*"/\\<>:|?]'
local emptyString = ""

function StationClass:SetName(name)
	-- Set our name if one is provided.
	self.Name = name

	-- Recreate our timer name.
	self.TimerName = string.format(timerFormat, name)

	-- Create and cache a sanitized string of our name to use for folder operations.
	self.SanitizedName, _ = string.gsub(self.Name, dangerousPattern, emptyString)
end

function StationClass:GetID()
	return self.ID
end

local defaultIcon = Material("cradio/gui/default.png", "mips")

function StationClass:GetIcon()
	if SERVER then
		return
	end

	return self.Icon or defaultIcon
end

function StationClass:GetStartTime()
	return self.StartTime or CurTime()
end

function StationClass:GetCurTime()
	return CurTime() - self.StartTime
end

function StationClass:GetNextPlaylistRefresh()
	return self.NextPlaylistRefresh or CurTime()
end

function StationClass:SetNextPlaylistRefresh(nextRefresh)
	self.NextPlaylistRefresh = nextRefresh

	local delay = math.max(nextRefresh - CurTime(), 0)

	timer.Create(self.TimerName, delay, 1, function()
		self:RefreshPlaylist()
	end)
end

if CLIENT then
	function StationClass:GetRadioChannels()
		return self.RadioChannels
	end
end

function StationClass:GetSongs()
	return self.Songs
end

function StationClass:GetCurrentSong()
	return self.Playlist[1]
end

function StationClass:GetLastSong()
	return self.LastSong
end

local limitFormat = "[CRadio] | You have hit the song limit in playlist %s!"

function StationClass:AddSong(song)
	if !song or !song:IsValid() then
		return
	end

	if self.SongCount > 1023 then
		ErrorNoHaltWithStack(string.format(limitFormat, tostring(self)))

		return
	end

	table.insert(self.Songs, song)

	self.SongCount = self.SongCount + 1
end

function StationClass:RemoveSong(song)
	if !song or !song:IsValid() then
		return
	end

	-- Remove the song from our songs table, and playlist if present in it.
	table.RemoveByValue(self.Songs, song)
	table.RemoveByValue(self.Playlist, song)
end

function StationClass:GetSubPlaylists()
	return self.SubPlaylists
end

function StationClass:AddSubPlaylist(subplaylist)
	if !subplaylist or !subplaylist:IsValid() then
		return
	end

	table.insert(self.SubPlaylists, subplaylist)
end

function StationClass:RemoveSubPlaylist(subplaylist)
	if !subplaylist or !subplaylist:IsValid() then
		return
	end

	-- Remove the sub-playlist from our sub-playlist table.
	table.RemoveByValue(self.SubPlaylists, subplaylist)

	-- This removes all of the songs from our station's playlist.
	-- This op is an O(n^2) loop, but you should never destroy sub-playlists to begin with.
	for i = 1, #self.Playlist do
		local song = self.Playlist[i]

		table.RemoveByValue(self.Playlist, song)
	end
end

function StationClass:GetPlaylist()
	return self.Playlist
end

local mathRandom = math.random

local function ShuffleKnown(tbl, count)
	for i = 1, count - 1 do
		local r = mathRandom(i, count)

		tbl[i], tbl[r] = tbl[r], tbl[i]
	end
end

local function InsertSubPlaylist(playlist, subPlaylist, index)
	local songs = subPlaylist:GetSongs()
	local shouldRandomize = subPlaylist:ShouldRandomize()
	local songCount = #songs
	local songsToInsert = {}
	local finalCount = 0

	-- Loop over the sub-playlist's songs table.
	for i = 1, songCount do
	    local song = songs[i]

		if (song:GetChance()) < mathRandom() then
			continue
		end

		local tbl = (shouldRandomize and songsToInsert) or playlist
		local position = (shouldRandomize and i) or index + finalCount

		table.insert(tbl, position, song)

		finalCount = finalCount + 1
	end

	if !shouldRandomize then
		return finalCount
	end

	ShuffleKnown(songsToInsert, finalCount)

	for i = 1, finalCount do
		local song = songsToInsert[i]

		table.insert(playlist, index + i, song)
	end

	return finalCount
end

function StationClass:GeneratePlaylist()
	if CLIENT then
		return
	end

	-- Empty our playlist table.
	self.Playlist = {}

	local songCount = #self.Songs
	local subPlaylistCount = #self.SubPlaylists
	local allCount = songCount + subPlaylistCount
	local finalCount = 0

	for i = 1, allCount do
		local isSubPlaylist = i > songCount
	    local object = (isSubPlaylist and self.SubPlaylists[i % songCount]) or self.Songs[i]

		if !object:IsValid() or (object:GetChance()) < mathRandom() then
			continue
		end

		table.insert(self.Playlist, object)

		finalCount = finalCount + 1
	end

	if self.Randomize then
		ShuffleKnown(self.Playlist, finalCount)
	end

	if subPlaylistCount <= 0 then
		return
	end

	local subSongsInsertCount = 0

	for i = 1, finalCount do
		local index = i + subSongsInsertCount
		local object = self.Playlist[index]

		if !object:IsSubPlaylist() then
			continue
		end

		object = table.remove(self.Playlist, index)

		local songsAdded = InsertSubPlaylist(self.Playlist, object, index)

		-- Subtract one from the count because table indexes start at 1, not 0.
		-- This is used to skip songs inserted by this sub-playlist and others.
		subSongsInsertCount = subSongsInsertCount + songsAdded - 1
	end
end

function StationClass:SortPlaylist(lastSong)
	if CLIENT or !self.Randomize then
		return
	end

	local songCount = #self.Playlist

	-- Our playlist isn't big enough for us to shift songs around without repeating artists.
	if songCount <= 8 then
		return
	end

	local songsToShift = {}
	local shiftCount = 0

	for i = 1, songCount do
		-- The last song should be left alone too.
		if i == songCount then
			continue
		end

	    local song = self.Playlist[i]
		local leftSong = (i == 1 and lastSong) or self.Playlist[i - 1]

		-- It's unlikely, but if the left song is nil somehow then skip it.
		if !leftSong then
			continue
		end

		-- We aren't sorting songs from sub-playlists.
		if song:GetParent():IsSubPlaylist() or leftSong:GetParent():IsSubPlaylist() then
			continue
		end

		-- If the artist's arent the same, neither song needs to be shifted.
		if song:GetArtist() != leftSong:GetArtist() then
			continue
		end

		-- If the song has the same artist as the last song, it causes a repeating artist and needs to be shifted.
		table.insert(songsToShift, i)

		shiftCount = shiftCount + 1
	end

	local currentIndex = 0

	for i = 1, shiftCount do
		local index = songsToShift[i] - currentIndex
		local object = self.Playlist[index]

		-- Remove the song from the playlist.
		object = table.remove(self.Playlist, index)

		-- Insert the song at the end of the playlist.
		table.insert(self.Playlist, object)

		-- Add one to the current index.
		-- Shifting a song to the end means we need to subtract one from every future index.
		currentIndex = currentIndex + 1
	end
end

function StationClass:RefreshPlaylist(isInitial)
	-- Remove the finished song from our playlist.
	local lastSong = table.remove(self.Playlist, 1)

	self.LastSong = lastSong

	local shouldRefresh = table.IsEmpty(self.Playlist)

	if SERVER and shouldRefresh then
		-- Generate a new playlist since the current one is empty (finished).
		self:GeneratePlaylist()

		-- If playlist randomization is enabled, sort the playlist to reduce artist repetition.
		if self.Randomize then
			self:SortPlaylist(lastSong)
		end
	end

	local curSong = self:GetCurrentSong()

	if curSong and !curSong:ShouldPlay() then
		self:RefreshPlaylist()

		return
	end

	self:UpdateTime(shouldRefresh)

	-- Only network the playlist if it's a new one (refreshed), and it's not the initial one generated via core class' initialize.
	if SERVER and (shouldRefresh and !isInitial) then
		self:DoNetwork()
	end

	-- If our playlist was just refreshed, its empty on CLIENT and nothing will happen if we try to update our channels.
	-- Refer to NetClass:ReceivePlaylist for the solution.
	if CLIENT and !isInitial and !shouldRefresh then
		-- TODO: Check if net_fakelag affects timer desync
		self:UpdateRadioChannels()
	end
end

function StationClass:UpdateTime(didRefresh)
	local curTime = CurTime()

	if didRefresh then
		-- This stores the time the current playlist started at.
		self.StartTime = curTime
	end

	-- Whenever a new playlist is generated, the song start time is networked too.
	if CLIENT and didRefresh then
		return
	end

	local newSong = self.Playlist[1]

	if !newSong then
		return
	end

	newSong:SetStartTime(curTime)

	self:SetNextPlaylistRefresh(newSong:GetEndTime())
end

local function StopStatic(ent)
	if !IsValid(ent) then
		return
	end

	local staticSnd = ent.StaticSound

	if staticSnd then
		staticSnd:FadeOut(0.5)

		timer.Simple(0.5, function()
			if staticSnd then
				staticSnd:Stop()
			end

			ent.StaticSound = nil
		end)
	end
end

local enabled = GetConVar("cl_cradio")

function StationClass:RadioChannel(ent, enable3D, doFade, playStatic, callback)
	if SERVER or !IsValid(ent) or !enabled:GetBool() then
		return
	end

	-- Enforce station validity.
	if !self:IsValid() then
		return
	end

	local curSong = self:GetCurrentSong()

	-- Song must not be nil and be valid (have both name and url).
	if !curSong or !curSong:IsValid() then
		return
	end

	local curSongTime = curSong:GetCurTime()

	-- Only create the sound if we don't already have one playing.
	if playStatic and !ent.StaticSound then
		local staticSnd = CreateSound(ent, "cradio/radio_change_static_looped.wav")
		staticSnd:SetSoundLevel(80)
		staticSnd:Play()

		ent.StaticSound = staticSnd
	end

	local playSong, path = curSong:GetPlayMethod()

	-- We have no audio file and there is no valid URL provided, so halt and print an error.
	if !playSong then
		ErrorNoHalt(self, " - No file present or valid URL for ", tostring(curSong), ".")

		StopStatic(ent)

		return
	end

	local channelFlags = curSong:GetChannelFlags(enable3D)

	playSong(path, channelFlags, function(channel, errorID, errorName)
		self:ProcessRadioChannel(ent, channel, curSongTime > 0.5, doFade, callback)
	end)
end

local defaultVol = GetConVar("cl_cradio_volume")

function StationClass:ProcessRadioChannel(ent, channel, shouldBuffer, doFade, callback)
	if !IsValid(channel) then
		ErrorNoHalt(self, " - Channel for ", tostring(self.Playist[1]), " invalid before processing. Ensure file/URL is accessible.")

		StopStatic(ent)

		return
	end

	if !IsValid(ent) then
		channel:Stop()

		return
	end

	local is3D = channel:Is3D()

	if is3D then
		channel:Set3DEnabled(true)
	end

	if shouldBuffer then
		channel:DoBuffer(ent, self, doFade)
	else
		channel:Play()

		if doFade then
			channel:DoFade(0.5, 0, defaultVol:GetFloat())
		else
			channel:SetVolume(defaultVol:GetFloat())
		end

		StopStatic(ent)
	end

	-- Cache the station object for comparison. 
	channel:SetStation(self)

	ent:SetRadioChannel(channel)

	self.RadioChannels[ent] = channel

	if isfunction(callback) then
		callback(ent, channel)
	end

	-- PREBUFFER:
	if ent.CRadio or ent != CLib.GetVehicle() then
		return
	end

	self:QueuePreBuffer(self.Playlist[1], self.Playlist[2], is3D)
end

function StationClass:UpdateRadioChannels()
	local curSong = self.Playlist[1]

	if SERVER or !curSong then
		return
	end

	local radioChannels = self.RadioChannels

	-- Even on an empty table, pairs is still called. This prevents that.
	if table.IsEmpty(radioChannels) then
		return
	end

	local ourVehicle = CLib.GetVehicle()
	local updatedEnts = {}

	for ent, channel in pairs(radioChannels) do
		local alreadyUpdated = updatedEnts[ent]

		if alreadyUpdated then
			continue
		end

		-- When this happens, it's because the audio channel was stopped without updating the table.
		if !channel or !channel:IsValid() then
			-- Since the channel is invalid, remove the key (ent) from the table.
			radioChannels[ent] = nil

			continue
		end

		local is3D = channel:Is3D()

	    ent:StopRadioChannel(false, false, true)

        -- PREBUFFER:
        local cGUI = CRadio:GetGUI()
        local preBufferChannel = ent.acPreBuffer

		if preBufferChannel and preBufferChannel:IsValid() then
			ent:SetRadioChannel(preBufferChannel)
			preBufferChannel:Play()

			self.RadioChannels[ent] = preBufferChannel

			-- TODO: set to nil even if not :IsValid()?
			ent.acPreBuffer = nil

			cGUI:DoPlayNotification(curSong, preBufferChannel, ent)
		else
			self:RadioChannel(ent, is3D, false, false, function(nEnt, nChannel)
				cGUI:DoPlayNotification(curSong, nChannel, nEnt)
			end)
		end

		-- PREBUFFER:
		if !ent.CRadio and ent == ourVehicle then
			self:QueuePreBuffer(curSong, self.Playlist[2], is3D)
		end

		-- Mark the entity as already updated so we don't do so again.
		updatedEnts[ent] = true
	end
end

local shouldPreBuffer = GetConVar("cl_cradio_prebuffer")

function StationClass:QueuePreBuffer(curSong, nextSong, enable3D)
	if !enabled:GetBool() or !shouldPreBuffer:GetBool() then
		return
	end

	local preBufferDelay = math.max(curSong:GetTimeLeft() - 3, 1)

	timer.Create("CRadio.PreBuffer", preBufferDelay, 1, function()
		local vehicle = CLib.GetVehicle()

		if !IsValid(vehicle) then
			return
		end

		-- COMMENT:
		-- Song must not be nil and be valid (have both name and url).
		if self != vehicle:GetCurrentStation() or curSong != self.Playlist[1] or !IsValid(nextSong) or !nextSong:IsValid() then
			return
		end

		local playSong, path = nextSong:GetPlayMethod()

		-- We have no audio file and there is no valid URL provided, so halt and print an error.
		if !playSong then
			ErrorNoHalt(self, " - No file present or valid URL for ", nextSong, ".")

			return
		end

		local channelFlags = nextSong:GetChannelFlags(enable3D)

		playSong(path, channelFlags, function(channel, errorID, errorName)
			if !IsValid(channel) then
				return
			end

			if vehicle != CLib.GetVehicle() or !IsValid(vehicle) then
				channel:Stop()

				return
			end

			if channel:Is3D() then
				channel:Set3DEnabled(true)
			end

			channel:SetVolume(defaultVol:GetFloat())

			-- Cache the station object for comparison. 
			channel:SetStation(self)

			-- COMMENT: sanity check :)
			local preBufferChannel = vehicle.acPreBuffer

			if preBufferChannel and preBufferChannel:IsValid() then
				preBufferChannel:Stop()
			end

			vehicle.acPreBuffer = channel
		end)
	end)
end

function StationClass:DoNetwork(externalNet)
	if CLIENT then
		return
	end

	if !externalNet then
		net.Start("CRadio.NetworkPlaylist")
		net.WriteUInt(1, 8)
	end

	local playlist = self:GetPlaylist()
	local songCount = #playlist

	net.WriteUInt(self:GetID(), 8)

	local curSong = self:GetCurrentSong()
	local songEndTime = (curSong and curSong:GetEndTime()) or CurTime()

	net.WriteFloat(songEndTime)
	net.WriteUInt(songCount, 10)

	for i = 1, songCount do
		local song = playlist[i]

		net.WriteUInt(song:GetID(), 16)
	end

	if !externalNet then
		net.Broadcast()
	end

	return playlist
end

function StationClass:IsStation()
	return true
end

function StationClass:IsSong()
	return false
end

function StationClass:IsSubPlaylist()
	return false
end

local greenColor = Color(0, 255, 0)
local blueColor = Color(0, 180, 255)
local orangeColor = Color(255, 200, 30)

function StationClass:PrintInfo()
	MsgC(greenColor, self, color_white, ":\n")

	local count = #self.Playlist
	local length = 0

	for i = 1, count do
		local song = self.Playlist[i]

		MsgC(color_white, "-----------------------\n")

		if i == 1 then
			MsgC(color_white, "Song [",  orangeColor, i, color_white, "]: ", blueColor, song, color_white, " with ", greenColor, color_white, math.abs(CurTime() - self:GetNextPlaylistRefresh()), " seconds left!\n")
		else
			MsgC(color_white, "Song [",  orangeColor, i, color_white, "]: ", blueColor, song, "\n")
			MsgC(color_white, "Time until played: ", greenColor, math.abs(CurTime() - self:GetNextPlaylistRefresh() + length), color_white, " seconds!\n")
		end

		length = length + song:GetLength()

		if i == count then
			MsgC(color_white, "-----------------------\n")
		end
	end
end

function StationClass:DebugTime()
	local song = self.Playlist[1]

	if !IsValid(song) then
		return
	end

	MsgC(color_white, "-----------------------\n")
	MsgC(color_white, "Song / ",  orangeColor, song, color_white, "\n")

	local channelCurTime = 0

	if CLIENT then
		channelCurTime = CLib.GetVehicle():GetRadioChannel():GetTime()
	end

	local timerCurTime = song:GetLength() - timer.TimeLeft(self.TimerName)

	MsgC(color_white, "CurTime:              ", greenColor, math.Round(CurTime(), 4), color_white, " seconds!\n")
	MsgC(color_white, "songCurTime:          ", greenColor, math.Round(song:GetCurTime(), 4), color_white, " seconds!\n")

	if CLIENT then
		MsgC(color_white, "Channel Time:         ", greenColor, math.Round(channelCurTime, 4), color_white, " seconds!\n")
	end

	MsgC(color_white, "timerCurTime:         ", greenColor, math.Round(timerCurTime, 4), color_white, " seconds!\n")

	if CLIENT then
		MsgC(color_white, "Deviation from timer: ", greenColor, math.Round(timerCurTime - channelCurTime, 4), color_white, " seconds!\n")
	end

	MsgC(color_white, "Time until end:       ", greenColor, math.Round(math.abs(CurTime() - self:GetNextPlaylistRefresh()), 4), color_white, " seconds!\n")
	MsgC(color_white, "Song Length (Def):    ", greenColor, math.Round(song:GetLength(), 4), color_white, " seconds!\n")

	if CLIENT then
		MsgC(color_white, "Song Length (Act):    ", greenColor, math.Round(CLib.GetVehicle():GetRadioChannel():GetLength(), 4), color_white, " seconds!\n")
	end

	MsgC(color_white, "-----------------------\n")
end

function StationClass:DebugPreBuffer()
	if SERVER then
		return
	end

	local channel = nil
	local vehicle = CLib.GetVehicle()

	if IsValid(vehicle) then
		channel = vehicle.acPreBuffer
	end

	MsgC(color_white, "-----------------------\n")
	MsgC(color_white, "Timer Exists:           ", greenColor, timer.Exists("CRadio.PreBuffer"), color_white, "!\n")
	MsgC(color_white, "Timer Left:             ", greenColor, math.Round(timer.TimeLeft("CRadio.PreBuffer") or 0, 4), color_white, " seconds!\n")
	MsgC(color_white, "preBufferChannel:       ", greenColor, channel, color_white, "!\n")
	MsgC(color_white, "-----------------------\n")
end

setmetatable(StationClass, {
	__call = function(tbl, ...)
		local newStation = StationClass:New(...)

		if newStation.__constructor then
			newStation:__constructor(...)
		end

		return newStation
	end
})

CRadioStationClass = StationClass