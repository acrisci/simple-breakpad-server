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
fs = require 'fs-promise'

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

  json = report.toJSON()
  for k,v of json
    if k in hidden
      # pass
    else if config.get("customFields:filesById:#{k}")
      # a file
      fields.props[k] = { path: "/crashreports/#{report.id}/files/#{k}" }
    else if Buffer.isBuffer(json[k])
      # shouldn't happen, should hit line above
    else if k == 'created_at'
      # change the name of this key for display purposes
      fields.props['created'] = moment(v).fromNow()
    else if v instanceof Date
      fields.props[k] = moment(v).fromNow()
    else
      fields.props[k] = if v? then v else 'not present'

  if !fields.props.upload_file_minidump
    fields.props.upload_file_minidump = { path: "/crashreports/#{report.id}/files/upload_file_minidump" }

  return fields

symfileToViewJson = (symfile, contents) ->
  hidden = ['id', 'updated_at', 'contents']
  fields =
    id: symfile.id
    contents: contents
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
      pruneSymfilesFromDB = not config.get('filesInDatabase')
      # TODO: This is really, really slow when you have a lot of symfiles, and
      #   config.get('filesInDatabase') is true - only write those which do not
      #   already exist on disk?  User can delete the on-disk cache if needed.
      Promise.all(symfiles.map((s) -> Symfile.saveToDisk(s, pruneSymfilesFromDB)))
  .then ->
    console.log 'Symfile loading finished'
    if Symfile.didPrune
      # One-time vacuum of sqllite data to free up all of the data that was just deleted
      console.log 'One-time compacting and syncing database after prune...'
      db.query('VACUUM').then ->
        db.sync().then ->
          console.log 'Database compaction finished'
    else
      return
  .then ->
    run()
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

  breakpad.use(require('express-decompress').create());
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

    if err.stack
      console.error err
    else
      console.trace err
    res.status(500).send "Bad things happened:<br/> #{err.message || err}"

  breakpad.use(busboy(
    limits:
      fileSize: config.get 'fileMaxUploadSize'
  ))
  lastReportId = 0
  breakpad.post '/crashreports', (req, res, next) ->
    props = {}
    streamOps = []
    # Get originating request address, respecting reverse proxies (e.g.
    #   X-Forwarded-For header)
    # Fixed list of just localhost as trusted reverse-proxy, we can add
    #   a config option if needed
    props.ip = addr(req, ['127.0.0.1', '::ffff:127.0.0.1'])
    reportUploadGuid = moment().format('YYYY-MM-DD.HH.mm.ss') + '.' +
      process.pid + '.' + (++lastReportId)

    req.busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
      if config.get('filesInDatabase')
        streamOps.push streamToArray(file).then((parts) ->
          buffers = []
          for i in [0 .. parts.length - 1]
            part = parts[i]
            buffers.push if part instanceof Buffer then part else
              new Buffer(part)

          return Buffer.concat(buffers)
        ).then (buffer) ->
          if fieldname of Crashreport.attributes
            props[fieldname] = buffer
      else
        # Stream file to disk, record filename in database
        if fieldname of Crashreport.attributes
          saveFilename = path.join reportUploadGuid, fieldname
          props[fieldname] = saveFilename
          saveFilename = path.join config.getUploadPath(), saveFilename
          fs.mkdirs(path.dirname(saveFilename)).then ->
            file.pipe fs.createWriteStream(saveFilename)
        else
          file.close()

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
        return res.send 404, 'Symfile not found'

      if 'raw' of req.query
        res.set 'content-type', 'text/plain'
        if symfile.contents?
          res.send(symfile.contents.toString())
          res.end()
        else
          fs.createReadStream(Symfile.getPath(symfile)).pipe(res)

      else
        Symfile.getContents(symfile).then (contents) ->
          res.render 'symfile-view', {
            title: 'Symfile'
            symfile: symfileToViewJson(symfile, contents)
          }

  breakpad.get '/crashreports/:id', (req, res, next) ->
    Crashreport.findById(req.params.id).then (report) ->
      if not report?
        return res.send 404, 'Crash report not found'
      Crashreport.getStackTrace report, (err, stackwalk) ->
        if err
          stackwalk = err.stack || err
          err = null
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
    field = req.params.filefield
    if !config.get("customFields:filesById:#{field}")
      return res.status(404).send 'Crash report field is not a file'

    Crashreport.findById(req.params.id).then (crashreport) ->
      if not crashreport?
        return res.status(404).send 'Crash report not found'

      contents = crashreport.get(field)

      # Find appropriate downloadAs file name
      filename = config.get("customFields:filesById:#{field}:downloadAs") || field
      filename = filename.replace('{{id}}', req.params.id)

      if !config.get('filesInDatabase')
        # If this is a string, or a string stored as a blob in an old database,
        # stream the on-disk file instead
        onDiskFilename = contents
        if Buffer.isBuffer(contents)
          if contents.length > 128
            # Large, must be an old actual dump stored in the database
            onDiskFilename = null
          else
            onDiskFilename = contents.toString('utf8')
        if onDiskFilename
          # stream
          res.setHeader('content-disposition', "attachment; filename=\"#{filename}\"")
          return fs.createReadStream(path.join(config.getUploadPath(), onDiskFilename)).pipe(res)

      if not Buffer.isBuffer(contents)
        return res.status(404).send 'Crash report field is an unknown type'

      res.setHeader('content-disposition', "attachment; filename=\"#{filename}\"")
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
    Symfile.createFromRequest req, res, (err, symfile) ->
      return next(err) if err?
      symfileJson = symfile.toJSON()
      delete symfileJson.contents
      res.json symfileJson

  app.listen port
  console.log "Listening on port #{port}"
