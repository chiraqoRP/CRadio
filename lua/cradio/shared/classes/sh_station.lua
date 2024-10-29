local StationClass = {}
StationClass.__index = StationClass

local stationsGenerated = 0

function StationClass:__constructor(name)
	if stationsGenerated > 65535 then
		ErrorNoHaltWithStack("[CRadio] | You have hit the station limit!")

		return
	end

	-- Set our name if one is provided.
	self:SetName(name)

	-- Playlist randomization is enabled by default.
	self.ShouldRandomize = true

	-- COMMENT
	self.Songs = {}

	-- COMMENT
	self.SubPlaylists = {}

	-- COMMENT
	self.Playlist = {}

	-- COMMENT
	self.SongCount = 0

	-- Players that are listening to this station.
	self.Listeners = {}

	-- Stores all of the client's radio channels.
	if CLIENT then
		self.RadioChannels = {}
	end

	stationsGenerated = stationsGenerated + 1
end

local formatString = "[Station Object] | %s"
local nullString = "[Station Object] | NULL"

function StationClass:__tostring()
	if !self:IsValid() then return nullString end

	return string.format(formatString, self.Name)
end

function StationClass:__eq(other)
	-- If either station lacks a name, they are not equal.
	if !self:IsValid() or !other:IsValid() then return false end

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

	table.RemoveByValue(seqStations, self)

	-- TODO: Does this even do what I think it does?
	setmetatable(self, nil)
end

function StationClass:GetName()
	return self.Name
end

function StationClass:GetSanitizedName()
	return self.SanitizedName
end

local timerFormat = "CRadio_Playlist-%s"
local dangerousPattern = '[.*"/\\<>:|?]'
local emptyString = ""

function StationClass:SetName(name)
	-- Set our name if one is provided.
	self.Name = name

	-- Recreate our timer name.
	self.TimerName = string.format(timerFormat, name)

	-- Create and cache a sanitized string of our name to use for folder operations.
	self.SanitizedName, _ = string.gsub(self.Name, dangerousPattern, emptyString)

	-- Create our station's folder used for caching song files.
	-- file.CreateDir(string.format(folderFormat, self.SanitizedName))
end

local defaultIcon = Material("cradio/icons/default.png", "mips")

function StationClass:GetIcon()
	if SERVER then return end

	return self.Icon or defaultIcon
end

function StationClass:SetIcon(icon)
	if SERVER then return end

	self.Icon = icon
end

function StationClass:GetRandomizeEnabled()
	return self.ShouldRandomize
end

function StationClass:SetRandomizeEnabled(bool)
	self.ShouldRandomize = bool
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

function StationClass:SetNextPlaylistRefresh(delay)
	-- print("SetNextPlaylistRefresh timer set to ", delay, " for station ", self.Name, "!")

	self.NextPlaylistRefresh = CurTime() + delay

	timer.Create(self.TimerName, delay, 1, function()
		-- print("SetNextPlaylistRefresh timer called at ", CurTime(), ", actually supposed to be called at ", self.NextPlaylistRefresh)

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

local function InsertSubPlaylist(playlist, subplaylist, index)
	local songs = subplaylist:GetSongs()
	local shouldRandomize = subplaylist:GetRandomizeEnabled()
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

	if self.ShouldRandomize then
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

function StationClass:SortPlaylist(last)
	if CLIENT or !self.ShouldRandomize then
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
		local leftSong = (i == 1 and last) or self.Playlist[i - 1]

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

	-- print(self.Name, " playlist refreshed at ", CurTime(), ". ", lastSong and lastSong:GetName() or "nothing", " removed!")

	self.LastSong = lastSong

	local shouldRefresh = table.IsEmpty(self.Playlist)

	if SERVER and shouldRefresh then
		-- Generate a new playlist since the current one is empty (finished).
		self:GeneratePlaylist()

		-- If playlist randomization is enabled, sort the playlist to reduce artist repetition.
		if self.ShouldRandomize then
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

	-- COMMENT
	if CLIENT and !isInitial and !shouldRefresh then
		-- TODO: Check if net_fakelag affects timer desync
		self:UpdateRadioChannels()
	end
end

function StationClass:UpdateTime(didRefresh)
	local curTime = CurTime()

	-- print("StationClass:UpdateTime called at ", curTime, "!")

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

	local songEndTime = newSong:GetEndTime()

	-- print("StationClass:UpdateTime | NextPlaylistRefresh set to ", curTime + length, " at ", CurTime())

	self:SetNextPlaylistRefresh(newSong:GetEndTime() - CurTime())
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

local m3DFlags = "3d mono %s"
local urlFlags = "noplay noblock"
local fileFlags = "noplay"
local playFuncs = {}

function StationClass:RadioChannel(ent, enable3D, doFade, playStatic, callback)
	if SERVER then
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
	local url = curSong:GetURL()
	local fileValid, audioFile = curSong:GetFileExists(), curSong:GetFile()

	-- print("ENTITY:RadioChannel | curSongTime: ", curSongTime)
	-- MsgC("Do we already have a static sound active?", Color(0, 255, 0), self.StaticSound, "\n")

	-- COMMENT
	if playStatic and !ent.StaticSound then
		local staticSnd = CreateSound(ent, "cradio/radio_change_static_looped.wav")
		staticSnd:SetSoundLevel(80)
		staticSnd:Play()

		-- print("ENTITY:RadioChannel | staticSnd: ", staticSnd)

		ent.StaticSound = staticSnd
	end

	-- COMMENT
	local urlValid = string.Left(url, 4) == "http"

	-- If the song's CurTime is below a reasonable margin (0-1.5 seconds), do not use noblock.
	-- Doing this saves bandwidth and some performance (no need for a buffer callback).
	local channelFlags = urlValid and curSongTime > 1.5 and urlFlags or fileFlags

	-- COMMENT
	if enable3D then
		channelFlags = string.format(m3DFlags, channelFlags)
	end

	-- MsgC("ENTITY:RadioChannel | channelFlags: ", Color(0, 255, 0), channelFlags, "\n")
	-- MsgC("ENTITY:RadioChannel | doFade: ", Color(0, 255, 0), doFade, "\n")

	-- COMMENT
	local playSong = audioFile and sound.PlayFile or (urlValid and sound.PlayURL)

	if playSong then
		playSong(audioFile or url, channelFlags, function(channel, errorID, errorName)
			self:ProcessRadioChannel(ent, channel, curSongTime, doFade, callback)
		end)
	-- We have no audio file and there is no valid URL provided, so halt.
	else
		StopStatic(ent)

		return
	end
end

local shouldNotification = GetConVar("cl_cradio_notification")

function StationClass:ProcessRadioChannel(ent, channel, time, doFade, callback)
	if !IsValid(channel) then
		StopStatic(ent)

		return
	end

	if !IsValid(ent) then
		channel:Stop()

		return
	end

	if channel:Is3D() then
		channel:Set3DEnabled(true)
	end

	-- print("ProcessChannel | Buffering?: ", time > 2)

	if time > 1.5 then
		channel:DoBuffer(ent, self, time, doFade)
	else
		channel:Play()

		if doFade then
			channel:DoFade(0.5, 0, 1.0)
		end
	end

	-- Cache the station object for comparison. 
	channel:SetStation(self)

	-- COMMENT
	if !ent.IsCRadioEnt and shouldNotification:GetBool() then
		local cGUI = CRadio:GetGUI()

		-- COMMENT
		cGUI:DoPlayNotification(self:GetCurrentSong(), channel)
	end

	-- COMMENT
	ent:SetRadioChannel(channel)

	-- COMMENT
	self.RadioChannels[ent] = channel

	if isfunction(callback) then
		callback(ent, channel)
	end
end

function StationClass:UpdateRadioChannels()
	if SERVER then
		return
	end

	local radioChannels = self.RadioChannels

	-- Even on an empty table, pairs is still called. This prevents that.
	if table.IsEmpty(radioChannels) then
		return
	end

	local cacheCheck = radioChannels[LocalPlayer():GetVehicle()]

	if cacheCheck and cacheCheck:IsValid() then
		MsgC("How much time was left on song for station [", Color(200, 0, 0), self.Name, color_white, "]: ", Color(0, 255, 0), cacheCheck:GetLength() - cacheCheck:GetTime(), color_white, " seconds!")
	end

	local updatedEnts = {}

	for ent, channel in pairs(radioChannels) do
		-- print("StationClass:UpdateRadioChannels | ent/channel: ", ent, channel)
		-- print("StationClass:UpdateRadioChannels | alreadyUpdated: ", updatedEnts[ent])

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

	    ent:StopRadioChannel()

        self:RadioChannel(ent, is3D)

		-- COMMENT:
		updatedEnts[ent] = true
	end
end

function StationClass:DoNetwork(externalNet)
	if CLIENT then
		return
	end

	-- COMMENT
	if !externalNet then
		net.Start("CRadio.NetworkPlaylist")
		net.WriteUInt(1, 8)
	end

	local playlist = self:GetPlaylist()
	local songCount = #playlist

	net.WriteString(self:GetName())

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

	-- COMMENT
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