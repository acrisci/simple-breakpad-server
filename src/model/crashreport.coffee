config = require '../config'
path = require 'path'
fs = require 'fs-promise'
cache = require './cache'
minidump = require '@jimbly/minidump'
Sequelize = require 'sequelize'
sequelize = require './db'
tmp = require 'tmp'

symbolsPath = config.getSymbolsPath()

# custom fields should have 'files' and 'params'
customFields = config.get('customFields') || {}

schema =
  id:
    type: Sequelize.INTEGER
    autoIncrement: yes
    primaryKey: yes
  product: Sequelize.STRING
  version: Sequelize.STRING

options =
  indexes: [
    { fields: ['created_at'] }
  ]

for field in customFields.params
  schema[field.name] = Sequelize.STRING

for field in customFields.files
  schema[field.name] = if config.get('filesInDatabase') then Sequelize.BLOB else Sequelize.STRING

Crashreport = sequelize.define('crashreports', schema, options)

Crashreport.getStackTrace = (record, callback) ->
  return callback(null, cache.get(record.id)) if cache.has record.id

  if !config.get('filesInDatabase')
    # If this is a string, or a string stored as a blob in an old database,
    # just use the on-disk file instead
    onDiskFilename = record.upload_file_minidump
    if Buffer.isBuffer(record.upload_file_minidump)
      if record.upload_file_minidump.length > 128
        # Large, must be an old actual dump stored in the database
        onDiskFilename = null
      else
        onDiskFilename = record.upload_file_minidump.toString('utf8')
    if onDiskFilename
      # use existing file, do not delete when done!
      use_filename = path.join(config.getUploadPath(), onDiskFilename)
      return minidump.walkStack use_filename, [symbolsPath], (err, report) ->
        cache.set record.id, report unless err?
        callback err, report

  tmpfile = tmp.fileSync()
  fs.writeFile(tmpfile.name, record.upload_file_minidump).then ->
    minidump.walkStack tmpfile.name, [symbolsPath], (err, report) ->
      tmpfile.removeCallback()
      cache.set record.id, report unless err?
      callback err, report
  .catch (err) ->
    tmpfile.removeCallback()
    callback err

module.exports = Crashreport
