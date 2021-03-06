kd                     = require 'kd'
JView                  = require 'app/jview'
isKoding               = require 'app/util/isKoding'
AvatarStaticView       = require 'app/commonviews/avatarviews/avatarstaticview'
getFullnameFromAccount = require 'app/util/getFullnameFromAccount'


# a user be a Member, Admin and Owner at the same time but in the UI we should
# show the role name which has the most permissions.
defaultRoles  =
  member      : { slug: 'member',    label: 'Member',    buttonTitle: 'MAKE MEMBER',    priority: 1 }
  moderator   : { slug: 'moderator', label: 'Moderator', buttonTitle: 'MAKE MODERATOR', priority: 2 }
  admin       : { slug: 'admin',     label: 'Admin',     buttonTitle: 'MAKE ADMIN',     priority: 3 }
  owner       : { slug: 'owner',     label: 'Owner',     buttonTitle: 'MAKE OWNER',     priority: 4 }


{ member, moderator, admin, owner } = defaultRoles
kick = { slug: 'kick', buttonTitle: 'DISABLE USER', extraClass: 'red' }

buttonSet     =
  owner       :
    member    : [ owner, admin, moderator, kick  ]
    moderator : [ owner, admin, member, kick     ]
    admin     : [ owner, moderator, member, kick ]
    owner     : [ member ]
  admin       :
    member    : [ admin, moderator, kick  ]
    moderator : [ admin, member, kick     ]
    admin     : [ moderator, member, kick ]
    owner     : []


module.exports = class MemberItemView extends kd.ListItemView

  JView.mixin @prototype

  constructor: (options = {}, data) ->

    options.type or= 'member'

    super options, data

    @actionButtons    = {}
    @loggedInUserRole = @getRole data.loggedInUserRoles
    @memberRole       = @getRole data.roles

    @avatar = new AvatarStaticView
      size : { width: 40, height : 40 }
    , @getData()

    @roleLabel = new kd.CustomHTMLView
      cssClass : 'role'
      partial  : "#{@memberRole.label} <span class='settings-icon'></span>"
      click    : @bound 'toggleSettings'

    @createSettingsView()

    @on 'UserRoleChangeRequested', (role) =>
      if role is 'kick' then @kick() else @handleRoleChange role


  getRole: (userRoles) ->

    currentRole = defaultRoles.member

    # find the most prioritized role
    for userRole in userRoles when role = defaultRoles[userRole]
      currentRole = role  if role.priority > currentRole.priority

    return currentRole


  createSettingsView: ->

    unless @settings
      @settings  = new kd.CustomHTMLView
        cssClass : 'settings hidden'

    set     = buttonSet[@loggedInUserRole.slug]
    buttons = if set then (set[@memberRole.slug] ? []) else []

    buttons.forEach (button) =>

      buttonView = new kd.ButtonView
        cssClass : kd.utils.curry 'solid compact outline', button.extraClass
        title    : button.buttonTitle
        loader   : { color: '#444444' }
        callback : => @emit 'UserRoleChangeRequested', button.slug

      @actionButtons[button.slug] = buttonView
      @settings.addSubView buttonView


  handleRoleChange: (newRole) ->

    oldRole  = @memberRole
    button   = @actionButtons[newRole]
    jAccount = @getData()

    return button.hideLoader()  if @isInProgress

    @isInProgress = yes

    group    = kd.singletons.groupsController.getCurrentGroup()
    newRoles = [ newRole ]

    newRoles.push 'admin'  if newRole is 'owner'

    group.changeMemberRoles jAccount.getId(), newRoles, (err, response) =>
      return @handleError button, err  if err

      group.fetchUserRoles [ jAccount.getId() ], (err, roles) =>

        return @handleError button, err  if err

        data        = @getData()
        data.roles  = (role.as for role in roles)
        @memberRole = @getRole data.roles

        @handleRoleChangeOnUI @memberRole.label
        @emit 'MemberRoleChanged', oldRole, @memberRole

        @isInProgress = no


  handleRoleChangeOnUI: (roleLabel) ->

    @roleLabel.updatePartial "#{roleLabel} <span class='settings-icon'></span>"
    @settings.destroySubViews()
    @createSettingsView()


  handleError: (button, err) ->

    @isInProgress = no

    if err?.message is 'Access denied'
      return global.location.href = '/Activity'

    button.hideLoader()

    message = switch
      when err?.name is 'UserIsTheOnlyAdmin'
        "Failed to change user role as you're the only admin of this team."
      when err?.message
        err.message
      else
        'Failed to change user role. Please try again.'

    return new kd.NotificationView { title: message, duration: 5000 }


  kick: ->

    currentGroup = kd.singletons.groupsController.getCurrentGroup()
    account      = @getData()
    group        = account._currentGroup ? currentGroup

    return  if isKoding group

    group.kickMember account.getId(), (err) =>

      if err
        customErr = new Error 'Failed to kick user. Please try again.'
        return @handleError @actionButtons.kick, customErr

      @destroy()
      @emit 'UserKicked'


  toggleSettings: ->

    @settings.toggleClass  'hidden'
    @roleLabel.toggleClass 'active'


  pistachio: ->
    data     = @getData()
    fullname = getFullnameFromAccount data
    nickname = data.profile.nickname
    email    = data.profile.email

    return """
      <div class="details">
        {{> @avatar}}
        <p class="fullname">#{fullname}</p>
        <p class="nickname">@#{nickname}</p>
      </div>
      <p title="#{email}" class="email">#{email}</p>
      {{> @roleLabel}}
      <div class='clear'></div>
      {{> @settings}}
    """
