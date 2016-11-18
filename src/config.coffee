nconf = require 'nconf'
nconf.formats.yaml = require 'nconf-yaml'

nconf.file 'pwd', {
  file: "#{process.cwd()}/breakpad-server.yaml"
  format: nconf.formats.yaml
}
nconf.file 'user', {
  file: "#{process.env.HOME}/.simple-breakpad-server/breakpad-server.yaml"
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
    storage: 'database.sqlite'
    logging: no
  customFields:
    files: []
    params: []

module.exports = nconf
