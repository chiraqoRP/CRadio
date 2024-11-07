---------------------------------
-- Station
---------------------------------
local station = CRadio:Station("My Station", {
    Icon = "cradio/stations/my_station.png"
})

---------------------------------
-- Songs
---------------------------------
CRadio:Song("Cool Song 1", {
    Artist = "Cool Artist 1",
    Release = "Cool Release 1",
    Length = 485.35,
    URL = "https://coolfile.host/cool_song_1.mp3",
    Cover = "cradio/covers/cool_release_1.png",
    Parent = station
})