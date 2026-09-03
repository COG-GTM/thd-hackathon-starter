const crypto = require('crypto')

const MIN_KEY_LENGTH = 32

// Reads the cookie-session signing keys from `cookieSigningKey`.
// Multiple keys may be supplied comma-separated (newest first) to rotate keys.
// There is deliberately no hardcoded fallback: a known signing key lets anyone
// forge a session cookie for any username.
function getSessionKeys(env = process.env) {
  const keys = (env.cookieSigningKey || '')
    .split(',')
    .map(k => k.trim())
    .filter(Boolean)

  if (keys.length > 0) {
    const short = keys.find(k => k.length < MIN_KEY_LENGTH)
    if (short !== undefined) {
      throw new Error(
        `cookieSigningKey entries must be at least ${MIN_KEY_LENGTH} characters long`
      )
    }
    return keys
  }

  if (env.NODE_ENV === 'production') {
    throw new Error(
      'cookieSigningKey environment variable must be set in production'
    )
  }

  console.warn(
    'cookieSigningKey is not set; using a random per-process session key. ' +
      'Sessions will not survive restarts. Set cookieSigningKey to persist them.'
  )
  return [crypto.randomBytes(32).toString('hex')]
}

module.exports = { getSessionKeys, MIN_KEY_LENGTH }
