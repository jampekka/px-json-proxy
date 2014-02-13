express = require 'express'
Q = require 'q'
http = require 'http'
urllib = require 'url'
path = require 'path'
px = require 'px'

config = require './config.json'
source_config = require './data-sources.json'

geturl = (url) ->
    deferred = Q.defer()
    data = ""
    req = http.get url, (response) ->
        response.setEncoding 'utf8'
        response.on "data", (chunk) ->
            data += chunk
        response.on "end", ->
            deferred.resolve [data, response]

    req.on 'error', (e) ->
        console.log e
        deferred.reject e
    return deferred.promise

load_sources = (source_config) ->
    sources = {}
    handle_source = (source_spec) ->
        deferred = Q.defer()
        data_promise = geturl source_spec.url

        data_promise.done ([data, res]) ->
            fname = res.headers['content-disposition']
            fname = /.*;.*filename=([^ ]*)/.exec fname
            fname = fname[1].split('.')
            fname = fname[...fname.length-1].join('.')
            host = urllib.parse(source_spec.url).host
            resource_name = [host, fname].join("/")
        
            source_info =
                apis:
                    px:
                        url: '/' + resource_name + '.px'
                    json:
                        url: '/' + resource_name + '.json'
                origin_url: source_spec.url
            
            sources[resource_name] =
                info: source_info
                data: data

            deferred.resolve resource_name
        
        data_promise.catch (error) ->
            deferred.reject error

        return deferred.promise

    source_promises = source_config.map handle_source
    sources_promise = Q.defer()
    Q.allSettled(source_promises).done ->
        sources_promise.resolve sources
    return sources_promise.promise

load_sources(source_config).then (sources) ->
    server = express()
    
    source_infos = {}
    for name, spec of sources
        source_infos[name] = spec.info
    server.get '/index.json', (req, res) ->
        res.send(JSON.stringify source_infos)

    for name, source of sources
        server.get source.info.apis.px.url, (req, res) ->
            res.send source.data
        
        server.get source.info.apis.json.url, (req, res) ->
            dump = new px.Px(source.data).entries()
            res.send JSON.stringify(dump)

    server.listen config.server.port
