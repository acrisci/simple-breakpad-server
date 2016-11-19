# Simple Breakpad Server

Simple collecting server for crash reports sent by [google-breakpad](https://code.google.com/p/google-breakpad/).

Simple Breakpad Server is a lightweight alternative to [Socorro](https://github.com/mozilla/socorro) for small projects.

## Installing

    npm install -g simple-breakpad-server

## Features

* Send crash reports to the server from your applications.
* Display crash report information like minidump stackwalks and application metadata.
* Supports PostgreSQL, MySQL, MariaDB, SQLite and MSSQL.
* Simple web interface for viewing translated crash reports.
* Add symbols from the web API.

## Running in Development

Simple Breakpad Server uses [Grunt](http://gruntjs.com/) as a task runner.

```sh
npm install -g grunt
npm install
grunt serve
```

The server is now running on port 1127. The default database location is `$HOME/.simple-breakpad-server/database.sqlite`.

## Endpoints

### `GET /crashreports`

View a list of crash reports.

### `GET /crashreports/<id>`

View a single crash report.

### `GET /crashreports/<id>/<file>`

Download a file associated with this crash report. For example, to download the minidump file for a crash report, use `/crashreports/123/upload_file_minidump`.

### `POST /crashreports`

Create a new crash report. Use content type `multipart/form-data`. Some applications already dump a file in this format, so you can just upload that.

If you have a binary minidump file, use a curl request like this:

```sh
curl -F upload_file_minidump=@mymini.dmp \
     -F ver="0.0.1" \
     -F prod=cef \
     localhost:1127/crashreports
```

### `POST /symfiles`

Add a new symbol file to the database to use to symbolize crash reports.

To create a symfile for your binary, first follow the instructions to install the [google-breakpad](https://github.com/google/breakpad) project.

Then use the `dump_syms` binary to generate a symbol file.

```
dump_syms /path/to/binary > /path/to/symfile.syms
```

Use the content type `multipart/form-data` to upload it to the server from this endpoint with the name of the file being `symfile`. Here is an example curl request to upload your symfile:

```sh
curl -F symfile=@symfile.syms localhost:1127/symfiles
```

## Configuration

Configuration is done in yaml (or json).

The configuration path is as follows:

* `$PWD/breakpad-server.yaml`
* `/etc/breakpad-server.yaml`

Here is an example configuration:

```yaml
port: 1127
baseUrl: '/'
database:
  dialect: 'sqlite'
  storage: '/home/myuser/.simple-breakpad-server/database.sqlite'
  logging: false
customFields:
  files: []
  params: []
dataDir: '/home/myuser/.simple-breakpad-server'
```

### Database configuration

Database options are passed directly to [Sequelize](http://docs.sequelizejs.com/en/v3/api/sequelize/). See that page for details on how to configure the database. Currently, sqlite is best supported by Simple Breakpad Server.

### Custom Fields

The `customFields` member has two members. Place a list of file parameters in the `files` array. These will be stored in the database as blobs and can contain binary data. Non-files should go into the `params` array. These will be stored in the database encoded as strings.

Custom `files` can be downloaded from the `GET /crashreports/<id>/<file>` endpoint and custom `params` will be shown on the main page for the crash report.

For now, if you change this configuration after the database is initialized, you will have to create the tables on your database manually for things to work.

### Data Directory

Simple breakpad server caches symbols on the disk within the directory specified by `dataDir`. The default location is `$HOME/.simple-breakpad-server`.

## Contributing

Simple Breakpad Server is a work in progress and there is a lot to do. Send pull requests and issues on the project's [Github page](https://github.com/acrisci/simple-breakpad-server).

Here are some things to do:

* improve UI
* endpoint to delete crash reports
* group and filter crash reports
* break the cache when new symfiles are added
* script to create symfiles

This project open source available to you under an [MIT license](https://github.com/acrisci/simple-breakpad-server/blob/master/LICENSE).
