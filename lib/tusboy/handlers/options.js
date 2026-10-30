const cors = require('cors')
const { ALLOWED_HEADERS, ALLOWED_METHODS, MAX_AGE } = require ('../constants');

const tusExtension = (extensions = []) => {
  if (!extensions.length) {
    return (req, res, next) => next()
  }
  return (req, res, next) => {
    res.set('Tus-Extension', extensions.join(','))
    next()
  }
}

const corsPreflight = (extraMethods, origin) => cors({
  origin,
  methods: [...ALLOWED_METHODS, ...extraMethods],
  allowedHeaders: ALLOWED_HEADERS,
  maxAge: MAX_AGE,
})

module.exports = (extensions, extraMethods = [], origin = false) => ([
  tusExtension(extensions),
  corsPreflight(extraMethods, origin),
])
