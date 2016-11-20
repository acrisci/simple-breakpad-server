Sequelize = require 'sequelize'
config = require '../config'

options = config.get 'database'

sequelize = new Sequelize(options.database, options.username, options.password, options)

module.exports = sequelize
