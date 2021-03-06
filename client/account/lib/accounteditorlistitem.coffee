kd                           = require 'kd'
KDCustomHTMLView             = kd.CustomHTMLView
KDListItemView               = kd.ListItemView
AccountEditorTags            = require './accounteditortags'
AccountsSwappable            = require './accountsswappable'
AccountEditorExtensionTagger = require './accounteditorextensiontagger'


module.exports = class AccountEditorListItem extends KDListItemView

  constructor: (options, data) ->
    options = { tagName : 'li' }
    super options, data

  viewAppended: ->
    super
    @form = form = new AccountEditorExtensionTagger
      delegate : this
      cssClass : 'posstatic'
    , @data.extensions

    @info = info = new AccountEditorTags
      cssClass : 'posstatic'
      delegate : this
    , @data.extensions

    info.addSubView new KDCustomHTMLView
      tagName  : 'a'
      partial  : 'Edit'
      cssClass : 'action-link'
      click    : @bound 'swapSwappable'

    @swappable = swappable = new AccountsSwappable
      views : [form, info]
      cssClass : 'posstatic'

    @addSubView swappable, '.swappable-wrapper'

    form.on 'FormCancelled', @bound 'swapSwappable'

  swapSwappable: ->
    @swappable.swapViews()

  partial: (data) ->
    """
      <span class='darkText'>#{data.title}</span>
    """
    # """
    #   <div class='labelish'>
    #     <span class="icon #{data.type}"></span>
    #     <span class='editor-method-title'>#{data.title}</span>
    #   </div>
    #   <div class='swappableish swappable-wrapper posstatic'></div>
    # """
