const path = require('path')
const express = require('express')
const mongoose = require('mongoose')
const logger = require('morgan')
const cookieParser = require('cookie-parser')
const session = require('cookie-session')
const bodyParser = require('body-parser')
const compression = require('compression')
const helmet = require('helmet')
const errorHandler = require('api-error-handler')
const passport = require('passport')
const LocalStrategy = require('passport-local').Strategy

const index = require('./routes')
const auth = require('./routes/auth')
const cors = require('cors')

const app = express()

app.get('/healthz', (req, res) => res.sendStatus(200))
app.get('/readyz', (req, res) =>
  res.sendStatus(mongoose.connection.readyState === 1 ? 200 : 503)
)

app.use(helmet())
app.use(compression())

app.use(
  cors({
    origin: (reqOrigin, callback) => {
      const whitelist = ['wishhack.xyz', 'localhost']
      if (whitelist.filter(w => reqOrigin && reqOrigin.includes(w))) {
        callback(null, true)
      } else {
        callback(new Error('Now Allowed by CORS'))
      }
    },
    credentials: true
  })
)

app.use(logger('dev'))
app.use(bodyParser.json())
app.use(bodyParser.urlencoded({ extended: false }))
app.use(cookieParser())

app.use(session({ keys: [process.env.cookieSigningKey || 'secretkey1'] }))

app.use(passport.initialize())
app.use(passport.session())

const Account = require('./db/Account')

passport.use(new LocalStrategy(Account.authenticate()))

passport.serializeUser(Account.serializeUser())
passport.deserializeUser(Account.deserializeUser())

require('./db/bootstrap-mongoose')

const uiBuildDir = process.env.UI_BUILD_DIR

if (uiBuildDir) {
  app.use(express.static(uiBuildDir))
}

app.use('/', index)
app.use('/auth', auth)

if (uiBuildDir) {
  app.get('*', (req, res, next) =>
    req.accepts('html')
      ? res.sendFile(path.join(uiBuildDir, 'index.html'))
      : next()
  )
}

// catch 404 and forward to error handler
app.use((req, res, next) => {
  var err = new Error('Not Found')
  err.status = 404
  next(err)
})

// error handler
app.use(errorHandler())

if (process.env.NODE_ENV !== 'test') {
  app.set('port', process.env.PORT || 3002)
  const server = app.listen(app.get('port'), function() {
    console.log('Express server listening on port ' + server.address().port)
  })
}

module.exports = app
