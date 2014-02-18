request = require "request"

# TODO: This probably doesn't belong here
metadata_url = "http://www.hri.fi/wp-content/uploads/ckan/hri-ckan-active-metadata-daily-output.json"

request metadata_url, (error, response, body) ->
    sources = []
    packages = JSON.parse(body).packages
    for pkg in packages
        for resource in pkg.resources
            if resource.format != 'pc-axis'
                continue
            sources.push
                url: resource.url
                encoding: "iso8859-1"
    console.log JSON.stringify sources, undefined, 2
