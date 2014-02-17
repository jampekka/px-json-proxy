restify = require 'restify'
Q = require 'q'
http = require 'http'
urllib = require 'url'
path = require 'path'
px = require 'px'
iconv = require 'iconv-lite'

config = require './config.json'
source_config = require './data-sources.json'

geturl = (url, encoding='utf8') ->
    deferred = Q.defer()
    data = new Buffer(0)
    req = http.get url, (response) ->
        response.on "data", (chunk) ->
            data = Buffer.concat [data, chunk]
        response.on "end", ->
            data = iconv.decode data, encoding
            deferred.resolve [data, response]

    req.on 'error', (e) ->
        console.log e
        deferred.reject e
    return deferred.promise

class PxSource
    constructor: (@metadata, @data) ->
        @px = new px.Px @data
        @metadata.title = @px.metadata.TITLE
        variables = {}
        for variable in @px.variables()
            variables[variable] = @px.values variable
        @metadata.variables = variables

load_sources = (source_config) ->
    handle_source = (source_spec) ->
        deferred = Q.defer()
        data_promise = geturl source_spec.url, source_spec.encoding

        data_promise.done ([data, res]) ->
            fname = res.headers['content-disposition']
            fname = /.*;.*filename=([^ ]*)/.exec fname
            fname = fname[1].split('.')
            fname = fname[...fname.length-1].join('.')
            host = urllib.parse(source_spec.url).host
            resource_name = [host, fname].join "_"
            
            metadata =
                origin_url: source_spec.url
            
            resource = new PxSource metadata, data
            deferred.resolve [resource_name, resource]
        
        data_promise.catch (error) ->
            deferred.reject error

        return deferred.promise

    source_promises = source_config.map handle_source
    sources_promise = Q.defer()
    Q.allSettled(source_promises).done (results) ->
        sources = {}
        for result in results
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
    server.listen config.server.port
###
    route root_name, px_server.resources
    
    server.get '/resources.json', (req, res) ->
        listing = {}
        for name, resource of sources
            listing[name]
        res.send(JSON.stringify source_info)
            

    server.get '/resources/:name/json', boilerplate (source) ->
        return JSON.stingify new px.Px source.data

    server.get '/resources/:name/px', boilerplate (source) ->
        return source.data
    
###

load_sources(source_config).then setup_server
