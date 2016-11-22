Sequelize = require 'sequelize'
config = require '../config'

options = config.get 'database'
options.define = options.define || {}

defaultModelOptions =
  timestamps: yes
  underscored: yes

options.define = Object.assign(options.define, defaultModelOptions)

sequelize = new Sequelize(options.database, options.username,
                          options.password, options)

module.exports = sequelize
