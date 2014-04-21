# account and models will be removed.
{argv}              = require 'optimist'
{uri, client}       = require('koding-config-manager').load("main.#{argv.c}")
{getAvatarImageUrl} = require '../helpers'

getDock = ->
  """
  <header id="main-header" class="kdview">
      <div class="inner-container">
          <a id="koding-logo" href="/">
              <cite></cite>
          </a>
          <div id="dock" class="">
              <div id="main-nav" class="kdview kdlistview kdlistview-navigation">
                  <a class="kdview kdlistitemview kdlistitemview-main-nav activity kddraggable running" href="/Activity" style="left: 0px;">
                      <span class="icon"></span>
                      <cite>Activity</cite>
                  </a>
                  <a class="kdview kdlistitemview kdlistitemview-main-nav teamwork kddraggable" href="/Teamwork" style="left: 55px;">
                      <span class="icon"></span>
                      <cite>Teamwork</cite>
                  </a>
                  <a class="kdview kdlistitemview kdlistitemview-main-nav terminal kddraggable" href="/Terminal" style="left: 110px;">
                      <span class="icon"></span>
                      <cite>Terminal</cite>
                  </a>
                  <a class="kdview kdlistitemview kdlistitemview-main-nav editor kddraggable" href="/Ace" style="left: 165px;">
                      <span class="icon"></span>
                      <cite>Editor</cite>
                  </a>
                  <a class="kdview kdlistitemview kdlistitemview-main-nav apps kddraggable" href="/Apps" style="left: 220px;">
                      <span class="icon"></span>
                      <cite>Apps</cite>
                  </a>
              </div>
          </div>
      </div>
  </header>
  """

getSingleActivityPage = ({activityContent, account, models})->
  {Relationship} = require 'jraphical'
  getStyles      = require './styleblock'
  getGraphMeta   = require './graphmeta'
  analytics      = require './analytics'
  model          = models.first if models and Array.isArray models

  title  = activityContent?.title
  """

  <!DOCTYPE html>
  <html lang="en">
  <head>
    <title>#{title} - Koding</title>
    #{getGraphMeta()}
  </head>
    <body itemscope itemtype="http://schema.org/WebPage">
      #{getDock()}
      <section id="main-panel-wrapper" class="kdview">
          <div id="main-tab-view" class="kdview kdscrollview kdtabview">
            <div class="kdview kdtabpaneview activity clearfix content-area-pane active">

              <div id="content-page" class="kdview kdscrollview content-page">
                <main class="">
                  <div class="kdview activity-content feeder-tabs">
                    <div class="kdview listview-wrapper">
                      <div class="kdview kdscrollview">
                        <div class="kdview kdlistview kdlistview-default activity-related">
                          <div></div>
                          <div class="kdview kdscrollview content-display activity-related status">
                            #{getSingleActivityContent(activityContent, model)}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </main>
              </div>
            </div>
          </div>
        </section>
        #{analytics()}
    </body>
  </html>
  """


createCommentNode = (comment)->
  commentContent = ""
  if comment.body
    commentContent =
    """
    <li itemtype="http://schema.org/Comment" itemscope itemprop="comment">
        <span itemprop="commentText">#{comment.body}</span> - at
        <span itemprop="commentTime">#{comment.createdAt}</span> by
        <a href="#{uri.address}/#{comment.authorNickname}"><span itemprop="name">#{comment.authorName}</span></a>
    </li>
    """
  return commentContent

createAccountName = (fullName)->
  return "#{fullName}"

createAvatarImage = (hash, avatar)=>
  imgURL = getAvatarImageUrl hash, avatar
  """
  <img width="70" height="70" src="#{imgURL}" style="opacity: 1;" itemprop="image" />
  """

createCreationDate = (createdAt, url="")->
  """
    <a href='#{url}' class=><time>Created at: <span itemprop=\"dateCreated\">#{createdAt}</span></time></a>
  """

createCommentsCount = (numberOfComments)->
  content = ""
  if numberOfComments > 0
    content =  "<span>#{numberOfComments}</span>"
  return content

createLikesCount = (numberOfLikes)->
  content = ""
  if numberOfLikes > 0
    content = "<span>#{numberOfLikes}</span>"
  return content

createAuthor = (accountName, nickname)->
  return "<a href=\"#{uri.address}/#{nickname}\"><span itemprop=\"name\">#{accountName}</span></a>"

createUserInteractionMeta = (numberOfLikes, numberOfComments)->
  userInteractionMeta = "<meta itemprop=\"interactionCount\" content=\"UserLikes:#{numberOfLikes}\"/>"
  userInteractionMeta += "<meta itemprop=\"interactionCount\" content=\"UserComments:#{numberOfComments}\"/>"
  return userInteractionMeta

getSingleActivityContent = (activityContent, model)->
  slugWithDomain = "#{uri.address}/Activity/#{activityContent.slug}"
  body          = activityContent.body
  nickname      = activityContent.nickname
  accountName   = createAccountName activityContent.fullName
  avatarImage   = createAvatarImage activityContent.hash, activityContent.avatar
  createdAt     = createCreationDate activityContent.createdAt, slugWithDomain
  commentsCount = createCommentsCount activityContent.numberOfComments
  likesCount    = createLikesCount activityContent.numberOfLikes
  author        = createAuthor accountName, nickname

  userInteractionMeta = createUserInteractionMeta \
    activityContent.numberOfLikes, activityContent.numberOfComments

  commentsList = ""
  if activityContent?.comments
    for comment in activityContent.comments
      avatarUrl = getAvatarImageUrl comment.authorHash, false
      commentsList +=
        """
          <div class="kdview kdlistitemview kdlistitemview-comment">
            <a class="avatarview online" href="/#{comment.authorNickname}" style="width: 40px; height: 40px; background-size: 40px; background-image: none;"><img class="" width="40" height="40" src="#{avatarUrl}" style="opacity: 1;"></a>
            <div class="comment-contents clearfix" itemscope itemtype="http://schema.org/UserComments">
              <a class="profile" href="/#{comment.authorNickname}" itemprop="name">#{comment.authorName}</a>
              <div class="comment-body-container"><p itemprop="commentText">#{comment.body}</p></div>
            </div>
          </div>
        """

  commentsContent =
    """
      <div class="kdview comment-container commented">
        <div class="kdview listview-wrapper">
          <div class="kdview kdscrollview">
            <div class="kdview kdlistview kdlistview-comments">
              #{commentsList}
            </div>
          </div>
        </div>
      </div>
    """

  tags = ""
  if activityContent?.tags?.length > 0
    tags = "tags: "
    for tag in activityContent.tags
      content =
        """
          <a href="#{uri.address}/Topics/#{tag.slug}">#{tag.title}</a>
        """
      tags += content

  shortenedTitle = activityContent.title
  if shortenedTitle?.length > 150
    shortenedTitle = activityContent.title.substring(0, 150) + "..."
  title =
    """
      <a href="#{slugWithDomain}">#{shortenedTitle}</a>
    """

  content  =
    """
      <div class="kdview activity-item status">
          <a class="avatarview author-avatar" href="#{uri.address}/#{nickname}" style="width: 70px; height: 70px; background-size: 70px; background-image: none;">
              #{avatarImage}
          </a>

          <a class="profile" href="#{uri.address}/#{nickname}">
            <span data-paths="profile.firstName profile.lastName" itemscope itemtype="http://schema.org/person" title="#{accountName}">
              #{accountName}
            </span>
          </a>

          <article data-paths="body">
            <p>
              #{body}
            </p>
          </article>

          <footer>
              #{userInteractionMeta}
              <div class="kdview comment-header activity-actions">
                  <span class="kdview logged-in action-container"><a class="action-link" href="/Login?warning=1&type=like">Like</a>
                      <a class="count" href="/Login?warning=1&type=like">
                          <span data-paths="meta.likes">#{likesCount}</span>
                      </a>
                  </span>
                  <span class="logged-in action-container">
                      <a class="action-link" href="/Login?warning=1&type=comment">Comment</a>
                      <a class="count" href="/Login?warning=1&type=comment">
                          <span data-paths="repliesCount" >#{commentsCount}</span>
                      </a>
                  </span>
              </div>
              #{createdAt}
          </footer>
          #{commentsContent}
      </div>
    """
  return content

module.exports = {
  getSingleActivityPage
  getSingleActivityContent
}
