kd           = require 'kd'
React        = require 'kd-react'

module.exports = class ProfileLink extends React.Component

  @defaultProps =
    onClick  : kd.noop


  getHref: ->
    if @props.account?.isIntegration
    then "/Admin/Integrations/Configure/#{@props.account.id}"
    else '#'


  render: ->
    <a href={@getHref()} onClick={@props.onClick} {...@props}>
      {@props.children}
    </a>
