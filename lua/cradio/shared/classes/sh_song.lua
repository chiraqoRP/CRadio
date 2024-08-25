local SongClass = {}
SongClass.__index = SongClass

local songsGenerated = 0

function SongClass:__constructor(name)
	if songsGenerated > 65535 then
		ErrorNoHaltWithStack("[CRadio] | You have hit the song limit!")

		return
	end

	-- Set our name if one is provided.
	self.Name = name
	self.Length = 0

	-- Our ID doesn't need to be cryptographically secure, it's only used for __eq operations.
	self.ID = songsGenerated + 1

	songsGenerated = songsGenerated + 1
end

local formatString = "[Song Object] | %s - %s"
local nullString = "[Song Object] | NULL"

function SongClass:__tostring()
	if !self:IsValid() then
		return nullString
	end

	return string.format(formatString, self.Artist, self.Name)
end

function SongClass:__eq(other)
	-- If either song lacks a name or file/url, they are not equal.
	if !self:IsValid() or !other:IsValid() then
		return false
	end

	return self.ID == other:GetID()
end

--- Checks validity.
-- @return {boolean} whether our song is valid or not
function SongClass:IsValid()
	-- Song must have a valid artist string and name string.
	if !self.ID or !string.IsValid(self.Artist) or !string.IsValid(self.Name) then
		return false
	end

	return (string.IsValid(self.URL) or string.IsValid(self.Filepath)) and self.Parent:IsValid()
end

function SongClass:New(name)
	local newSong = setmetatable({}, self)

	return newSong
end

function SongClass:Remove()
	if self.Parent then
		self.Parent:RemoveSong(self)
	end

	-- TODO: Does this even do what I think it does?
	setmetatable(self, nil)
end

--- Gets our songs name.
-- @return {string} our songs name
function SongClass:GetName()
	return self.Name
end

--- Sets our songs name. This should only be used immediately after creation.
-- @param {string} our songs desired name
function SongClass:SetName(name)
	self.Name = name
end

--- Gets our songs artist.
-- @return {string} our songs artist
function SongClass:GetArtist()
	return self.Artist
end

--- Sets our songs artist. This should only be used immediately after creation.
-- @param {string} our songs desired artist
function SongClass:SetArtist(artist)
	self.Artist = artist
end

--- Gets our songs release.
-- @return {string} our songs release if present, can be nil
function SongClass:GetRelease()
	-- COMMENT
	if !self.Release and !self.Parent then
		return
	end

	-- COMMENT
	if !self.Release and self.Parent and self.Parent:IsSubPlaylist() then
		return self.Parent:GetRelease()
	end

	-- COMMENT
	if self.Release == true then
		return self.Name
	end

	return self.Release
end

--- Sets our songs release. This should only be used immediately after creation.
-- @param {string} our songs desired release
function SongClass:SetRelease(release)
	self.Release = release
end

--- Gets our songs ID.
-- @return {integer} our songs numerical ID
function SongClass:GetID()
	return self.ID
end

--- Gets our songs parent.
-- @return {station/subplaylist} our songs parent, can be a station or a subplaylist.
function SongClass:GetParent()
	return self.Parent
end

--- Sets our songs parent. This should only be used immediately after creation.
-- @param {station/subplaylist} our songs desired parent
function SongClass:SetParent(parent)
	self.Parent = parent

	-- If the parent provided isn't valid, don't add the song to it.
	if !parent or !parent:IsValid() then
		return
	end

	-- Add our song to the parent.
	parent:AddSong(self)
end

--- Gets our songs station. This is a distinct method from SONG:SetParent and has special usage.
-- @return {station} our songs station
function SongClass:GetStation()
	-- If the parent provided isn't valid, don't add the song to it.
	if !self.Parent or !self.Parent:IsValid() then
		return
	end

	local isSubPlaylist = self.Parent:IsSubPlaylist()

	return (isSubPlaylist and self.Parent:GetParent()) or self.Parent
end

--- Gets our songs length.
-- @return {float} our songs length in seconds
function SongClass:GetLength()
	return self.Length
end

--- Sets our songs length. This should only be used immediately after creation.
-- @param {float} our songs desired length in seconds
function SongClass:SetLength(length)
	-- We've already set the song's length, so it must be correct.
	if isnumber(self.Length) and self.Length != 0 then
		return
	end

	self.Length = length
end

--- Gets the time our song started playing. Defaults to CurTime if nil.
-- @return {float} time our song started playing in seconds
function SongClass:GetStartTime()
	return self.StartTime or CurTime()
end

--- Sets the time our song started playing. 
-- @param {float} time our song started playing in seconds
function SongClass:SetStartTime(time)
	if !isnumber(time) then
		return
	end

	self.StartTime = math.max(time, 0)
end

local blueColor = Color(0, 180, 255)
local orangeColor = Color(255, 200, 30)

--- Gets the time our song will end. Based on CurTime if our StartTime var is nil.
-- @return {float} time our song will end in seconds
function SongClass:GetEndTime()
	return (self.StartTime or CurTime()) + self.Length
end

--- Gets the time our songs current timestamp.
-- @return {float} current timestamp, 0 if our StartTime var is nil.
function SongClass:GetCurTime()
	if !self.StartTime then
		return 0
	end

	return CurTime() - self.StartTime
end

--- Gets our songs chance to be inserted into the playlist in STATION:GeneratePlaylist.
-- @return {float} chance to play, 1 if nil.
function SongClass:GetChance()
	return self.Chance or 1
end

--- Sets our songs chance to be inserted into the playlist in STATION:GeneratePlaylist. This should only be used immediately after creation.
-- @param {float} our songs desired chance
function SongClass:SetChance(chance)
	self.Chance = chance
end

--- Gets our songs filepath. Be warned that the filepath can be invalid and should be checked with SONG:GetFileExists.
-- @return {string} the songs filepath
function SongClass:GetFile()
	if !self:IsValid() then
		return
	end

	return self.Filepath
end

--- Sets our songs filepath. This should only be used immediately after creation.
-- @param {string} our songs desired filepath
function SongClass:SetFile(filePath)
	self.Filepath = filePath
end

--- Gets whether the file exists or not based on our set filepath. Checks on first call then caches the result.
-- @return {boolean} whether the file exists or not, always returns false on server.
function SongClass:GetFileExists()
	if SERVER or !self:IsValid() then
		return false
	end

	-- Only check if we have an actual filepath provided.
	if self.FileExists == nil and string.IsValid(self.Filepath) then
		-- Sound files are not automatically precached, so its fine to place them in sounds.
		self.FileExists = file.Exists(self.Filepath, "GAME")
	end

	return self.FileExists or false
end

--- Gets our songs url. Be warned that the url can be invalid and cannot easily be checked without doing http.Fetch.
-- @return {string} the songs url
function SongClass:GetURL()
	return self.URL
end

--- Sets our songs url. This should only be used immediately after creation.
-- @param {string} our songs desired url
function SongClass:SetURL(url)
	self.URL = url
end

--- Gets our songs current radio channel.
-- @return {IGModAudioChannel} our songs current radio channel, can be NULL depending on channel status
function SongClass:GetRadioChannel()
	return self.RadioChannel
end

--- Sets our songs current radio channel.
-- @param {IGModAudioChannel} our songs current radio channel
function SongClass:SetRadioChannel(acChannel)
	self.RadioChannel = acChannel
end

--- Sets our songs cover path. This should only be used immediately after creation.
-- @param {string} our songs desired cover path
function SongClass:GetCover()
	return self.Cover
end

--- Gets our songs cover path.
-- @return {string} our songs cover path, this can be nil and should always be validated
function SongClass:SetCover(coverPath)
	self.Cover = coverPath
end

--- Gets whether we're a CRadioStationClass object or not. This method is also present in CRadioStationClass and CRadioSubPlaylistClass.
-- @return {boolean} returns false
function SongClass:IsStation()
	return false
end

--- Gets whether we're a CRadioSongClass object or not. This method is also present in CRadioStationClass and CRadioSubPlaylistClass.
-- @return {boolean} returns true
function SongClass:IsSong()
	return true
end

--- Gets whether we're a CRadioSubPlaylistClass object or not. This method is also present in CRadioStationClass and CRadioSubPlaylistClass.
-- @return {boolean} returns false
function SongClass:IsSubPlaylist()
	return false
end

--- Dictates insertion into the playlist on STATION:GeneratePlaylist. This is meant to be overriden as a custom method.
-- @return {boolean} true if our song should be inserted, false otherwise. returns true by default
function SongClass:ShouldPlay()
	return true
end

setmetatable(SongClass, {
	__call = function(tbl, ...)
		local newSong = SongClass:New(...)

        if newSong.__constructor then
            newSong:__constructor(...)
        end

		return newSong
	end
})

CRadioSongClass = SongClass