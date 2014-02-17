# Simple PC-Axis to JSON REST-API server

A simple server written in Coffeescript for node.js that
reads a PC-Axis .px file using px.js and serves it over a
simple REST API producing JSON records.

The output format is geared towards ease of use, at the expense
of performance. If you query large datasets or otherwise like
a more performant option, using the .px file using eg. px.js
is a more suitable choice.

## Usage

To get started, you need the Coffeescript compiler/interpreter and
`npm`. Install dependencies with `npm install` and launch the server
with `coffee px-json-proxy.coffee`. There should be something in
http://localhost:9100/resources after that.

The datasets to export are configured in `data-sources.json` and
server configuration (ie port number) is in `config.json`.
