class SlackInterfaceRequestHandler
  constructor: (auth, spotify, volume) ->
    @exec = require('child_process').exec
    @auth = auth
    @spotify = spotify
    @volume = volume
    @plugin_handler = require("../../lib/plugin_handler")()

    @endpoints =
      handle:
        post: (request, response) =>
          request.resume()
          request.once "end", =>
            return if !@auth.validate(request, response)

            reply_data = { ok: true }

            # We can store the user who issued the command
            @queuer = request.body['user_name']
            
            muppets = ['spotify:track:3iwC7lNEnW2XefyROIiAtB', 'spotify:track:3sXJTHeaEXEgziOCyI4DYl', 'spotify:track:6eVUH8bqIo2x6sfeeUGkHU', 'spotify:track:6RKbWCytFTB6emlcnrsdpt', 'spotify:track:5Kgjzdpk6INHN7MHVW1CdM', 'spotify:track:0SMobBlnSvGStk8rDfXLgs']

            rules = ['*Herein lie the rules of belonging to the cult of Sasquatch!*', '>First Rule of Sasquatch: Never `skip` a `queue` (from someone who can hear it).', '>Second Rule of Sasquatch: It is _always_ OK to switch from `list` john.', '>Third Rule of Sasquatch: Thursday is for Throwbacks. Deal with it.', '>Fourth Rule of Sasquatch: You `phone` it down, you `phone` it back up.', '>Fifth Rule of Sasquatch: Don\'t be a dick, or someone will get the `CoC` out on you.']

            switch @auth.command.toLowerCase()
              when 'reconnect' then @spotify.connect()
              when 'restart' then process.exit 1
              when 'scrubs' then @spotify.play 'spotify:track:1KGi9sZVMeszgZOWivFpxs', @queuer
              when 'spaceman' then @spotify.play 'spotify:track:2Elq6GxVh8v9QFCF3ca2Xc', @queuer
              when 'uptownfunk' then @spotify.play 'spotify:track:32OlwWuMpZ6b0aN2RZOeMS', @queuer
              when 'hustle' then @spotify.play 'spotify:track:0rBMP6VVGRgwnzZCLpijyl', @queuer
              when 'attak' then @spotify.play 'spotify:track:6XNmtLiveX987arpfhYGrj', @queuer
              when 'muppets' then @spotify.play muppets[Math.floor(Math.random()*muppets.length)], @queuer

              when 'pause'
                @spotify.pause()
                reply_data['text'] = "Paused."

              when 'back'
                @spotify.back()
                reply_data['text'] = "Now playing previous song."

              when 'mute'
                @volume.mute()
                reply_data['text'] = "Muted."

              when 'unmute'
                @volume.mute()
                reply_data['text'] = "Unmuted."

              when 'skip'
                reply_data['text'] = "Skipped *<#{@spotify.state.track.object.link}|#{@spotify.state.track.name}>* by *#{@spotify.state.track.artists}*."
                @spotify.skip()

              when 'critical'
                @exec('~/critical-script', (error, stdout, stderr) -> )

              when 'recover'
                @exec('~/recover-script', (error, stdout, stderr) -> )

              when 'emptyqueue'
                @spotify.emptyQueue()
                reply_data['text'] = "The queue has been emptied :anguished:"
                
              when 'duration'
                duration = @spotify.getDuration()
                reply_data['text'] = "The song ends in " + duration
                
              when 'queue'
                if @auth.args[0]?
                  if @spotify.addtoqueue @auth.args[0], @queuer
                  	reply_data['text'] = "Queued ^.^"
                  else
                    reply_data['text'] = "Invalid track. Jesus. What are you even doing. Give up BAKA ONIICHAN."
                else
                  queueList = @spotify.getQueue()
                  if queueList.length
                    reply_data['text'] = "In the queue we have... \n• " + queueList.join('\n• ')
                  else
                    reply_data['text'] = "There are currently no items in the queue."

              when 'stop'
                @spotify.stop()
                reply_data['text'] = ['HAMMER TIME!', 'Collaborate and LISTEN!', 'Right now, thank you very much, I need somebody with the human touch!', 'In the NAAAAAME of love!', 'Me if you\'ve heard this one before'][Math.floor(Math.random() * 5)]

              when 'play'
                reply_data['text'] = "Please use `queue` instead"

              when 'shuffle'
                @spotify.toggle_shuffle()
                reply_data['text'] = if @spotify.shuffle then "Mixin' it up." else "Playin' it straight."

              when 'vol'
                if @auth.args[0]?
                  if @volume.sticky_volume.status == "none"
                    switch @auth.args[0]
                      when "up" then @volume.up()
                      when "down" then @volume.down()
                      else @volume.set @auth.args[0]
                    reply_data['text'] = "Current Volume: *#{@volume.current_step}*"
                  else reply_data['text'] = "Volume is locked! Please unlock with the correct command."
                else reply_data['text'] = "Current Volume: *#{@volume.current_step}*"

              when 'phone'
                @volume.phone()
                if @volume.sticky_volume.status == "phone"
                    reply_data['text'] = "Shh! Someone's taking a very important business call."
                else if @volume.sticky_volume.status == "none" 
                  reply_data['text'] = "And we're back. Hope you closed that deal!"

              when 'list'
                if @auth.args[0]?
                  random = false
                  switch @auth.args[0]
                    when 'add' then status = @spotify.add_playlist @auth.args[1], @auth.args[2]
                    when 'remove' then status = @spotify.remove_playlist @auth.args[1]
                    when 'rename' then status = @spotify.rename_playlist @auth.args[1], @auth.args[2]
                    when 'random', 'roulette' then random = @spotify.list_random()
                    else status = @spotify.set_playlist @auth.args[0]
                  if random
                    @spotify.set_playlist random
                    reply_data['text'] = 'Now playing list: ' + random
                  else if status
                    reply_data['text'] = ['Ok.', 'Sweet.', 'Chur.', 'Done like dinner.', 'sorted.org.nz (use your mouse!)', 'Coolies.', 'No problem, brah.', 'Affirmative.', 'Gotcha.', 'Aye-aye, captain! :captain:'][Math.floor(Math.random() * 10)]
                  else
                    reply_data['text'] = "Oops, you did it again. Try `help` if you need some."
                else
                  sortObject = (o) ->
                    sorted = {}
                    key = undefined
                    a = []
                    for key of o
                      `key = key`
                      if o.hasOwnProperty(key)
                        a.push key
                    a.sort (a, b) ->
                      a.toLowerCase().localeCompare b.toLowerCase()
                    key = 0
                    while key < a.length
                      sorted[a[key]] = o[a[key]]
                      key++
                    sorted
                  orderedPlaylists = sortObject @spotify.playlists
                  cleanPlaylists = []
                  for key of orderedPlaylists
                    cleanPlaylists.push "<#{@spotify.playlists[key]}|#{key}>"
                  str = 'Currently available playlists:\n' + cleanPlaylists.join ', '
                  reply_data['text'] = str

              when 'status', 'stat'
                shuffleword = if @spotify.shuffle then '' else ' not'
                if @spotify.is_paused()
                  reply_data['text'] = "We are *paused* on a song called *<#{@spotify.state.track.object.link}|#{@spotify.state.track.name}>* by *#{@spotify.state.track.artists}*.\n The playlist is *<#{@spotify.playlists[@spotify.state.playlist.name]}|#{@spotify.state.playlist.name}>*, and we are#{shuffleword} shufflin'. Resume playback with `play`."
                else if !@spotify.is_playing()
                  reply_data['text'] = "Playback is *stopped*. Choose a `list` or single track to `play`!"
                else
                  if @spotify.state.track.object.queuer
                    reply_data['text'] = "This fine selection is *<#{@spotify.state.track.object.link}|#{@spotify.state.track.name}>* by *#{@spotify.state.track.artists}* - brought to you by *#{@spotify.state.track.object.queuer}*. The playlist *<#{@spotify.playlists[@spotify.state.playlist.name]}|#{@spotify.state.playlist.name}>* will resume shortly."
                  else
                    reply_data['text'] = "This banging tune is *<#{@spotify.state.track.object.link}|#{@spotify.state.track.name}>* by *#{@spotify.state.track.artists}*.\nThe playlist is *<#{@spotify.playlists[@spotify.state.playlist.name]}|#{@spotify.state.playlist.name}>*, and we are#{shuffleword} shufflin'."

              when 'help'
                reply_data['text'] = "Noob. Here's how to work it:
                \n\n*Commands*
                \n> `play [Spotify URI/URL]` - Starts/resumes playback if no URI/URL is provided. If a URI/URL is given, immediately switches to the linked track.
                \n> `pause` - Pauses playback at the current time.
                \n> `queue [Spotify URI/URL]` - Add a new track to the queue. Will play before continuing playlist. FIFO Queue.
                \n> `queue` - View the items in the queue
                \n> `stop` - Stops playback and resets to the beginning of the current track.
                \n> `skip` - Skips (or shuffles) to the next track in the playlist.
                \n> `back` - Returns to the previous track in the playlist.
                \n> `shuffle` - Toggles shuffle on or off and resets the tracker.
                \n> `vol [up|down|0..10]` Turns the volume either up/down one notch or directly to a step between `0` (mute) and `10` (full blast). Also goes to `11`.
                \n> `phone` - Temporarily turns the volume down if someone needs to take a call (or puts it back once the call has finished)
                \n> `mute` - Same as `vol 0`.
                \n> `unmute` - Returns volume to pre-mute level.
                \n> `status` - Shows the currently playing song, playlist and whether you're shuffling or not.
                \n> `duration` - Displays the amount of seconds until the current song finishes.
                \n> `coc` - Lay down the law with the Code of Conduct. If you need to get specific, whip out a `rule` by number.
                \n> `help` - Shows a list of commands with a short explanation.
                    \n*Playlists*
                \n> `list add <name> <Spotify URI>` - Adds a list that can later be accessed under <name>.
                \n> `list remove <name>` - Removes the specified list.
                \n> `list rename <old name> <new name>` - Renames the specified list.
                \n> `list random` - Plays a random list.
                \n> `list <name>` - Selects the specified list and starts playback."

              when 'coc'
                reply_data['text'] = rules.join '\n'
                reply_data['icon_emoji'] = ":sascoc:"

              when 'rule'
                if @auth.args[0]?
                  if rules[@auth.args[0]]
                    reply_data['text'] = rules[@auth.args[0]]
                    reply_data['icon_emoji'] = ":sascoc:"
                else reply_data['text'] = "You'll need to be more specific - or check the `CoC` for a full list."

              else
                # Fallback to external plugins.
                status = @plugin_handler.handle(@auth, @spotify, @volume)
                if status?
                  reply_data['text'] = status

            if @volume.sticky_volume.status == "mute" then reply_data['icon_emoji'] = ":sasmute:"
            else if @volume.sticky_volume.status == "phone" then reply_data['icon_emoji'] = ":sasphone:"

            response.serveJSON reply_data
            return
          return



module.exports = (auth, spotify, volume) ->
  handler = new SlackInterfaceRequestHandler(auth, spotify, volume)
  return handler.endpoints
