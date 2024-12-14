local SongClass = {}
SongClass.__index = SongClass

local songsGenerated = 0

function SongClass:__constructor(name, songStruct)
	if songsGenerated > 262143 then
		ErrorNoHaltWithStack("[CRadio] | You have hit the song limit!")

		return
	end

	-- Set our name if one is provided.
	self.Name = name
	self.Artist = songStruct.Artist
	self.Release = songStruct.Release
	self.Length = songStruct.Length or 0
	self.Gap = songStruct.Gap or 0.5
	self.Chance = songStruct.Chance or 1.0

	-- Without this, some string ops will cause halting errors.
	-- Its the users responsibility to check URL validity anyways.
	self.URL = songStruct.URL or ""

	self.File = songStruct.File
	self.Cover = songStruct.Cover

	-- Our ID doesn't need to be cryptographically secure, it's only used for __eq operations.
	self.ID = songsGenerated + 1

	songsGenerated = songsGenerated + 1

	self:SetParent(songStruct.Parent)

    for key, val in pairs(songStruct) do
		if self[key] != nil then
			continue
		end

		self[key] = val
    end
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

	return (string.IsValid(self.URL) or string.IsValid(self.File)) and self.Parent:IsValid()
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

function SongClass:GetArtist()
	return self.Artist
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
	return self.Length + self.Gap
end

function SongClass:GetBaseLength()
	return self.Length
end

function SongClass:GetGap()
	return self.Gap
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

function SongClass:GetEndTime()
	return (self.StartTime or CurTime()) + self:GetLength()
end

function SongClass:GetCurTime()
	if !self.StartTime then
		return 0
	end

	return CurTime() - self.StartTime
end

function SongClass:GetTimeLeft()
	return math.max(self:GetEndTime() - CurTime(), 0)
end

function SongClass:GetChance()
	return self.Chance
end

function SongClass:GetFile()
	if !self:IsValid() then
		return
	end

	return string.lower(self.File or "")
end

function SongClass:GetFileExists()
	if SERVER or !self:IsValid() then
		return false
	end

	local filePath = self:GetFile()

	-- Only check if we have an actual filepath provided.
	if self.FileExists == nil and string.IsValid(filePath) then
		-- Sound files are not automatically precached, so its fine to place them in sounds.
		self.FileExists = file.Exists(filePath, "GAME")
	end

	return self.FileExists or false
end

function SongClass:GetURL()
	return self.URL
end

local m3DFlags = "3d mono %s"
local urlFlags = "noplay noblock"
local fileFlags = "noplay"

function SongClass:GetChannelFlags(enable3D)
	local curTime = self:GetCurTime()
	local url = self:GetURL()

	-- Checks if our URL is a non-empty string, and if it is a valid URL (ie: https://urlhere.domain).
	local urlValid = string.Left(url, 4) == "http"

	-- If the song's CurTime is below a reasonable margin (0 <--> 0.5 seconds), do not use noblock.
	-- Doing this saves bandwidth and some performance (no need for a buffer callback).
	local channelFlags = urlValid and curTime > 0.5 and urlFlags or fileFlags

	-- 3D only works properly with the mono channel flag.
	if enable3D then
		channelFlags = string.format(m3DFlags, channelFlags)
	end

	return channelFlags
end

function SongClass:GetPlayMethod()
	-- Checks if our URL is a non-empty string, and if it is a valid URL (ie: https://urlhere.domain).
	local urlValid = string.Left(self:GetURL(), 4) == "http"
	local fileValid = self:GetFileExists()

	-- This just returns false if we don't have a URL or (valid) file.
	local method = fileValid and sound.PlayFile or (urlValid and sound.PlayURL) or false
	local path = fileValid and self:GetFile() or self:GetURL()

	return method, path
end

function SongClass:GetCover()
	return self.Cover
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

function SongClass:ShouldNotify()
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