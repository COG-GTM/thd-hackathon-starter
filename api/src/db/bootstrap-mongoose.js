const mongoose = require('mongoose')

const mongoDB = process.env.mongoUrl

if (!mongoDB) {
  throw new Error('mongoUrl environment variable must be set (including credentials)')
}

mongoose.connect(mongoDB, { useNewUrlParser: true })

const db = mongoose.connection

db.on('error', console.error.bind(console, 'MongoDB connection error:'))
