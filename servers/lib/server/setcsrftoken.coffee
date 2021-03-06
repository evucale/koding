KONFIG = require 'koding-config-manager'
{ v4: createId } = require 'node-uuid'

module.exports = (req, res, next) ->

  unless KONFIG.environment is 'production'
    res.header 'Access-Control-Allow-Origin', 'http://www.koding.com'

  next()  if req?.cookies?._csrf

  { maxAge, secure } = KONFIG.sessionCookie

  csrfToken = createId()
  # set cookie as pending cookie
  req.pendingCookies or= {}
  req.pendingCookies._csrf = csrfToken

  expires = new Date Date.now() + 360
  res.cookie '_csrf', csrfToken, { expires, secure }

  next()

