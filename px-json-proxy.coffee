restify = require 'restify'
Q = require 'q'
urllib = require 'url'
requestlib = require 'request'
path = require 'path'
px = require 'px'
iconv = require 'iconv-lite'

config = require './config.json'
source_config = require './data-sources.json'

geturl = (url) ->
    promise = Q.defer()
    requestlib url, (error, response, body) ->
        if error
            promise.reject error
            return
        if response.statusCode != 200
            promise.reject response.statusCode
            return

        promise.resolve [body, response]

    return promise.promise

class PxSource
    constructor: (@metadata, @data) ->
        @px = new px.Px @data
        @metadata.title = @px.metadata.TITLE.TABLE
        variables = {}
        for variable in @px.variables()
            variables[variable] = @px.values variable
        #@metadata.variables = variables

load_sources = (source_config) ->
    handle_source = (source_spec) ->
        deferred = Q.defer()
        data_promise = geturl source_spec.url

        data_promise.then ([data, res]) ->
            fname = res.headers['content-disposition']
            fname = /.*;.*filename=([^ ]*)/.exec fname
            if not fname
                fname = path.basename source_spec.url
            else
                fname = fname[1]
            fname = fname.split('.')
            fname = fname[...fname.length-1].join('.')
            host = urllib.parse(source_spec.url).host
            resource_name = [host, fname].join "_"
            
            metadata =
                origin_url: source_spec.url
            
            resource = new PxSource metadata, data
            deferred.resolve [resource_name, resource]
        
        data_promise.fail (error) ->
            deferred.reject [source_spec, error]
        
        return deferred.promise
    
    source_promises = source_config.map handle_source
    sources_promise = Q.defer()
    n_fulfilled = 0
    for promise in source_promises
        promise.finally ->
            n_fulfilled += 1
            console.log "#{n_fulfilled}/#{source_promises.length} fetched"
        promise.then ([name, resource]) ->
            url = resource.metadata.origin_url
            size = resource.data.length
            console.log "#{name} #{url}: #{size} bytes"
        promise.fail ([source_spec, error]) ->
            console.log "Resource fetching failed (#{error}): " +
                source_spec.url
    
    Q.allSettled(source_promises).then (results) ->
        sources = {}
        for result in results
            continue if result.state == "rejected"
            [name, resource] = result.value
            sources[name] = resource
        sources_promise.resolve sources
    return sources_promise.promise

dryrouter = (server) -> (route, handler) ->
    server.get route, (req, res, next) ->
        result = handler req.params, req, res, next
        if result
            res.send result

class PxServer
    constructor: (@_sources, @_mypath, server) ->
        router = dryrouter server
        router @_mypath, @index
        router "#{@_mypath}/:name/json", @json
        router "#{@_mypath}/:name/px", @px

    _description: (name) =>
        resource = @_sources[name]
        entry = {}
        for k of resource.metadata
            entry[k] = resource.metadata[k]

        path = [@_mypath, name].join '/'
        entry['_links'] =
            json:
                href: [path, 'json'].join '/'
            px:
                href: [path, 'px'].join '/'
        return entry

    index: =>
        listing = {}
        for name, resource of @_sources
            listing[name] = @_description name
        
        listing['_links'] = {
            'self': @_mypath
            }

        return listing

    px: (param) =>
        return @_sources[param.name].data

    json: (param) =>
        data = new px.Px @_sources[param.name].data
        return data.entries()

setup_server = (sources) ->
    server = restify.createServer()
    .use(restify.fullResponse())
    .use(restify.CORS())
    
    root_name = '/resources'
    px_server = new PxServer(sources, root_name, server)
    console.log "Listening on #{config.server.port}"
    server.listen config.server.port

load_sources(source_config).done setup_server
