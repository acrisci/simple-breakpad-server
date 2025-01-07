nconf = require 'nconf'
nconf.formats.yaml = require 'nconf-yaml'
fs = require 'fs-promise'
os = require 'os'
path = require 'path'

SBS_HOME = path.join(os.homedir(), '.simple-breakpad-server')

nconf.file 'pwd', {
  file: path.join(process.cwd(), 'breakpad-server.yaml')
  format: nconf.formats.yaml
}
nconf.file 'user', {
  file: path.join(SBS_HOME, 'breakpad-server.yaml')
  format: nconf.formats.yaml
}
unless process.platform == 'win32'
  nconf.file 'system', {
    file: '/etc/breakpad-server.yaml'
    format: nconf.formats.yaml
  }

nconf.argv()
nconf.env()

nconf.defaults
  port: 1127
  baseUrl: '/'
  database:
    host: 'localhost'
    dialect: 'sqlite'
    storage: path.join(SBS_HOME, 'database.sqlite')
    logging: no
  customFields:
    files: []
    params: []
    hide: []
  extraField: null
  dataDir: SBS_HOME
  filesInDatabase: true
  fileMaxUploadSize: Infinity

# Post-process custom files and params
customFields = nconf.get('customFields')

# Ensure array
customFields.files = customFields.files || []
# Always add upload_file_minidump file as first file
customFields.files.splice(0, 0,
  name: 'upload_file_minidump'
  downloadAs: 'upload_file_minidump.{{id}}.dmp'
)
# If extraField is specified, ensure it's also in customField.params
extraField = nconf.get('extraField')
if typeof extraField is 'string'
  if customFields.params.indexOf(extraField) == -1
    customFields.params.push(extraField)
# Ensure array members are objects and build lookup
customFields.filesById = {}
for field, idx in customFields.files
  if typeof field is 'string'
    customFields.files[idx] =
      name: field
  customFields.filesById[customFields.files[idx].name] = customFields.files[idx]

# Ensure array
customFields.params = customFields.params || []
# Always add ip as first params
customFields.params.splice(0, 0,
  name: 'ip'
)
# Ensure array members are objects and build lookup
customFields.paramsById = {}
for field, idx in customFields.params
  if typeof field is 'string'
    customFields.params[idx] =
      name: field
  customFields.paramsById[customFields.params[idx].name] = customFields.params[idx]

nconf.set('customFields', customFields)

nconf.getSymbolsPath = -> path.join(nconf.get('dataDir'), 'symbols')
nconf.getUploadPath = -> path.join(nconf.get('dataDir'), 'uploads')

fs.mkdirsSync(nconf.getSymbolsPath())

module.exports = nconf
