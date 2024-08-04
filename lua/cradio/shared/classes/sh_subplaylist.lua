local SubPlaylistClass = {}
SubPlaylistClass.__index = SubPlaylistClass

function SubPlaylistClass:__constructor(name)
	-- Set our name if one is provided.
	self.Name = name

	-- Sub-playlist randomization is false by default.
	self.ShouldRandomize = false

	self.Songs = {}
end

local formatString = "[SubPlaylist Object] %s"
local nullString = "[SubPlaylist Object] NULL"

function SubPlaylistClass:__tostring()
	if !self:IsValid() then
		return nullString
	end

	return string.format(formatString, self.Name)
end

function SubPlaylistClass:__eq(other)
	-- If either sub-playlist lacks a name, they are not equal.
	if !self:IsValid() or !other:IsValid() then
		return false
	end

	return self.Name == other:GetName()
end

function SubPlaylistClass:IsValid()
	return string.IsValid(self.Name)
end

function SubPlaylistClass:New()
	local newSubPlaylist = setmetatable({}, self)

	return newSubPlaylist
end

function SubPlaylistClass:Remove()
	if self.Parent then
		self.Parent:RemoveSubPlaylist(self)
	end

	-- TODO: Does this even do what I think it does?
	setmetatable(self, nil)
end

function SubPlaylistClass:GetName()
	return self.Name
end

function SubPlaylistClass:SetName(name)
	self.Name = name
end

function SubPlaylistClass:GetParent()
	return self.Parent
end

function SubPlaylistClass:SetParent(parent)
	self.Parent = parent

	-- If the parent provided isn't valid, don't add the sub-playlist to it.
	if !parent or !parent:IsValid() then
		return
	end

	-- Cache the sub-playlists position so it isn't always appended to the end of the main playlist.
	self.Position = #parent:GetSongs() + #parent:GetSubPlaylists()

	-- Add our sub-playlist to the parent.
	parent:AddSubPlaylist(self)
end

function SubPlaylistClass:GetRelease()
	return self.Release
end

function SubPlaylistClass:SetRelease(release)
	self.Release = release
end

function SubPlaylistClass:GetChance()
	return self.Chance or 1
end

function SubPlaylistClass:SetChance(chance)
	self.Chance = chance
end

function SubPlaylistClass:GetRandomizeEnabled()
	return self.ShouldRandomize
end

function SubPlaylistClass:SetRandomizeEnabled(bool)
	self.ShouldRandomize = bool
end

function SubPlaylistClass:GetSongs()
	return self.Songs
end

function SubPlaylistClass:AddSong(song)
	if !song or !song:IsValid() then
		return
	end

	table.insert(self.Songs, song)
end

function SubPlaylistClass:RemoveSong(song)
	if !song or !song:IsValid() then
		return
	end

	-- Remove the song from our songs table.
	table.RemoveByValue(self.Songs, song)
end

function SubPlaylistClass:IsStation()
	return false
end

function SubPlaylistClass:IsSong()
	return false
end

function SubPlaylistClass:IsSubPlaylist()
	return true
end

setmetatable(SubPlaylistClass, {
	__call = function(tbl, ...)
		local newSubPlaylist = SubPlaylistClass:New(...)

        if newSubPlaylist.__constructor then
            newSubPlaylist:__constructor(...)
        end

		return newSubPlaylist
	end
})

CRadioSubPlaylistClass = SubPlaylistClass