{EventEmitter} = require 'microemitter'

module.exports = class AuthWorker extends EventEmitter

  AuthedClient = require './authedclient'

  AUTH_EXCHANGE_OPTIONS =
    type        : 'fanout'
    autoDelete  : yes

  REROUTING_EXCHANGE_OPTIONS =
  USERS_PRESENCE_CONTROL_EXCHANGE_OPTIONS =
    type        : 'fanout'
    autoDelete  : yes

  NOTIFICATION_EXCHANGE_OPTIONS =
    type        : 'topic'
    autoDelete  : yes

  constructor: (@bongo, options = {}) ->

    # instance options
    { @servicesPresenceExchange, @reroutingExchange
      @notificationExchange, @usersPresenceControlExchange
      @presenceTimeoutAmount, @authExchange, @authAllExchange } = options

    # initialize defaults:
    @servicesPresenceExchange     ?= 'services-presence'
    @usersPresenceControlExchange ?= 'users-presence-control'
    @reroutingExchange            ?= 'routing-control'
    @notificationExchange         ?= 'notification'
    @authExchange                 ?= 'auth'
    @authAllExchange              ?= 'authAll'
    @presenceTimeoutAmount        ?= 1000 * 60 * 2 # 2 min

    # instance state
    @services         = {}
    @clients          =
      bySocketId      : {}
      byExchange      : {}
      byRoutingKey    : {}
    @usersBySocketId  = {}
    @counts           = {}
    @waitingAuthWhos  = {}

  bound: require 'koding-bound'

  authenticate: (messageData, routingKey, socketId, callback) ->
    {clientId, channel, event} = messageData
    @requireSession clientId, routingKey, socketId, callback

  requireSession: (clientId, routingKey, socketId, callback) ->
    {JSession} = @bongo.models
    JSession.fetchSession clientId, (err, { session }) =>
      if err? then console.error err
      if err? or not session? then @rejectClient routingKey
      else
        @addUserSocket session.username, socketId  if session.username?
        tokenHasChanged = session.clientId isnt clientId
        @updateSessionToken session.clientId, routingKey  if tokenHasChanged
        callback session

  addUserSocket: (username, socketId) ->
    @usersBySocketId[socketId] = username
    @fetchUserPresenceControlExchange (exchange) ->
      exchange.publish 'auth.join', { username, socketId }

  removeUserSocket: (socketId) ->
    username = @usersBySocketId[socketId]
    return  unless username
    delete @usersBySocketId[username]
    @fetchUserPresenceControlExchange (exchange) ->
      exchange.publish 'auth.leave', { username, socketId }

  updateSessionToken: (clientId, routingKey) ->
    @bongo.respondToClient routingKey,
      method      : 'updateSessionToken'
      arguments   : [clientId]
      callbacks   : {}

  getNextServiceInfo: (serviceType) ->
    count = @counts[serviceType] ?= 0
    servicesOfType = @services[serviceType]
    return  unless servicesOfType?.length
    serviceInfo = servicesOfType[count % servicesOfType.length]
    @counts[serviceType] += 1
    return serviceInfo

  addService: ({serviceGenericName, serviceUniqueName, loadBalancing}) ->
    servicesOfType = @services[serviceGenericName] ?= []
    servicesOfType.push {serviceUniqueName, serviceGenericName, loadBalancing}

  removeService: ({serviceGenericName, serviceUniqueName}) ->
    servicesOfType = @services[serviceGenericName]
    [index] = (i for s, i in servicesOfType \
                 when s.serviceUniqueName is serviceUniqueName)
    servicesOfType.splice index, 1
    clientsByExchange = @clients.byExchange[serviceUniqueName]
    clientsByExchange?.forEach @bound 'cycleClient'

  cycleClient: (client) ->
    {routingKey} = client
    @bongo.respondToClient routingKey,
      method      : 'cycleChannel'
      arguments   : []
      callbacks   : {}

  removeClient: (rest...) ->
    if rest.length is 1
      [client] = rest
      return @removeClient client.socketId, client.exchange, client.routingKey
    [socketId, exchange, routingKey] = rest
    delete @clients.bySocketId[socketId]
    delete @clients.byExchange[exchange]
    delete @clients.byRoutingKey[routingKey]

  addClient: (socketId, exchange, routingKey, sendOk=yes) ->
    if sendOk
      @bongo.respondToClient routingKey,
        method    : 'auth.authOk'
        arguments : []
        callbacks : {}
    clientsBySocketId   = @clients.bySocketId[socketId]     ?= []
    clientsByExchange   = @clients.byExchange[exchange]     ?= []
    clientsByRoutingKey = @clients.byRoutingKey[routingKey] ?= []
    client = new AuthedClient { routingKey, socketId, exchange }
    clientsBySocketId.push client
    clientsByRoutingKey.push client
    clientsByExchange.push client

  rejectClient:(routingKey, message)->
    # console.log 'rejecting', routingKey
    return console.trace()  unless routingKey?
    @bongo.respondToClient routingKey,
      method    : 'error'
      arguments : [message: message ? 'Access denied']
      callbacks : {}

  setSecretNames:(routingKey, publishingName, subscribingName)->
    setSecretNamesEvent = "#{routingKey}.setSecretNames"
    message = JSON.stringify { publishingName, subscribingName }
    @bongo.respondToClient setSecretNamesEvent, message

  publishToService: (exchangeName, routingKey, payload, callback) ->
    { connection } = @bongo.mq
    connection.exchange exchangeName, AUTH_EXCHANGE_OPTIONS,
      (exchange) =>
        exchange.publish routingKey, payload
        exchange.close() # don't leak a channel
        callback? null

  sendAuthMessage: (options) ->
    { serviceUniqueName, serviceGenericName, routingKey, method, callback
    username, correlationName, socketId, deadService } = options

    params = {
      routingKey, username, correlationName
      serviceGenericName, deadService
      replyExchange: @authExchange
    }

    @publishToService serviceUniqueName, method, params, callback

  sendAuthJoin: (options) ->
    { socketId, serviceUniqueName, routingKey } = options
    options.callback = =>
      key = getWaitingAuthWhoKey options
      socketId ?= @waitingAuthWhos[key]
      delete @waitingAuthWhos[key]
      @addClient socketId, serviceUniqueName, routingKey
    options.method = 'auth.join'
    @sendAuthMessage options

  getWaitingAuthWhoKey = (o) ->
    "#{o.username}!#{o.correlationName}!#{o.serviceGenericName}"

  sendAuthWho: (options) ->
    options.method = 'auth.who'
    @waitingAuthWhos[getWaitingAuthWhoKey options] = options.socketId
    @sendAuthMessage options

  fetchReroutingExchange:(callback)->
    @bongo.mq.connection.exchange(
      @reroutingExchange
      REROUTING_EXCHANGE_OPTIONS
      callback
    )

  makeExchangeFetcher =(exchangeName, exchangeOptions)->
    exKey   = "#{exchangeName}_"
    (callback)->
      if @[exKey] then return process.nextTick => callback @[exKey]
      @bongo.mq.connection.exchange(
        @[exchangeName]
        exchangeOptions
        (exchange)=> callback @[exKey] = exchange
      )

  fetchReroutingExchange: makeExchangeFetcher(
    'reroutingExchange', REROUTING_EXCHANGE_OPTIONS
  )

  fetchNotificationExchange: makeExchangeFetcher(
    'notificationExchange', NOTIFICATION_EXCHANGE_OPTIONS
  )

  fetchUserPresenceControlExchange: makeExchangeFetcher(
    'usersPresenceControlExchange', USERS_PRESENCE_CONTROL_EXCHANGE_OPTIONS
  )

  addBinding:(bindingExchange, bindingKey, publishingExchange, routingKey, suffix = '')->
    suffix = ".#{suffix}"  if suffix.length
    @fetchReroutingExchange (exchange)=>
      exchange.publish 'auth.join', {
        bindingExchange
        bindingKey
        publishingExchange
        routingKey
        suffix
      }

  _fakePersistenceWorker:(secretChannelName)->
    { connection } = @bongo.mq
    options = {type: 'fanout', autoDelete: yes, durable: no}
    connection.exchange secretChannelName, options, (exchange)->
      connection.queue '', {autoDelete: yes, durable: no, exclusive: yes}, (queue)->
        queue.bind exchange, '#'
        queue.on 'queueBindOk', ->
          queue.subscribe (message)->
            console.log message.data+''

  notify:(routingKey, event, contents)->
    @fetchNotificationExchange (exchange)->
      exchange.publish routingKey, { event, contents }

  respondServiceUnavailable: (routingKey, serviceGenericName) ->
    @bongo.respondToClient routingKey,
      method    : 'error'
      arguments : [{
        message : "Service unavailable! #{routingKey}"
        code    :503
        serviceGenericName
      }]
      callbacks : {}

  join: do ->

    joinHelper = (messageData, routingKey, socketId) ->
      @authenticate messageData, routingKey, socketId, (session) =>

        serviceInfo = @getNextServiceInfo messageData.name

        unless serviceInfo?
          {name} = messageData
          @respondServiceUnavailable routingKey, name
          return console.error "No service info! #{name}"

        { serviceUniqueName, serviceGenericName, loadBalancing } = serviceInfo

        if messageData.serviceType is 'kite' and not messageData.correlationName
          console.warn "No correlation name!", messageData, routingKey

        params = {
          serviceGenericName
          serviceUniqueName
          routingKey
          username        : session.username ? 'guest'
          correlationName : messageData.correlationName
          # maybe the callback wants this:
          socketId
        }
        if loadBalancing
        then @sendAuthWho params
        else if serviceUniqueName?
        then @sendAuthJoin params
        else @respondServiceUnavailable routingKey, serviceGenericName


    ensureGroupPermission = ({group, account}, callback) ->
      {JGroup} = @bongo.models
      checkGroupPermission.call this, group, account, (err, hasPermission) ->
        if err then callback err
        else if hasPermission
          JGroup.fetchSecretChannelName group.slug, callback
        else
          callback {message: 'Access denied!', code: 403}

    ensureSocialapiChannelPermission = ({group, account, options}, callback) ->
      {SocialChannel} = @bongo.models
      checkGroupPermission.call this, group, account, (err, hasPermission) ->
        if err then callback err
        else if hasPermission
          SocialChannel.fetchSecretChannelName options, callback
        else
          callback {message: 'Access denied!', code: 403}

    checkGroupPermission = (group, account, callback) ->
      {JPermissionSet, JGroup, SocialChannel} = @bongo.models
      client = {context: {group: group.slug}, connection: delegate: account}
      JPermissionSet.checkPermission client, "read group activity", group,
        callback

    joinGroupHelper =(messageData, routingKey, socketId)->
      {JAccount, JGroup} = @bongo.models
      fail = (err) =>
        console.error err  if err
        @rejectClient routingKey
      @authenticate messageData, routingKey, socketId, (session) =>
        unless session then fail()
        fetchAccountAndGroup.call this, session.username, messageData.group,
          (err, data)=>
            return fail err  if err
            {account, group} = data
            ensureGroupPermission.call this, {group, account},
              (err, secretChannelName) =>
                if err or not secretChannelName
                  @rejectClient routingKey
                else
                  handleSecretnameAndRoutingKey.call this,
                    routingKey,
                    secretChannelName

    handleSecretnameAndRoutingKey = (routingKey, secretChannelName)->
      @addBinding 'broadcast', secretChannelName, 'broker', routingKey
      @setSecretNames routingKey, secretChannelName

    fetchAccountAndGroup= (username, groupSlug, callback)->
      {JAccount, JGroup} = @bongo.models
      JAccount.one {'profile.nickname': username},
        (err, account) ->
          return callback err  if err
          return callback {message: "Account not found"}  if not account
          JGroup.one {slug: groupSlug}, (err, group) ->
            return callback err  if err
            return callback {message: "Group not found"}  if not group
            return callback null, {account, group}

    joinSocialApiHelper =(messageData, routingKey, socketId)->
      {JAccount, JGroup, SocialChannel} = @bongo.models
      fail = (err) =>
        console.error err  if err
        @rejectClient routingKey
      @authenticate messageData, routingKey, socketId, (session) =>
        return fail()  unless session
        fetchAccountAndGroup.call this, session.username, messageData.group,
          (err, data)=>
            return fail err  if err
            {account, group} = data

            options =
              groupSlug      : group.slug
              apiChannelType : messageData.channelType
              apiChannelName : messageData.channelName

            ensureSocialapiChannelPermission.call this, {
              group,
              account,
              options
            } , (err, secretChannelName)=>
              return fail err if err
              unless secretChannelName
                return fail {message: "secretChannelName not set"}
              handleSecretnameAndRoutingKey.call this,
                routingKey,
                secretChannelName

    joinNotificationHelper =(messageData, routingKey, socketId)->
      fail = (err)=>
        console.error err  if err
        @rejectClient routingKey

      @authenticate messageData, routingKey, socketId, (session)=>
        unless session then fail()
        else if session?.username
          @addClient socketId, @reroutingExchange, routingKey, no
          bindingKey = session.username
          @addBinding 'notification', bindingKey, 'broker', routingKey
        else
          @rejectClient routingKey

    joinChatHelper =(messageData, routingKey, socketId)->
      {name} = messageData
      {JName} = @bongo.models
      fail = => @rejectClient routingKey
      @authenticate messageData, routingKey, socketId, (session)=>
        return fail()  unless session?.username?
        JName.fetchSecretName name, (err, secretChannelName)=>
          return console.error err  if err

          personalToken = 'pt' + do require 'hat'

          bindingKey          = "client.#{personalToken}"
          consumerRoutingKey  = "chat.#{secretChannelName}"

          {username} = session

          @addBinding 'chat', bindingKey, 'chat-hose', consumerRoutingKey, username

          # @_fakePersistenceWorker secretChannelName
          @notify username, 'chatOpen', {
            publicName  : name
            routingKey  : personalToken
            bindingKey  : consumerRoutingKey
          }

    joinClient =(messageData, socketId)->
      { routingKey, brokerExchange, serviceType, wrapperRoutingKeyPrefix } = messageData

      switch serviceType
        when 'bongo', 'kite'
          joinHelper.call this, messageData, routingKey, socketId

        when 'group'
          unless ///^group\.#{messageData.group}\.///.test routingKey
            return @rejectClient routingKey
          joinGroupHelper.call this, messageData, routingKey, socketId

        when 'socialapi'
          unless ///^socialapi\.///.test routingKey
            return @rejectClient routingKey
          joinSocialApiHelper.call this, messageData, routingKey, socketId

        when 'chat'
          joinChatHelper.call this, messageData, routingKey, socketId

        when 'notification'
          unless ///^notification\.///.test routingKey
            return @rejectClient routingKey
          joinNotificationHelper.call this, messageData, routingKey, socketId

        when 'secret'
          @addClient socketId, 'routing-control', wrapperRoutingKeyPrefix, no

        else
          @rejectClient routingKey  unless /^oid./.test routingKey
          # TODO: we're not really handling the oid channels at all (I guess we don't need to) C.T.

  cleanUpClient: (client) ->
    @removeClient client
    @bongo.mq.connection.exchange client.exchange, AUTH_EXCHANGE_OPTIONS,
      (exchange) ->
        exchange.publish 'auth.leave', { routingKey: client.routingKey }
        exchange.close() # don't leak a channel!

  cleanUpAfterDisconnect: (socketId) ->
    @removeUserSocket socketId
    clientServices = @clients.bySocketId[socketId]
    clientServices?.forEach @bound 'cleanUpClient'

  parseServiceKey = (serviceKey) ->
    last = null
    serviceInfo = serviceKey.split('.').reduce (acc, edge, i)->
      unless i % 2 then last = edge
      else acc[last] = edge
      return acc
    , {}
    serviceInfo.loadBalancing = /\.loadBalancing$/.test serviceKey
    isValidKey  = serviceInfo.serviceGenericName? and
                  serviceInfo.serviceUniqueName?
    throw {
      message: 'Bad service key!'
      serviceKey
      serviceInfo
    }  unless isValidKey

    return serviceInfo

  monitorPresence: (connection) ->
    Presence = require 'koding-rabbit-presence'
    @presence = new Presence {
      connection
      exchange  : @servicesPresenceExchange
      member    : @resourceName
    }
    @presence.on 'join', (serviceKey) =>
      try @addService parseServiceKey serviceKey
      catch e then console.error e
    @presence.on 'leave', (serviceKey) =>
      try @removeService parseServiceKey serviceKey
      catch e then console.error e
    @presence.listen()

  handleKiteWho: (messageData, socketId) ->
    { serviceGenericName, serviceUniqueName, routingKey
      correlationName, username } = messageData

    # apparently auth worker can spam the terminal
    # kite with requests for kite.who for guest accounts.
    # this short-cicuiting is meant to prevent against that,
    # but since I couldn't reproduce this problem locally, 
    # it is possible that this is not a sufficient fix. C.T.
    return  if /^guest-\d+/.test username

    params = {
      serviceGenericName
      serviceUniqueName
      routingKey
      correlationName
      username
    }

    servicesOfType = @services[serviceGenericName]

    [matchingService] = (service for service in servicesOfType \
                                 when service.serviceUniqueName \
                                   is serviceUniqueName)
    if matchingService?
      @sendAuthJoin params
    else unless serviceUniqueName is "(error)"
      params.deadService = serviceUniqueName
      serviceInfo = @getNextServiceInfo serviceGenericName
      params.serviceUniqueName = serviceInfo.serviceUniqueName
      @sendAuthWho params

  connect: ->
    {bongo} = this
    bongo.mq.ready =>
      {connection} = bongo.mq
      @monitorPresence connection

      # FIXME: this is a hack to hold the chat exchange open for the meantime
      connection.exchange 'chat', NOTIFICATION_EXCHANGE_OPTIONS, (chatExchange) ->
        # *chirp chirp chirp chirp*

      connection.exchange @authAllExchange, AUTH_EXCHANGE_OPTIONS, (authAllExchange) =>
        connection.queue '', {exclusive:yes}, (authAllQueue) =>
          authAllQueue.bind authAllExchange, ''
          authAllQueue.on 'queueBindOk', =>
            authAllQueue.subscribe (message, headers, deliveryInfo) =>
              {routingKey} = deliveryInfo
              messageStr = "#{message.data}"
              switch routingKey
                when 'broker.clientConnected' then # ignore
                when 'broker.clientDisconnected'
                  @cleanUpAfterDisconnect messageStr

      connection.exchange @authExchange, AUTH_EXCHANGE_OPTIONS, (authExchange) =>
        connection.queue  @authExchange, (authQueue)=>
          authQueue.bind authExchange, ''
          authQueue.on 'queueBindOk', =>
            authQueue.subscribe (message, headers, deliveryInfo) =>
              {routingKey, correlationId} = deliveryInfo
              socketId = correlationId
              messageStr = "#{message.data}"
              messageData = (try JSON.parse messageStr) or message
              switch routingKey
                when 'kite.join'
                  @addService messageData
                when 'kite.leave'
                  @removeService messageData
                when 'kite.who'
                  @handleKiteWho messageData
                when "client.#{@authExchange}"
                  @join messageData, socketId
                else
                  @rejectClient routingKey
