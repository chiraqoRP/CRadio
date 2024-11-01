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

	-- Without this, some string ops will cause halting errors.
	-- Its the users responsibility to check URL validity anyways.
	self.URL = ""

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

function SongClass:GetName()
	return self.Name
end

function SongClass:SetName(name)
	self.Name = name
end

function SongClass:GetArtist()
	return self.Artist
end

function SongClass:SetArtist(artist)
	self.Artist = artist
end

function SongClass:GetRelease()
	-- If we have no defined release string and no valid parent, return nothing.
	if !self.Release and !self.Parent then
		return
	end

	-- If we have no defined release string but a valid subplaylist parent, redirect to it's GetRelease method.
	if !self.Release and self.Parent and self.Parent:IsSubPlaylist() then
		return self.Parent:GetRelease()
	end

	-- If our release var is a true boolean, it's a self-titled release (ie: single, title track).
	if self.Release == true then
		return self.Name
	end

	return self.Release
end

function SongClass:SetRelease(release)
	self.Release = release
end

function SongClass:GetID()
	return self.ID
end

function SongClass:GetParent()
	return self.Parent
end

function SongClass:SetParent(parent)
	self.Parent = parent

	-- If the parent provided isn't valid, don't add the song to it.
	if !parent or !parent:IsValid() then
		return
	end

	-- Add our song to the parent.
	parent:AddSong(self)
end

function SongClass:GetStation()
	-- If the parent provided isn't valid, don't add the song to it.
	if !self.Parent or !self.Parent:IsValid() then
		return
	end

	local isSubPlaylist = self.Parent:IsSubPlaylist()

	return (isSubPlaylist and self.Parent:GetParent()) or self.Parent
end

function SongClass:GetLength()
	return self.Length
end

function SongClass:SetLength(length)
	-- We've already set the song's length, so it must be correct.
	if isnumber(self.Length) and self.Length != 0 then
		return
	end

	self.Length = length
end

function SongClass:GetStartTime()
	return self.StartTime or CurTime()
end

function SongClass:SetStartTime(time)
	if !isnumber(time) then
		return
	end

	self.StartTime = math.max(time, 0)
end

local blueColor = Color(0, 180, 255)
local orangeColor = Color(255, 200, 30)

function SongClass:GetEndTime()
	return (self.StartTime or CurTime()) + self.Length
end

function SongClass:GetCurTime()
	if !self.StartTime then
		return 0
	end

	return CurTime() - self.StartTime
end

function SongClass:GetChance()
	return self.Chance or 1
end

function SongClass:SetChance(chance)
	self.Chance = chance
end

function SongClass:GetFile()
	if !self:IsValid() then
		return
	end

	return self.Filepath
end

function SongClass:SetFile(filePath)
	self.Filepath = filePath
end

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

function SongClass:GetURL()
	return self.URL
end

function SongClass:SetURL(url)
	self.URL = url
end

function SongClass:GetCover()
	return self.Cover
end

function SongClass:SetCover(coverPath)
	self.Cover = coverPath
end

function SongClass:IsStation()
	return false
end

function SongClass:IsSong()
	return true
end

function SongClass:IsSubPlaylist()
	return false
end

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