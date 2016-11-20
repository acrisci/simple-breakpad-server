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
  port: process.env.BREAKPAD_PORT || 1127
  baseUrl: process.env.BASEURL || '/'
  database:
    host: 'localhost'
    dialect: 'sqlite'
    storage: path.join(SBS_HOME, 'database.sqlite')
    logging: no
  customFields:
    files: []
    params: []
  dataDir: SBS_HOME

nconf.getSymbolsPath = -> path.join(nconf.get('dataDir'), 'symbols')

fs.mkdirsSync(nconf.getSymbolsPath())

module.exports = nconf
