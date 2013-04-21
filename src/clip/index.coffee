bindable = require "bindable"
dref     = require "dref"
events   = require "events"
defaultModifiers = require "./modifiers"
findRefs = require "./utils/findRefs"

###
 Reads a property chain 
###

class PropertyChain

  __isPropertyChain: true

  constructor: (@watcher) ->
    @_commands = []
    @clip = @watcher.clip

  ref: (path) ->
    @_commands.push { ref: path }
    @

  castAs: (name) ->
    @watcher.cast[name] = @
    @

  path: () ->
    path = []
    for c in @_commands
      path.push c.ref

    path.join(".")


  self: (path) ->
    @_self = true
    @ref path
    @

  call: (path, args) -> 
    @_commands.push { ref: path, args: args }
    @

  exec: () ->
    @currentValue = @value()
    @

  value: (value) ->
    hasValue = arguments.length

    cv = if @_self then @clip else @clip.data
    n = @_commands.length

    for command, i in @_commands

      @watcher._watch command.ref, cv

      if i is n-1 and hasValue
        if cv.set then cv.set(command.ref, value) else dref.set cv, command.ref, value

      pv = cv
      cv = if cv.get then cv.get(command.ref) else dref.get cv, command.ref
      
      # reference
      if command.args
        if cv and typeof cv is "function"
          cv = cv?.apply pv, command.args
        else
          cv = undefined

      break if not cv

    #modifier(ref.value(), modifier(anotherRef.value()))
    @watcher.currentRef = @

    return cv


class ClipScript extends events.EventEmitter

  ###
  ###

  constructor: (@script, @clip) ->
    @modifiers = @clip.modifiers
    @defaultModifiers = defaultModifiers
    @options = @clip.options
    @_watching = {}
    @cast = {}

  ###
  ###

  dispose: () ->
    for key of @_watching
      @_watching[key].binding.dispose()

    @_watching = {}

  ###
  ###

  update: () =>
    newValue = @script.call @
    return newValue if newValue is @value
    @emit "change", @value = newValue
    newValue

  ###
  ###

  watch: () ->
    @__watch = true
    @update()
    @

  ###
  ###

  references: () ->  
    # will happen with inline bindings
    return [] if not @script.expression 
    findRefs @script.expression


  ###
  ###

  modify: (modifier, args) ->
    @currentRefs = args.filter (arg) -> arg.__isPropertyChain
    ret = modifier.apply @, args.map (arg) ->
      if arg.__isPropertyChain 
        arg.value()
      else
        arg

    @currentRefs = []
    ret


  castAs: (name) -> new PropertyChain(@).castAs name
  ref: (path) -> new PropertyChain(@).ref path
  self: (path) -> new PropertyChain(@).self path
  call: (path, args) -> new PropertyChain(@).call path, args



  ###
  ###

  _watch: (path, target) ->

    return if not @__watch

    if @_watching[path]
      return if @_watching[path].target is target
      @_watching[path].binding.dispose()


    @_watching[path] = {
      target: target
      binding: target.bind(path).watch(true).to(@update)
    }



class ClipScripts

  ###
  ###

  constructor: (@clip, scripts) ->
    @_scripts = {}
    @names = []
    @_bindScripts scripts

  ###
  ###

  watch: () ->
    for key of @_scripts
      @_scripts[key].watch()
    @

  update: () ->
    for key of @_scripts
      @_scripts[key].update()
    @


  ###
  ###

  dispose: () ->
    for key of @_scripts
      @_scripts[key].dispose()

    @_scripts = {}


  ###
  ###

  get: (name) -> @_scripts[name]

  ###
  ###

  _bindScripts: (scripts) ->
    if typeof scripts is "function"
      @_bindScript "value", scripts
    else
      for scriptName of scripts
        @_bindScript scriptName, scripts[scriptName]

  ###
  ###

  _bindScript: (name, script, watch) ->
    @names.push name
    clipScript = new ClipScript script, @clip
    @_scripts[name] = clipScript
    clipScript.on "change", (value) =>
      @clip.set name, value







class Clip
  
  ###
  ###

  constructor: (@options) ->
    @_self = new bindable.Object()
    @data = new bindable.Object options.data  or {}
    @modifiers = options.modifiers or {}
    scripts = @options.scripts or @options.script

    if scripts
      @scripts = new ClipScripts @, scripts

    if options.watch isnt false
      @watch()

  watch: () ->
    @scripts.watch()
    @

  update: () ->
    @scripts.update()
    @

  dispose: () -> 
    @_self?.dispose()
    @scripts?.dispose()
    @_self     = undefined
    @_scripts  = undefined


  script: (name) ->
    @scripts.get name

  get  : () -> @_self.get arguments...
  set  : () -> @_self.set arguments...
  bind : () -> @_self.bind arguments...


module.exports = Clip
module.exports.modifiers = defaultModifiers
module.exports.compile   = require "./compile"