---------------------------------
-- Station
---------------------------------
local station = CRadio:Station("My Station")
station:SetIcon("cradio/stations/my_station.png")

---------------------------------
-- Songs
---------------------------------
local song = CRadio:Song("Cool Song 1")
song:SetArtist("Cool Artist 1")
song:SetRelease("Cool Release 1")
song:SetLength(485.35)
song:SetURL("https://coolfile.host/cool_song_1.mp3")
song:SetCover("cradio/covers/cool_release_1.png")
song:SetParent(station)

song = CRadio:Song("Cool Song 2")
song:SetArtist("Cool Artist 2")
song:SetRelease("Cool Release 2")
song:SetLength(469.24)
song:SetURL("https://coolfile.host/cool_song_2.mp3")
song:SetCover("cradio/covers/cool_release_2.png")
song:SetParent(station)