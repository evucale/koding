kd = require 'kd'
JView = require 'app/jview'
Encoder = require 'htmlencode'
WizardSteps = require './wizardsteps'
WizardProgressPane = require './wizardprogresspane'
StackTemplateEditorView = require 'stacks/views/stacks/editors/stacktemplateeditorview'

module.exports = class StackTemplatePageView extends JView

  constructor: (options = {}, data) ->

    super options, data

    @progressPane = new WizardProgressPane
      currentStep : WizardSteps.Instructions

    { template: { rawContent } } = @getData()
    @editorView = new StackTemplateEditorView
      delegate    : this
      content     : Encoder.htmlDecode rawContent
      contentType : 'yaml'
      readOnly    : yes
      showHelpContent : no
    { ace }   = @editorView.aceView
    ace.ready => @editorView.resize()

    @backButton = new kd.ButtonView
      title    : 'Back to Read Me'
      cssClass : 'GenericButton secondary'
      callback : @lazyBound 'emit', 'ReadmeRequested'

    @nextButton = new kd.ButtonView
      title    : 'Next'
      cssClass : 'GenericButton'
      callback : @lazyBound 'emit', 'NextPageRequested'


  pistachio: ->

    '''
      <div class="build-stack-flow stack-template-page">
        <header>
          <h1>Build Your Stack</h1>
        </header>
        {{> @progressPane}}
        <section class="main">
          <h2>Stack Template</h2>
          <p>Your whole development environment in a text file</p>
          {{> @editorView}}
          {{> @backButton}}
        </section>
        <footer>
          {{> @nextButton}}
        </footer>
      </div>
    '''
