local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Logger = require(ReplicatedStorage.Shared.Modules.ClientLogger)

local MusicService = {}
MusicService.__index = MusicService

-- Music configuration
local MUSIC_VOLUME = 0.3 -- 30% volume for background music
local FADE_TIME = 2 -- 2 seconds fade between tracks

function MusicService.new()
    local self = setmetatable({}, MusicService)
    self._connections = {}
    self._musicTracks = {}
    self._currentSound = nil
    self._currentTrackIndex = 0
    self._isPlaying = false
    self._musicFolder = nil
    self:_initialize()
    return self
end

function MusicService:_initialize()
    Logger:Info("MusicService initializing...")
    
    self:_loadMusicTracks()
    self:_startPlayback()
    
    Logger:Info("✓ MusicService initialized")
end

function MusicService:_loadMusicTracks()
    -- Find the music folder
    local audioFolder = ReplicatedStorage:FindFirstChild("AUDIO")
    if not audioFolder then
        Logger:Error("AUDIO folder not found in ReplicatedStorage")
        return
    end
    
    self._musicFolder = audioFolder:FindFirstChild("MUSIC")
    if not self._musicFolder then
        Logger:Error("MUSIC folder not found in AUDIO folder")
        return
    end
    
    -- Load all sound files from the music folder
    local trackCount = 0
    for _, child in pairs(self._musicFolder:GetChildren()) do
        if child:IsA("Sound") then
            table.insert(self._musicTracks, child)
            trackCount = trackCount + 1
            Logger:Debug("Found music track: " .. child.Name)
        end
    end
    
    if trackCount == 0 then
        Logger:Warn("No Sound objects found in MUSIC folder")
        return
    end
    
    Logger:Info(string.format("✓ Loaded %d music tracks", trackCount))
    
    -- Setup all tracks
    for _, track in pairs(self._musicTracks) do
        track.Volume = MUSIC_VOLUME
        track.Looped = false -- We'll handle looping manually for random playback
        track.Parent = SoundService -- Move to SoundService for better audio management
    end
end

function MusicService:_startPlayback()
    if #self._musicTracks == 0 then
        Logger:Warn("No music tracks available for playback")
        return
    end
    
    -- Start with a random track
    self:_playNextTrack()
    
    Logger:Info("✓ Music playback started")
end

function MusicService:_playNextTrack()
    if #self._musicTracks == 0 then
        return
    end
    
    -- Stop current track if playing
    if self._currentSound then
        self:_fadeOutCurrentTrack()
    end
    
    -- Select a random track (make sure it's different from current if we have more than 1 track)
    local nextIndex
    if #self._musicTracks > 1 then
        repeat
            nextIndex = math.random(1, #self._musicTracks)
        until nextIndex ~= self._currentTrackIndex
    else
        nextIndex = 1
    end
    
    self._currentTrackIndex = nextIndex
    local nextTrack = self._musicTracks[nextIndex]
    
    if not nextTrack then
        Logger:Error("Selected music track is nil")
        return
    end
    
    self._currentSound = nextTrack
    
    -- Connect to track ended event
    local endedConnection
    endedConnection = nextTrack.Ended:Connect(function()
        Logger:Debug("Music track ended: " .. nextTrack.Name)
        if endedConnection then
            endedConnection:Disconnect()
        end
        -- Play next track after a brief pause
        task.wait(1)
        self:_playNextTrack()
    end)
    
    -- Store connection for cleanup
    self._connections[nextTrack.Name] = endedConnection
    
    -- Fade in and play the track
    self:_fadeInTrack(nextTrack)
    
    Logger:Info("Now playing: " .. nextTrack.Name)
end

function MusicService:_fadeInTrack(track)
    if not track then return end
    
    -- Start at 0 volume
    track.Volume = 0
    track:Play()
    self._isPlaying = true
    
    -- Fade in over FADE_TIME seconds
    local targetVolume = MUSIC_VOLUME
    local fadeSteps = 20
    local volumeStep = targetVolume / fadeSteps
    local timeStep = FADE_TIME / fadeSteps
    
    task.spawn(function()
        for i = 1, fadeSteps do
            if track.IsPlaying then
                track.Volume = math.min(volumeStep * i, targetVolume)
                task.wait(timeStep)
            else
                break
            end
        end
        track.Volume = targetVolume
    end)
end

function MusicService:_fadeOutCurrentTrack()
    if not self._currentSound or not self._currentSound.IsPlaying then
        return
    end
    
    local track = self._currentSound
    local currentVolume = track.Volume
    local fadeSteps = 10
    local volumeStep = currentVolume / fadeSteps
    local timeStep = (FADE_TIME * 0.5) / fadeSteps -- Fade out faster than fade in
    
    task.spawn(function()
        for i = fadeSteps, 1, -1 do
            if track.IsPlaying then
                track.Volume = volumeStep * (i - 1)
                task.wait(timeStep)
            else
                break
            end
        end
        track:Stop()
        track.Volume = MUSIC_VOLUME -- Reset volume for next time
    end)
end

function MusicService:SetVolume(volume)
    MUSIC_VOLUME = math.clamp(volume, 0, 1)
    
    if self._currentSound and self._currentSound.IsPlaying then
        self._currentSound.Volume = MUSIC_VOLUME
    end
    
    -- Update all tracks' default volume
    for _, track in pairs(self._musicTracks) do
        if not track.IsPlaying then
            track.Volume = MUSIC_VOLUME
        end
    end
    
    Logger:Info(string.format("Music volume set to %.1f%%", MUSIC_VOLUME * 100))
end

function MusicService:GetCurrentTrack()
    if self._currentSound then
        return self._currentSound.Name
    end
    return "None"
end

function MusicService:GetTrackCount()
    return #self._musicTracks
end

function MusicService:IsPlaying()
    return self._isPlaying and self._currentSound and self._currentSound.IsPlaying
end

function MusicService:SkipTrack()
    if self._currentSound and self._currentSound.IsPlaying then
        Logger:Info("Skipping current track: " .. self._currentSound.Name)
        self._currentSound:Stop()
        -- The Ended event will trigger and play the next track
    end
end

function MusicService:PauseMusic()
    if self._currentSound and self._currentSound.IsPlaying then
        self._currentSound:Pause()
        self._isPlaying = false
        Logger:Info("Music paused")
    end
end

function MusicService:ResumeMusic()
    if self._currentSound and not self._currentSound.IsPlaying then
        self._currentSound:Resume()
        self._isPlaying = true
        Logger:Info("Music resumed")
    end
end

function MusicService:StopMusic()
    if self._currentSound then
        self:_fadeOutCurrentTrack()
        self._isPlaying = false
        Logger:Info("Music stopped")
    end
end

function MusicService:Cleanup()
    Logger:Info("MusicService shutting down...")
    
    -- Stop current track
    if self._currentSound then
        self._currentSound:Stop()
    end
    
    -- Disconnect all connections
    for _, connection in pairs(self._connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    
    self._connections = {}
    self._musicTracks = {}
    self._currentSound = nil
    
    Logger:Info("✓ MusicService shutdown complete")
end

return MusicService