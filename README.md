# Simple Breakpad Server

Simple collecting server for crash reports sent by [google-breakpad](https://code.google.com/p/google-breakpad/).

Simple Breakpad Server is a lightweight alternative to [Socorro](https://github.com/mozilla/socorro) for small projects.

## Installing

    npm install -g simple-breakpad-server

Now simply run `simple-breakpad-server` which should be in your PATH. Navigate to [localhost:1127](http://localhost:1127) in your browser to see the server.

## Features

* Send crash reports to the server from your applications.
* Display crash report information like minidump stackwalks and application metadata.
* Supports SQLite, PostgreSQL, MySQL, MariaDB
* Simple web interface for viewing translated crash reports.
* Add symbols from the web API.

## Running in Development

Simple Breakpad Server uses [Grunt](http://gruntjs.com/) as a task runner.

```sh
npm install
npm run-script serve
```

The server is now running on port 1127. The default database location is `$HOME/.simple-breakpad-server/database.sqlite`.

## Endpoints

### `GET /crashreports`

View a list of crash reports.

### `GET /crashreports/<id>`

View a single crash report.

### `GET /crashreports/<id>/files/<file>`

Download a file associated with this crash report. For example, to download the minidump file for a crash report, use `/crashreports/123/files/upload_file_minidump`.

### `GET /symfiles`

See a list of available symfiles used to symbolize the crash reports.

### `GET /symfiles/<id>`

See the contents of an individual symfile.

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
* `$HOME/.simple-breakpad-server/breakpad-server.yaml`
* `/etc/breakpad-server.yaml`

Here is an example configuration:

```yaml
port: 1127
baseUrl: '/'
database:
  database: 'simple-breakpad-server'
  username: 'myuser'
  password: 'secret'
  dialect: 'sqlite'
  storage: '/home/myuser/.simple-breakpad-server/database.sqlite'
  logging: false
customFields:
  files:
    - name: 'customfile1'
      downloadAs: 'customfile1.jpg'
    - name: 'customfile2'
  params: ['customparam']
dataDir: '/home/myuser/.simple-breakpad-server'
fileMaxUploadSize: 100000000
filesInDatabase: true
```

### Database configuration

Database options are passed directly to [Sequelize](http://docs.sequelizejs.com/en/v3/api/sequelize/). See that page for details on how to configure the database. Currently, sqlite is best supported by Simple Breakpad Server.

### Custom Fields

Place a list of file parameters in the `files` array. These will be stored in the database as blobs and can contain binary data. Non-files should go into the `params` array. These will be stored in the database encoded as strings.  File parameters can either be a simple string, or an object specifying a required `name` (used for upload and download url) and an optional `downloadAs` which specifies what name will be used when downloading.

Custom `files` can be downloaded from the `GET /crashreports/<id>/files/<file>` endpoint and custom `params` will be shown on the main page for the crash report.

For now, if you change this configuration after the database is initialized, you will have to create the tables on your database manually for things to work.

### Data Directory

Simple breakpad server caches symbols on the disk within the directory specified by `dataDir`. The default location is `$HOME/.simple-breakpad-server`.

## Uploaded Files

By default, there is no enforced limit to uploaded file size (limited by Node.js heap size and database size), and uploaded files (minidumps or custom files) are stored directly in the database.  The maximum allowed file size can be specified with `fileMaxUploadSize` (in bytes).

The server can be directed to store all uploaded files on disk (instead of in the database) with `filesInDatabase: false`, however the dumps may be unable to be read after switching, so the database should be recreated (manually delete the `database.sqlite` file from your data directory).  Old symbols files (already on disk) should still work fine after changing this setting, even if they don't show up in the web interface's Symfiles list.  Note: if `filesInDatabase` is set to `false`, and you are doing backups, you should back up your entire data directory (or, at least, the symbols/ directory) in addition to your database file.

## Contributing

Simple Breakpad Server is a work in progress and there is a lot to do. Send pull requests and issues on the project's [Github page](https://github.com/acrisci/simple-breakpad-server).

Here are some things to do:

* improve UI
* endpoint to delete crash reports
* group and filter crash reports
* script to create symfiles
* cli

## License

This project is open source and available to you under an [MIT license](https://github.com/acrisci/simple-breakpad-server/blob/master/LICENSE).
