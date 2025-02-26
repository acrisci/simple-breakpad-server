config = require '../config'
cache = require './cache'
Sequelize = require 'sequelize'
sequelize = require './db'
fs = require 'fs-promise'
path = require 'path'
streamToArray = require 'stream-to-array'

symbolsPath = config.getSymbolsPath()
COMPOSITE_INDEX = 'compositeIndex'

schema =
  id:
    type: Sequelize.INTEGER
    autoIncrement: yes
    primaryKey: yes
  os:
    type: Sequelize.STRING
    unique: COMPOSITE_INDEX
  name:
    type: Sequelize.STRING
    unique: COMPOSITE_INDEX
  code:
    type: Sequelize.STRING
    unique: COMPOSITE_INDEX
  arch:
    type: Sequelize.STRING
    unique: COMPOSITE_INDEX
  contents: Sequelize.TEXT

options =
  indexes: [
    { fields: ['created_at'] }
  ]

Symfile = sequelize.define('symfiles', schema, options)

Symfile.getPath = (symfile) ->
  symfileDir = path.join(symbolsPath, symfile.name, symfile.code)
  # From https://chromium.googlesource.com/breakpad/breakpad/+/master/src/processor/simple_symbol_supplier.cc#179:
  # Transform the debug file name into one ending in .sym.  If the existing
  #   name ends in .pdb, strip the .pdb.  Otherwise, add .sym to the non-.pdb
  #   name.
  symbol_name = symfile.name
  if path.extname(symbol_name).toLowerCase() == '.pdb'
    symbol_name = symbol_name.slice(0, -4)
  symbol_name += '.sym'
  path.join(symfileDir, symbol_name)

Symfile.saveToDisk = (symfile, prune) ->
  filePath = Symfile.getPath(symfile)

  # Note: this code will migrate symbol files between filesInDatabase: true/false,
  #   or from an older version where filesInDatabase: true only referred to
  #   dump files, however dump files have no similar migration - the database
  #   must be wiped, so this is only actually useful for upgrading versions,
  #   not switching between filesInDatabase modes, though it can be used
  #   to import/export symbol files if you don't care about old dumps.

  if not symfile.contents
    if not prune
      # If at startup, and the option was set back to "filesInDatabase", read them back from disk?
      return fs.exists(filePath).then (exists) ->
        if (exists)
          console.log "Restoring contents to database from symfile #{symfile.id}, #{filePath}"
          fs.readFile(filePath, 'utf8').then (contents) ->
            Symfile.didPrune = true
            Symfile.update({ contents: contents }, { where: { id: symfile.id }, fields: ['contents']})
    else
      # At startup, pruning, already no contents, great!
      return

  fs.mkdirs(path.dirname(filePath)).then ->
    fs.writeFile(filePath, symfile.contents).then ->
      if prune
        console.log "Pruning contents from database for symfile #{symfile.id}, file saved at #{filePath}"
        delete symfile.contents
        Symfile.didPrune = true
        Symfile.update({ contents: null }, { where: { id: symfile.id }, fields: ['contents']})

Symfile.getContents = (symfile) ->
  if config.get('filesInDatabase')
    Promise.resolve(symfile.contents)
  else
    fs.readFile(Symfile.getPath(symfile), 'utf8')

Symfile.createFromRequest = (req, res, callback) ->
  props = {}
  streamOps = []

  req.busboy.on 'file', (fieldname, file, filename, encoding, mimetype) ->
    streamOps.push streamToArray(file).then((parts) ->
      buffers = []
      for i in [0 .. parts.length - 1]
        part = parts[i]
        buffers.push if part instanceof Buffer then part else new Buffer(part)

      return Buffer.concat(buffers)
    ).then (buffer) ->
      if fieldname == 'symfile'
        props[fieldname] = buffer

  req.busboy.on 'finish', ->
    Promise.all(streamOps).then ->
      if not props.hasOwnProperty('symfile')
        res.status 400
        throw new Error 'Form must include a "symfile" field'

      contents = props.symfile
      header = contents.toString('utf8', 0, 4096).split('\n')[0].match(/^(MODULE) ([^ ]+) ([^ ]+) ([0-9A-Fa-f]+) (.*)/)

      [line, dec, os, arch, code, name] = header

      if dec != 'MODULE'
        msg = 'Could not parse header (expecting MODULE as first line)'
        throw new Error msg

      props =
        os: os
        arch: arch
        code: code
        name: name
        contents: contents

      sequelize.transaction (t) ->
        whereDuplicated =
          where: { os: os, arch: arch, code: code, name: name}

        Symfile.findOne(whereDuplicated, {transaction: t}).then (duplicate) ->
          p =
            if duplicate?
              duplicate.destroy({transaction: t})
            else
              Promise.resolve()
          p.then ->
            Symfile.saveToDisk(props, false).then ->
              if not config.get('filesInDatabase')
                delete props.contents
              Symfile.create(props, {transaction: t}).then (symfile) ->
                cache.clear()
                callback(null, symfile)

    .catch (err) ->
      callback err

  req.pipe(req.busboy)

module.exports = Symfile
