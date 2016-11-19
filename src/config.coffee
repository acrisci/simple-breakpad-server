nconf = require 'nconf'
nconf.formats.yaml = require 'nconf-yaml'
fs = require 'fs-promise'

SBS_HOME = "#{process.env.HOME}/.simple-breakpad-server"

nconf.file 'pwd', {
  file: "#{process.cwd()}/breakpad-server.yaml"
  format: nconf.formats.yaml
}
nconf.file 'user', {
  file: "#{SBS_HOME}/breakpad-server.yaml"
  format: nconf.formats.yaml
}
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
    storage: "#{SBS_HOME}/database.sqlite"
    logging: no
  customFields:
    files: []
    params: []
  dataDir: "#{SBS_HOME}"

nconf.getSymbolsPath = -> "#{nconf.get('dataDir')}/symbols"

fs.mkdirsSync(nconf.getSymbolsPath())

module.exports = nconf
