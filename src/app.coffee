config = require './config'
moment = require 'moment'
bodyParser = require 'body-parser'
methodOverride = require('method-override')
path = require 'path'
express = require 'express'
exphbs = require 'express-handlebars'
hbsPaginate = require 'handlebars-paginate'
paginate = require 'express-paginate'
Crashreport = require './model/crashreport'
Symfile = require './model/symfile'
db = require './model/db'
titleCase = require 'title-case'

crashreportToApiJson = (crashreport) ->
  json = crashreport.toJSON()

  for k,v of json
    if Buffer.isBuffer(json[k])
      json[k] = "/crashreports/#{json.id}/#{k}"

  json

crashreportToViewJson = (report) ->
  fields = {}
  json = report.toJSON()
  for k,v of json
    if Buffer.isBuffer(json[k])
      fields[k] = { path: "/crashreports/#{report.id}/files/#{k}" }
    else if v instanceof Date
      fields[k] = moment(v).fromNow()
    else
      fields[k] = if v? then v else 'not present'

  return fields

# initialization: init db and write all symfiles to disk
db.sync().then(->
  Symfile.findAll().then (symfiles) ->
    Promise.all(symfiles.map((s) -> Symfile.saveToDisk(s))).then(run)
).catch (err) ->
    console.error err.stack
    process.exit 1

run = ->
  app = express()
  breakpad = express()

  hbs = exphbs.create
    defaultLayout: 'main'
    partialsDir: path.resolve(__dirname, '..', 'views')
    layoutsDir: path.resolve(__dirname, '..', 'views', 'layouts')
    helpers:
      paginate: hbsPaginate
      reportUrl: (id) -> "/crashreports/#{id}"
      titleCase: titleCase

  breakpad.set 'views', path.resolve(__dirname, '..', 'views')
  breakpad.engine('handlebars', hbs.engine)
  breakpad.set 'view engine', 'handlebars'
  breakpad.use bodyParser.json()
  breakpad.use bodyParser.urlencoded({extended: true})
  breakpad.use methodOverride()

  baseUrl = config.get('baseUrl')
  port = config.get('port')

  app.use baseUrl, breakpad

  breakpad.use '/assets', express.static(path.resolve(__dirname, '..', 'node_modules/bootstrap/dist/css'))

  # error handler
  app.use (err, req, res, next) ->
    if not err.message?
      console.log 'warning: error thrown without a message'

    console.trace err
    res.status(500).send "Bad things happened:<br/> #{err.message || err}"

  breakpad.post '/crashreports', (req, res, next) ->
    Crashreport.createFromRequest req, (err, record) ->
      return next err if err?
      res.json crashreportToApiJson(record)

  breakpad.get '/', (req, res, next) ->
    res.redirect '/crashreports'

  breakpad.use paginate.middleware(15, 50)
  breakpad.get '/crashreports', (req, res, next) ->
    limit = req.query.limit
    offset = req.offset
    page = req.query.page

    findAllQuery =
      order: 'created_at DESC'
      limit: limit
      offset: offset

    Crashreport.findAndCountAll(findAllQuery).then (q) ->
      records = q.rows
      count = q.count
      pageCount = Math.floor(count / limit)

      viewReports = records.map(crashreportToViewJson)
      for r in viewReports
        delete r['updated_at']
      fields = if viewReports.length then Object.keys(viewReports[0]) else []
      res.render 'index',
        title: 'Crash Reports'
        records: viewReports
        fields: fields
        pagination:
          page: page
          pageCount: pageCount

  breakpad.get '/crashreports/:id', (req, res, next) ->
    Crashreport.findById(req.params.id).then (report) ->
      if not report?
        return res.send 404, 'Crash report not found'
      Crashreport.getStackTrace report, (err, stackwalk) ->
        return next err if err?
        fields = crashreportToViewJson(report)

        delete fields['id']
        delete fields['updated_at']

        res.render 'view', {
          title: 'Crash Report'
          stackwalk: stackwalk
          product: fields.product
          version: fields.version
          fields: fields
        }

  breakpad.get '/crashreports/:id/stackwalk', (req, res, next) ->
    # give the raw stackwalk
    Crashreport.findById(req.params.id).then (report) ->
      if not report?
        return res.send 404, 'Crash report not found'
      Crashreport.getStackTrace report, (err, stackwalk) ->
        return next err if err?
        res.set('Content-Type', 'text/plain')
        res.send(stackwalk.toString('utf8'))

  breakpad.get '/crashreports/:id/files/:filefield', (req, res, next) ->
    # download the file for the given id
    Crashreport.findById(req.params.id).then (crashreport) ->
      if not crashreport?
        return res.status(404).send 'Crash report not found'

      contents = crashreport.get(req.params.filefield)

      if not Buffer.isBuffer(contents)
        return res.status(404).send 'Crash report field is not a file'

      res.send(contents)

  breakpad.post '/symfiles', (req, res, next) ->
    Symfile.createFromRequest req, (err, symfile) ->
      return next(err) if err?
      symfileJson = symfile.toJSON()
      delete symfileJson.contents
      res.json symfileJson

  app.listen port
  console.log "Listening on port #{port}"
