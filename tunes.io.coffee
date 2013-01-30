XMLStream = require 'xml-stream'
winston = require 'winston'
async = require 'async'
http = require 'http'
mpd = require 'mpd-ng'
fs = require 'fs'


logger = new winston.Logger
    transports: [
        new winston.transports.Console
    ]
    exceptionHandlers: [
        new winston.transports.Console json: true
        new winston.transports.File filename: __dirname + '/exceptions.log'
    ]


fetchPlaylistTask = (task, callback) ->
    logger.info "Fetching playlist", location: task.location

    req = http.request task.location, (res) ->
        unless res.statusCode is 200
            logger.warn "Can't fetch playlist",
                location: task.location
                statusCode: res.statusCode

            res.destroy()
            return callback()

        res.on 'error', (exception) ->
            logger.warn "Error while playlist downloading",
                location: task.location
                exception: exception
            
            callback()

        xml = new XMLStream res
        
        xml.on 'endElement: track', (track) ->
            player.send "add #{track.location}"

        xml.on 'end', ->
            player.send "save #{task.date}"
            player.send "clear"
            callback()

    req.on 'error', (exception) ->
        logger.warn "Can't fetch playlist"
            location: task.location
            exception: exception
        
        callback()

    req.end()


player = mpd.connect
    host: '127.0.0.1'
    port: 6600

player.on 'error', ->
    logger.error "Can't connect to MPD"

player.on 'connect', ->
    currentDate = new Date
    tasks = []

    loop
        date = currentDate.toISOString().slice(0, 10)
        location = "http://tunes.io/xspf/#{date}/"

        tasks.push
            date: date
            location: location

        currentDate.setDate(currentDate.getDate() - 1)

        if date is '2012-09-07'
            break

    player.send "stop"
    player.send "clear"

    async.mapSeries tasks, fetchPlaylistTask, ->
        # load all tracks in playlist named "tunes-io"
        player.send "load #{task.date}" for task in tasks
        player.send "save tunes-io"

        player.send "shuffle"
        player.send "play"
        player.end()
