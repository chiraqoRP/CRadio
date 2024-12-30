-- Station lua must be placed in this folder path: */lua/cradio/shared/stations

---------------------------------
-- Station
---------------------------------
local station = CRadio:Station("My Station", {
    -- Optional, only used for the GUI.
    -- A fallback icon will draw if a valid path relative to (garrysmod/materials/) is not present.
    Icon = "cradio/stations/my_station.png",

    -- True or false boolean that controls whether the station's playlist will be randomized on (re)creation.
    -- Defaults to true.
    Randomize = false
})

-- The following sound types are supported:
    -- .ogg (Best choice, ~q6 recommended)
    -- .mp3 (Good alternative, v2 bitrate recommended)
    -- .flac (Not recommended, way too large)

-- All audio files should have ReplayGain applied to them.
-- foobar2000 is the best for this.
-- For linux users, ffmpeg also works with this:
    -- ffmpeg -i in.flac -codec:a libvorbis -qscale:a 6 -af volume=replaygain=track out.ogg
    -- ffmpeg -i in.flac -b:a 128k -af volume=replaygain=track out.mp3

---------------------------------
-- Songs
---------------------------------
local coolSong = CRadio:Song("Cool Song 1", {
    Artist = "Cool Artist 1",

    -- Can be these options:
        -- A regular string.
        -- A 'true' boolean, will use song name instead (useful for self-titled releases!).
        -- Nothing, and will use parents release var instead IF that parent is a sub-playlist.
    Release = "Cool Release 1",

    -- Can be any integer/float, but should be a float with at least two decimal places of precision, like the one below.
    Length = 485.35,

    -- Adds a gap of silence after this song has finished playing (Previous song --> Previous song's gap --> Song --> Current song's gap).
    -- Very similar to how redbook CDs handle gaps.
    -- Defaults to 0.
    Gap = 1.0,

    -- Controls the chance of the song remaining in the playlist once a new one is created.
    -- Ranges from 0.0 --> 1.0.
    -- Defaults to 1.0.
    Chance = 0.33,

    -- String pointing to an audio file in the clients base game folder (garrysmod/).
    -- Even if a valid URL string is present, clients will default to playing from the specified file if it is present.
    -- Avoid capitol letters as file.Find has issues with them on Linux.
    File = "sound/cradio/stations/my_station/cool_song_1.mp3",

    -- Should be a valid link. An error will be thrown if no URL or file is present.
    -- An error will also be thrown if the URL is inaccessible.
    URL = "https://coolfile.host/cool_song_1.mp3",

    -- Optional, only used for 'now playing' notifications.
    -- A fallback cover will draw if a valid path relative to (garrysmod/materials/) is not present.
    Cover = "cradio/covers/cool_release_1.png",

    -- Can be a station or a sub-playlist.
    Parent = station
})

-- ShouldPlay is a function that can be overriden to allow control over when a song plays.
-- This is called when the previous song is removed and is about to be played for clients.
-- It is shared, and as such you must return the same result in both realms (CLIENT/SERVER).
-- Failure to do so WILL result in the playlist desyncing.
function coolSong:ShouldPlay()
    if !StormFox2 then
        return true
    end

    return StormFox2.Time.IsNight()
end

---------------------------------
-- SubPlaylist
---------------------------------
local coolMix = CRadio:SubPlaylist("Cool Mix", {
    -- Optional, only used if a song you insert into your sub-playlist will attempt to inherit its release from this.
    Release = "Cool Release 1",

    -- Controls the chance of this sub-playlist remaining in it's stations playlist once a new one is created.
    -- Ranges from 0.0 --> 1.0.
    -- Defaults to 1.0.
    Chance = 0.33,

    -- True or false boolean that controls whether the sub-playlist's songs will be shuffled on playlist insertion.
    -- Defaults to false.
    Randomize = false
})