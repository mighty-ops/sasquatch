class SpotifyHandler
  constructor: (options) ->
    @spotify = options.spotify
    @config = options.config
    @storage = options.storage
    @storage.initSync()

    @connect_timeout = null
    @connected = false

    # "playing" in this context means actually playing music or being currently paused (but NOT stopped).
    # This is an important distinction regarding the functionality of @spotify.player.resume().
    @playing = false
    @paused = false

    @state = {
      shuffle: false
      track:
        object: null
        index: 0
        name: null
        artists: null
      playlist:
        name: null
        object: null
    }

    @playlists = @storage.getItem('playlists') || {}

    #Tracks songs already shuffled through
    @shuffletracker = @storage.getItem('shuffletracker') || []

    @queue = []

    @spotify.on
      ready: @spotify_connected.bind(@)
      logout: @spotify_disconnected.bind(@)
    @spotify.player.on
      endOfTrack: @skip.bind(@)

    # And off we go
    @connect()


  # Connects to Spotify.
  connect: ->
    @spotify.login @config.username, @config.password, false, false


  # Called after we have successfully connected to Spotify.
  # Clears the connect-timeout and grabs the default Playlist (or resumes playback if another playlist was set).
  spotify_connected: ->
    @connected = true
    clearTimeout @connect_timeout
    @connect_timeout = null

    # If we already have a set playlist (i.e. we were reconnecting), just keep playing.
    if @state.playlist.name?
      @play()
    # If we started fresh, get the one that we used last time
    else if last_playlist = @storage.getItem 'last_playlist'
      @set_playlist last_playlist
    # If that didn't work, try a default
    else if @playlists.sasquatch?
      @set_playlist 'sasquatch'
    return


  # Called after the handler has lost its connection to Spotify.
  # Attempts to re-connect every 2.5s.
  spotify_disconnected: ->
    @connected = false
    @connect_timeout = setTimeout (() => @connect), 2500
    return


  # Called after the current playlist has been updated.
  # Simply replaces the current playlist-instance with the new one and re-bind events.
  # Player-internal state (number of tracks in the playlist, current index, etc.) is updated on @get_next_track().
  update_playlist: (err, playlist, tracks, position) ->
    if @state.playlist.object?
      # Remove event handlers from the old playlist
      @state.playlist.object.off()
    @state.playlist.object = playlist
    @state.playlist.object.on
      tracksAdded: @update_playlist.bind(this)
      tracksRemoved: @update_playlist.bind(this)
    return

  # Pauses playback at the current time. Can be resumed by calling @play().
  pause: ->
    @paused = true
    @spotify.player.pause()
    return


  # Stops playback. This does not just pause, but returns to the start of the current track.
  # This state can not be changed by simply calling @spotify.player.resume(), because reasons.
  # Call @play() to start playing again.
  stop: ->
    @playing = false
    @paused = false
    @spotify.player.stop()
    return

  # Returns how many seconds are left in the current song
  getDuration: ->
    totalSecondsLeft = @state.track.object.duration - @spotify.player.currentSecond
    minutesLeft = Math.floor totalSecondsLeft / 60
    secondsLeft = totalSecondsLeft % 60

    if minutesLeft == 0
      secondsLeft + ' seconds.'
    else
      minutesLeft + ' mins and ' + secondsLeft + ' seconds.'

  # Returns an array of tracks from the queue in the form of '*trackname* by *trackartists*'
  getQueue: ->
    queueList = []
    i = 0
    while i < @queue.length
      trackArtists = []
      track = @queue[i]
      j = 0
      while j < @queue[i].artists.length
        trackArtists.push track.artists[j].name
        j++
      trackArtists = trackArtists.join(', ');
      trackDetails = "*<#{track.link}|#{track.name}>* by *#{trackArtists}*, queued by *#{track.queuer}*."
      queueList.push trackDetails
      i++
    return queueList

  # Remove all items from the current queue
  emptyQueue: ->
    @queue = []
    return

  # Plays the next track in the playlist
  skip: ->
    @play @get_next_track()
    return

  # Goes back a track
  back: ->
    @play @get_last_track()
    return

  # Toggles shuffle on and off. MAGIC!
  toggle_shuffle: ->
    @shuffle = !@shuffle

    #Also resets shuffle tracker
    @shuffletracker = []


  is_playing: ->
    return @playing


  is_paused: ->
    return @paused


  # Either starts the current track (or next one, if none is set) or immediately
  # plays the provided track or link.
  play: (track_or_link=null, queuer) ->
    @paused = false
    # If a track is given, immediately switch to it
    if track_or_link?
      switch typeof track_or_link
        # We got a link from Slack
        when 'string'
          # Links from Slack are encased like this: <spotify:track:1kl0Vn0FO4bbdrTbHw4IaQ>
          # So we remove everything that is neither char, number or a colon.
          new_track = @spotify.createFromLink @_sanitize_link(track_or_link)
          # Track the user who played this Track
          new_track['queuer'] = queuer
          # If the track was somehow invalid, don't do anything
          return if !new_track?
        # We also use this to internally trigger playback of already-loaded tracks
        when 'object'
          new_track = track_or_link
        # Other input is simply disregarded
        else
          return
    # If we are already playing, simply resume
    else if @playing
      return @spotify.player.resume()
    # Last resort: We are currently neither playing not have stopped a track. So we grab the next one.
    else if !new_track
      new_track = @get_next_track()

    # We need to check whether the track has already completely loaded.
    if new_track? && new_track.isLoaded
      @_play_callback new_track
    else if new_track?
      @spotify.waitForLoaded [new_track], (track) =>
        @_play_callback new_track
    return

  # Handles the actual playback once the track object has been loaded from Spotify
  _play_callback: (track) ->
    @state.track.object = track
    @state.track.name = @state.track.object.name
    @state.track.artists = @state.track.object.artists.map((artist) ->
      artist.name
    ).join ", "

    try @spotify.player.play @state.track.object
    catch err then @play @get_next_track()
    finally @playing = true
    return


  # Gets the next track from the playlist.
  get_next_track: ->
    if @queue.length > 0
       # Items to play!
       return @queue.shift()

    if @shuffle
      #Pushes track to shuffletracker array
      @shuffletracker.push @state.track.index
      @storage.setItem 'shuffletracker', @shuffletracker

      #Checks to see if whole playlist has been played, and if so, resets
      if @shuffletracker.length >= @state.playlist.object.numTracks
        @shuffletracker = [@state.track.index]

      #Checks if track index has played already
      while @state.track.index in @shuffletracker
        @state.track.index = Math.floor(Math.random() * @state.playlist.object.numTracks)

    else
      @state.track.index = ++@state.track.index % @state.playlist.object.numTracks
    @state.playlist.object.getTrack(@state.track.index)

  # Gets the previous track from the playlist.
  get_last_track: ->
    if @shuffle

      #Pops last track off the shuffletracker array
      @state.track.index = @shuffletracker.pop()
      @storage.setItem 'shuffletracker', @shuffletracker

    else
      @state.track.index = --@state.track.index % @state.playlist.object.numTracks
    @state.playlist.object.getTrack(@state.track.index)

  # Changes the current playlist and starts playing.
  # Since the playlist might have loaded before we can attach our callback, the actual playlist-functionality
  # is extracted to _set_playlist_callback which we call either directly or delayed once it has loaded.
  set_playlist: (nameOrLink) ->
    playlistLink = false
    playlistName = nameOrLink

    for key of @playlists
      if nameOrLink.toLowerCase() == key.toLowerCase()
        playlistName = key
        playlistLink = @playlists[key]

    # If playlist exists in playlists object, play the link there
    if playlistLink
      @set_playlist_by_link @playlists[playlistName], playlistName
      return true

    # If nameOrLink is a recognised spotify link then play that
    sanitizedLink = @_sanitize_link nameOrLink
    if sanitizedLink.substring(0, 8) == 'spotify:'
      @set_playlist_by_link sanitizedLink
      return true
    return false

  set_playlist_by_link: (link, name) ->
    playlist = @spotify.createFromLink link
    if playlist && playlist.isLoaded
      @_set_playlist_callback name || playlist.name, playlist
    else if playlist
      @spotify.waitForLoaded [playlist], (loadedPlaylist) =>
        @_set_playlist_callback name || playlist.name, loadedPlaylist
    return true


  # The actual handling of the new playlist once it has been loaded.

  _set_playlist_callback: (name, playlist) ->
    @shuffletracker = []
    @state.playlist.name = name
    @state.playlist.link = playlist.link

    # Update our internal state
    @update_playlist null, playlist

    @state.track.index = 0
    @play @state.playlist.object.getTrack(@state.track.index)
    # Also store the name as our last_playlist for the next time we start up
    @storage.setItem 'last_playlist', name
    return

  list_random: ->
    lists = []
    for key of @playlists
      lists.push key
    listToPlay = lists[Math.floor(Math.random()*lists.length)]
    return listToPlay

  # Adds a playlist to the storage and updates our internal list
  add_playlist: (name, spotify_url) ->
    return false if !name? || !spotify_url? || !spotify_url.match(/spotify:user:.*:playlist:[0-9a-zA-Z]+/)
    spotify_url = @_sanitize_link spotify_url.match(/spotify:user:.*:playlist:[0-9a-zA-Z]+/g)[0]
    @playlists[name] = spotify_url
    @storage.setItem 'playlists', @playlists
    return true

  remove_playlist: (name) ->
    return false if !name? || !@playlists[name]?
    delete @playlists[name]
    @storage.setItem 'playlists', @playlists
    return true

  rename_playlist: (old_name, new_name) ->
    return false if !old_name? || !new_name? || !@playlists[old_name]?
    @playlists[new_name] = @playlists[old_name]
    delete @playlists[old_name]
    @storage.setItem 'playlists', @playlists
    return true

  # Adds items to the queue, accepts tracks, playlists, albums and artists
  # @param {string} link - spotify url/uri
  # @param {string} queuer - the name of the person who queued the track
  addtoqueue: (link, queuer) ->
    slink = @_sanitize_link(link)
    if slink.indexOf(':track:') > -1
      return @addTrackToQueue slink, queuer
    if slink.indexOf(':playlist:') > -1
      return @addPlaylistToQueue slink, queuer
    if slink.indexOf(':album:') > -1
      return @addAlbumToQueue slink, queuer
    if slink.indexOf(':artist:') > -1
      return @addArtistToQueue slink, queuer
    return false

  # Adds a single track to the queue
  # @param {string} link - spotify url/uri
  # @param {string} queuer - the name of the person who queued the track
  # @returns {boolean}
  addTrackToQueue: (link, queuer) ->
    strack = @spotify.createFromLink link
    if strack
      @queueLoadedTrack strack, queuer
      return true
    return false

  # Loads a playlist then adds each individual track to the queue
  # @param {string} link - spotify url/uri
  # @param {string} queuer - the name of the person who queued the track
  # @returns {boolean}
  addPlaylistToQueue: (link, queuer) ->
    playlist = @spotify.createFromLink link
    if !playlist
      return false
    if !playlist.isLoaded
      @spotify.waitForLoaded [playlist], (loadedPlaylist) =>
        @addTracksToQueue loadedPlaylist.getTracks(), queuer
      return true
    else
      @addTracksToQueue playlist.getTracks(), queuer
      return true

  # Loads an album then adds each individual track to the queue
  # @param {string} link - spotify url/uri
  # @param {string} queuer - the name of the person who queued the track
  # @returns {boolean}
  addAlbumToQueue: (link, queuer) ->
    album = @spotify.createFromLink link
    if !album
      return false
    album.browse((err, browsedAlbum) =>
      @addTracksToQueue browsedAlbum.tracks, queuer
    )
    return true

  # TODO
  addArtistToQueue: (artist, queuer) ->
    return false

  # Adds an array of tracks to the queue
  # @param {array} tracks - an array of spotify track objects
  # @param {string} queuer - the name of the person who queued the track
  addTracksToQueue: (tracks, queuer) ->
    if tracks[0]
      if tracks[0].isLoaded
        @queueLoadedTrack tracks[0], queuer
        tracks.shift()
        @addTracksToQueue tracks, queuer;
      else
        @spotify.waitForLoaded [tracks[0]], (loadedTrack) =>
          @queueLoadedTrack loadedTrack, queuer
          tracks.shift()
          @addTracksToQueue tracks, queuer;

  # Pushes a spotify track to the queue
  # @param {object} strack - spotify loaded track
  # @param {string} queuer - the name of the person who queued the track
  queueLoadedTrack: (strack, queuer) ->
    strack['queuer'] = queuer
    @queue.push strack
    return true

  # Removes everything that shouldn't be in a link, especially Slack's <> encasing
  _sanitize_link: (link) ->
    link = link.replace(/[\/]/g, ':')
    link = link.replace(/[^0-9a-zA-Z:#\-]/g, '')
    if link.substring(0, 5) == "https"
      link = link.replace('https', 'http')
    if link.substring(0, 4) == "http"
      link = link.replace(link.slice(0, 21), 'spotify')
    return link


# export things
module.exports = (options) ->
  return new SpotifyHandler(options)
