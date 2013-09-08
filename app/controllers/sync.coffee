Spine = @Spine or require('spine')
Model = Spine.Model

# Connection states
OFFLINE = 0
IN_PROGRESS = 1
ONLINE = 2

Sync =

  queue: JSON.parse localStorage.Queue or '{"Note": {}, "Notebook": {}}'

  # Hold pending actions
  pending: []

  # Run pending actions
  _clearPending: ->
    for [fn, that, args] in @pending by - 1
      fn.apply(that, args)
      @pending.length--

  # If connection is not ready, then we will wait until it is
  defer: (self, fn, args...) ->
    if @state is ONLINE
      fn.apply(self, args)
    else
      @pending.push [fn, self,  args]

  state: OFFLINE

  connect: (fn) ->

    # Only run connect once
    if @state isnt OFFLINE and typeof fn is 'function 'then return fn()
    @state = IN_PROGRESS

    request = indexedDB.open("springseed", 1)

    request.onupgradeneeded = (e) =>
      @db = e.target.result

      # We're going to just be storing all the spine stuff in one store,
      # just because I cbf seperating the Keys.
      @db.createObjectStore("meta")

      # We'll make another store to seperate the note s
      @db.createObjectStore("notes")

    request.onsuccess = (e) =>
      Sync.db = e.target.result
      @state = ONLINE
      fn() if typeof fn is 'function'
      @_clearPending()

  # Check an event, and if it is a model update add it to the queue
  addToQueue: (event, args) ->
    if @queue[args.constructor.name][args.id] and @queue[args.constructor.name][args.id][0] is "create"
      # create + destroy = nothing
      if event is "destroy"
        delete @queue[args.constructor.name][args.id]
    else
      # Otherwiswe, add it to the queue
      @queue[args.constructor.name][args.id] = [event, new Date().getTime()]
    @saveQueue()

  saveQueue: ->
    # Save queue to localstorage
    localStorage.Queue = JSON.stringify @queue

# Just in case you need any default values
class Base

Model.Sync =

  extended: ->

    console.log '%c> Setting up sync for %s', 'font-weight: bold', this.name

    @fetch ->
      console.log '%c> Calling fetch', 'background: #eee'
      Sync.defer(this, @loadLocal)

    @change (record, event) ->
      Sync.addToQueue(event, record)
      console.log '%c> Calling change: ' + event, 'background: #eee'
      Sync.defer(this, @saveLocal)

    Sync.connect()

  saveLocal: ->
    result = JSON.stringify(@)

    # Save to IndexedDB
    trans = Sync.db.transaction(["meta"], "readwrite")
    store = trans.objectStore "meta"
    request = store.put(result, @className)

  loadLocal: (options = {}) ->

    console.log '%c> Fetching notes', 'color: blue'

    options.clear = true unless options.hasOwnProperty('clear')

    # Load from IndexedDB
    trans = Sync.db.transaction(["meta"], "readwrite")
    store = trans.objectStore "meta"
    request = store.get(@className)

    request.onsuccess = (e) =>
      result = e.target.result
      @refresh(result or [], options)

  saveNote: (content) ->
    trans = Sync.db.transaction(["notes"], "readwrite")
    store = trans.objectStore "notes"
    request = store.put(content, @id)

  loadNote: (callback) ->
    trans = Sync.db.transaction(["notes"], "readwrite")
    store = trans.objectStore "notes"
    request = store.get(@id)

    request.onsuccess = (e) =>
      result = e.target.result
      callback(result)

  deleteNote: ->
    trans = Sync.db.transaction(["notes"], "readwrite")
    store = trans.objectStore "notes"
    request = store.delete(@id)

Model.Sync.Methods =
  extended: ->
    @extend Extend
    @include Include

module?.exports = Sync
