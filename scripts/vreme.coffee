crypto = require 'crypto'

oddaljenost = (lat1, lon1, lat2, lon2) ->
  ## http://mathworld.wolfram.com/SphericalTrigonometry.html
  R = 6371; #v KM
  return Math.acos(Math.sin(lat1)*Math.sin(lat2) + 
                    Math.cos(lat1)*Math.cos(lat2) *
                    Math.cos(lon2-lon1)) * R

yql = (yqlq, cbl) ->
 
  uri = "http://query.yahooapis.com/v1/public/yql?format=json&q=" + encodeURIComponent(yqlq)
  hash = crypto.createHash('md5').update(yqlq).digest("hex")
  redis.get("yqlqh:#{hash}").then (cached)->
    logger.log "uri", uri
    unless cached
      request
        uri: uri
      , (error, response, body) ->
        redis.set "yqlqh:#{hash}", body
        redis.expire "yqlqh:#{hash}", 60*8 #8minut
        body = JSON.parse(body)
        cbl body.query.results
    else
      cbl JSON.parse(cached).query.results

vreme = (kraj, cb) ->

  yql "select woeid from geo.places where text = \"" + kraj + "\"", (res) ->
    if res
      try
        id = _.first(res.place).woeid
      catch e
        id = res.place.woeid
      
      yql "select item from weather.forecast where woeid = \"" + id + "\"", (res) ->
        item = res.channel.item
        cb "#{(100 / (212 - 32) * (item.condition.temp - 32)).toFixed(2)}°C #{item.link}"
    else
      cb "Podatka o vremenu ni..."
vreme2 = (lat, lon, cb) ->

  request.get "http://api.openweathermap.org/data/2.5/weather?APPID=017203dd3aeecf20cfb0b4bc1b032b36&lat=#{lat}&lon=#{lon}", (err, b, res) ->
    unless err
      res = JSON.parse(res)
      vzhod = moment.unix(res.sys.sunrise).format("HH:mm:ss")
      zahod = moment.unix(res.sys.sunset).format("HH:mm:ss")
      t = (res.main.temp-273.15).toFixed(2)
      cb "#{res.name}: #{t}°C, Sončni vzhod: #{vzhod}, Sončni zahod: #{zahod}"
    else
      cb "Podatkov o vremenu ni mogoče pridobiti..."

arso = (key, cb) ->
  request.get "http://maps.googleapis.com/maps/api/geocode/json?address=#{encodeURI(key)},%20slovenija&sensor=true", (err, b, res) ->
    if err
      vreme key, (msg)->
        cb "#{key}: #{msg}"
    else
      try
        res = JSON.parse(res)
        krajg = _.first(_.first(res.results).address_components).short_name
        loc = _.first(res.results).geometry.location
        imeg = _.first(res.results).formatted_address
        if (/Slovenia/i).test imeg 
          yql 'select metData.ddavg_longText, metData.rh, metData.ffavg_val, metData.domain_altitude, metData.t, metData.tsValid_issued, metData.domain_longTitle, metData.domain_lat, metData.domain_lon from xml where url in (select title from atom where url="http://spreadsheets.google.com/feeds/list/0AvY_vCMQloRXdE5HajQxUGF5ZEZYUjhKNG9EeVl2bFE/od6/public/basic")',
            (lokacije)->
              lokacije = lokacije.data
              lokacije.sort (a, b)->
                a = oddaljenost a.metData.domain_lat, a.metData.domain_lon, loc.lat, loc.lng
                b = oddaljenost b.metData.domain_lat, b.metData.domain_lon, loc.lat, loc.lng
                return a - b;
              kraj = _.first(lokacije)
              cb """ARSO: #{kraj.metData.domain_longTitle} (#{kraj.metData.domain_altitude}m): #{kraj.metData.t}°C @#{kraj.metData.tsValid_issued}.\nVlažnost: #{kraj.metData.rh}% Veter: #{kraj.metData.ddavg_longText} #{kraj.metData.ffavg_val} m/s\nhttp://forecast.io/#/f/#{loc.lat},#{loc.lng}"""
              vreme2 loc.lat, loc.lng, (msg)->
                cb msg
        else
          vreme key, (msg)->
            cb "#{imeg}: #{msg}"   
      catch e
        console.log  e
        cb "Neznana lokacija"


module.exports = (bot) ->
  bot.regexp /^\.vreme (.+)/i,
    ".vreme <kraj> dobi podatke o vremenu za <kraj>"
    (match, r) ->
      key = match[1]
      arso key, (msg)->
        r.reply msg

module.exports.arso = arso
