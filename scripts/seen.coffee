
module.exports = (bot) ->

  bot.on 'user:join', (r) ->
    
    redis.lrange("irc:#{r.nick}:pass", 0 , -1).then (msg)->
      logger.log msg
      if msg
        if msg.length > 1
          r.privmsg "Živjo #{r.nick}, par sporočilc imam za tebe :)"

        for m in msg
          r.privmsg m
        redis.del("irc:#{r.nick}:pass")

  bot.on 'user:talk', (r) ->
    redis.set("irc:#{r.nick}:timestamp", moment().unix())
    redis.set("irc:#{r.nick}:msg", r.text)
  
  bot.regexp /^.videl (.+)/,
    ".videl <nick> -- Kdaj je bil uporabnik zadnjič na kanalu, sporočilo",
    (match, r) ->
      usr = match[1]
      logger.log "iščem uporabnika #{usr}"
      
      if usr is r.nick
        return r.reply "#{r.nick}: Kdaj si se zadnjič pogledal/a v ogledalo?"
      
      redis.get("irc:#{usr}:timestamp").then (timestamp)->

        if timestamp
          cas = moment.unix(timestamp).fromNow()
          logger.log "zadnjič #{timestamp} - > #{cas}"
          redis.get("irc:#{usr}:msg").then (msg)->
            logger.log msg
            r.reply "#{r.nick}: #{usr} je bil zadnjič prisoten/na #{cas} z sporočilom: #{msg}"
        else
          r.reply "#{r.nick}: O čemu ti to?"

  bot.regexp /^\.sporoči (.*)/,
    ".sporoči <nick> <sporočilo> -- Pošlji sporočilo uporabniku, če ni prisoten",
    (match, r) ->
      usr = r.text.replace(".sporoči ", "").split(" ")[0]
      logger.log usr
      msg = r.text.slice(r.text.indexOf(usr)+usr.length+1, r.text.length)
      
      if usr is r.nick
        return r.privmsg "#{r.nick}: Dobro, ne moreš sam/a sebi pošiljat sporočil no!"

      redis.llen("irc:#{usr}:pass").then (count)->
        if count > 5
          r.privmsg "INBOX FULL!"
        else
          msg = "#{r.nick}: #{msg} @#{moment().toString()}"
          redis.rpush("irc:#{usr}:pass", msg)
          r.privmsg "Shranjeno! > #{msg} za #{usr}"
