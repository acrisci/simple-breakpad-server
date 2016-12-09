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
busboy = require 'connect-busboy'
streamToArray = require 'stream-to-array'
Sequelize = require 'sequelize'
addr = require 'addr'

crashreportToApiJson = (crashreport) ->
  json = crashreport.toJSON()

  for k,v of json
    if Buffer.isBuffer(json[k])
      json[k] = "/crashreports/#{json.id}/files/#{k}"

  json

crashreportToViewJson = (report) ->
  hidden = ['id', 'updated_at']
  fields =
    id: report.id
    props: {}

  for name, value of Crashreport.attributes
    if value.type instanceof Sequelize.BLOB
      fields.props[name] = { path: "/crashreports/#{report.id}/files/#{name}" }

  json = report.toJSON()
  for k,v of json
    if k in hidden
      # pass
    else if Buffer.isBuffer(json[k])
      # already handled
    else if k == 'created_at'
      # change the name of this key for display purposes
      fields.props['created'] = moment(v).fromNow()
    else if v instanceof Date
      fields.props[k] = moment(v).fromNow()
    else
      fields.props[k] = if v? then v else 'not present'

  return fields

symfileToViewJson = (symfile) ->
  hidden = ['id', 'updated_at', 'contents']
  fields =
    id: symfile.id
    contents: symfile.contents
    props: {}

  json = symfile.toJSON()

  for k,v of json
    if k in hidden
      # pass
    else if k == 'created_at'
      # change the name of this key for display purposes
      fields.props['created'] = moment(v).fromNow()
    else if v instanceof Date
      fields.props[k] = moment(v).fromNow()
    else
      fields.props[k] = if v? then v else 'not present'

  return fields

# initialization: init db and write all symfiles to disk
db.sync()
  .then ->
    Symfile.findAll().then (symfiles) ->
      Promise.all(symfiles.map((s) -> Symfile.saveToDisk(s))).then(run)
  .catch (err) ->
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
      symfileUrl: (id) -> "/symfiles/#{id}"
      titleCase: titleCase

  breakpad.set 'json spaces', 2
  breakpad.set 'views', path.resolve(__dirname, '..', 'views')
  breakpad.engine('handlebars', hbs.engine)
  breakpad.set 'view engine', 'handlebars'
  breakpad.use bodyParser.json()
  breakpad.use bodyParser.urlencoded({extended: true})
  breakpad.use methodOverride()

  baseUrl = config.get('baseUrl')
  port = config.get('port')

  app.use baseUrl, breakpad

  bsStatic = path.resolve(__dirname, '..', 'node_modules/bootstrap/dist')
  breakpad.use '/assets', express.static(bsStatic)

  # error handler
  app.use (err, req, res, next) ->
    if not err.message?
      console.log 'warning: error thrown without a message'

    console.trace err
    res.status(500).send "Bad things happened:<br/> #{err.message || err}"

  breakpad.use(busboy())
  breakpad.post '/crashreports', (req, res, next) ->
    props = {}
    streamOps = []
    # Get originating request address, respecting reverse proxies (e.g.
    #   X-Forwarded-For header)
    # Fixed list of just localhost as trusted reverse-proxy, we can add
    #   a config option if needed
    props.ip = addr(req, ['127.0.0.1', '::ffff:127.0.0.1'])

    req.busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      streamOps.push streamToArray(file).then((parts) ->
        buffers = []
        for i in [0 .. parts.length - 1]
          part = parts[i]
          buffers.push if part instanceof Buffer then part else new Buffer(part)

        return Buffer.concat(buffers)
      ).then (buffer) ->
        if fieldname of Crashreport.attributes
          props[fieldname] = buffer

    req.busboy.on 'field', (fieldname, val, fieldnameTruncated, valTruncated) ->
      if fieldname == 'prod'
        props['product'] = val
      else if fieldname == 'ver'
        props['version'] = val
      else if fieldname of Crashreport.attributes
        props[fieldname] = val.toString()

    req.busboy.on 'finish', ->
      Promise.all(streamOps).then ->
        Crashreport.create(props).then (report) ->
          res.json(crashreportToApiJson(report))
      .catch (err) ->
        next err

    req.pipe(req.busboy)

  breakpad.get '/', (req, res, next) ->
    res.redirect '/crashreports'

  breakpad.use paginate.middleware(10, 50)
  breakpad.get '/crashreports', (req, res, next) ->
    limit = req.query.limit
    offset = req.offset
    page = req.query.page

    attributes = []

    # only fetch non-blob attributes to speed up the query
    for name, value of Crashreport.attributes
      unless value.type instanceof Sequelize.BLOB
        attributes.push name

    findAllQuery =
      order: 'created_at DESC'
      limit: limit
      offset: offset
      attributes: attributes

    Crashreport.findAndCountAll(findAllQuery).then (q) ->
      records = q.rows
      count = q.count
      pageCount = Math.ceil(count / limit)

      viewReports = records.map(crashreportToViewJson)

      fields =
        if viewReports.length
          Object.keys(viewReports[0].props)
        else
          []

      res.render 'crashreport-index',
        title: 'Crash Reports'
        crashreportsActive: yes
        records: viewReports
        fields: fields
        pagination:
          hide: pageCount <= 1
          page: page
          pageCount: pageCount

  breakpad.use paginate.middleware(10, 50)
  breakpad.get '/symfiles', (req, res, next) ->
    limit = req.query.limit
    offset = req.offset
    page = req.query.page

    findAllQuery =
      order: 'created_at DESC'
      limit: limit
      offset: offset

    Symfile.findAndCountAll(findAllQuery).then (q) ->
      records = q.rows
      count = q.count
      pageCount = Math.ceil(count / limit)

      viewSymfiles = records.map(symfileToViewJson)

      fields =
        if viewSymfiles.length
          Object.keys(viewSymfiles[0].props)
        else
          []

      res.render 'symfile-index',
        title: 'Symfiles'
        symfilesActive: yes
        records: viewSymfiles
        fields: fields
        pagination:
          hide: pageCount <= 1
          page: page
          pageCount: pageCount

  breakpad.get '/symfiles/:id', (req, res, next) ->
    Symfile.findById(req.params.id).then (symfile) ->
      if not symfile?
        resturn res.send 404, 'Symfile not found'

      if 'raw' of req.query
        res.set 'content-type', 'text/plain'
        res.send(symfile.contents.toString())
        res.end()
      else
        res.render 'symfile-view', {
          title: 'Symfile'
          symfile: symfileToViewJson(symfile)
        }

  breakpad.get '/crashreports/:id', (req, res, next) ->
    Crashreport.findById(req.params.id).then (report) ->
      if not report?
        return res.send 404, 'Crash report not found'
      Crashreport.getStackTrace report, (err, stackwalk) ->
        return next err if err?
        fields = crashreportToViewJson(report).props

        res.render 'crashreport-view', {
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

  breakpad.get '/api/crashreports', (req, res, next) ->
    # Query for a count of crash reports matching the requested query parameters
    # e.g. /api/crashreports?version=1.2.3
    where = {}
    for name, value of Crashreport.attributes
      unless value.type instanceof Sequelize.BLOB
        if req.query[name]
          where[name] = req.query[name]
    Crashreport.count({ where }).then (result) ->
      res.json
        count: result
    .error next


  breakpad.use(busboy())
  breakpad.post '/symfiles', (req, res, next) ->
    Symfile.createFromRequest req, (err, symfile) ->
      return next(err) if err?
      symfileJson = symfile.toJSON()
      delete symfileJson.contents
      res.json symfileJson

  app.listen port
  console.log "Listening on port #{port}"
