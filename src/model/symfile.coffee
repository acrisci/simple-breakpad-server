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

Symfile.saveToDisk = (symfile) ->
  symfileDir = path.join(symbolsPath, symfile.name, symfile.code)
  fs.mkdirs(symfileDir).then ->
    # From https://chromium.googlesource.com/breakpad/breakpad/+/master/src/processor/simple_symbol_supplier.cc#179:
    # Transform the debug file name into one ending in .sym.  If the existing
    #   name ends in .pdb, strip the .pdb.  Otherwise, add .sym to the non-.pdb
    #   name.
    symbol_name = symfile.name
    if path.extname(symbol_name).toLowerCase() == '.pdb'
      symbol_name = symbol_name.slice(0, -4)
    symbol_name += '.sym'
    filePath = path.join(symfileDir, symbol_name)
    fs.writeFile(filePath, symfile.contents)

Symfile.createFromRequest = (req, callback) ->
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
        props[fieldname] = buffer.toString()

  req.busboy.on 'finish', ->
    Promise.all(streamOps).then ->
      if not 'symfile' of props
        res.status 400
        throw new Error 'Form must include a "symfile" field'

      contents = props.symfile
      header = contents.split('\n')[0].split(/\s+/)

      [dec, os, arch, code, name] = header

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
            Symfile.create(props, {transaction: t}).then (symfile) ->
              Symfile.saveToDisk(symfile).then ->
                cache.clear()
                callback(null, symfile)

    .catch (err) ->
      callback err

  req.pipe(req.busboy)

module.exports = Symfile
