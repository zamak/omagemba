import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy"
  property string statePath: stateDir + "/omagemba.json"
  property var state: Model.defaultState()
  property bool ready: false
  property bool pathSafe: false
  property bool loadError: false
  property string loadErrorMessage: ""
  property bool writeError: false
  property bool writePending: false
  property string queuedPayload: ""
  property string lastActionError: ""
  property date now: new Date()

  // "load" gates the initial read, "write" re-gates every save.
  property string probeMode: "load"
  property bool probeResolved: false

  readonly property string todayKey: Model.dateKey(now)
  readonly property var today: Model.aggregate(state, todayKey, 1)
  readonly property var week: Model.aggregate(state, todayKey, 7)
  readonly property var activeCountermeasure: state.activeCountermeasure || null
  readonly property var countermeasureProgress: Model.countermeasureProgress(state)
  readonly property int todayCount: today.observationCount
  readonly property bool canMutate: ready && pathSafe && !loadError

  function currentStamp() {
    return Model.stampFromDate(new Date())
  }

  function load(raw, allowEmpty) {
    var result = Model.parseStateResult(raw, allowEmpty === true)
    root.state = result.state
    root.loadError = result.error
    root.loadErrorMessage = result.message
    root.ready = true
  }

  function save(next) {
    if (!root.canMutate) return false
    root.state = Model.normalizeState(next)
    root.queuedPayload = Model.serializeState(root.state)
    root.requestWrite()
    return true
  }

  function applyResult(result) {
    root.lastActionError = result.error
    return result.ok ? root.save(result.state) : false
  }

  function logObservation(type, title, impactMinutes) {
    return root.applyResult(Model.logObservation(root.state, {
      type: type,
      title: title,
      impactMinutes: impactMinutes
    }, root.currentStamp()))
  }

  function quickLog(issueKey) {
    return root.applyResult(Model.quickLogIssue(root.state, issueKey, root.currentStamp()))
  }

  function startCountermeasure(issueKey) {
    return root.applyResult(Model.startCountermeasure(root.state, issueKey, root.currentStamp()))
  }

  function resolveCountermeasure(note, expectedId) {
    return root.applyResult(Model.resolveCountermeasure(root.state, note, root.currentStamp(), expectedId))
  }

  function abandonCountermeasure(expectedId) {
    return root.applyResult(Model.abandonCountermeasure(root.state, expectedId))
  }

  function retryWrite() {
    if (!root.canMutate || root.writePending) return
    root.writeError = false
    root.queuedPayload = Model.serializeState(root.state)
    root.requestWrite()
  }

  // ------------------------------------------------------------ path probe
  //
  // The single external process in this plugin. It runs one fixed absolute
  // binary with a cleared environment and no shell, so there is no PATH
  // lookup and no interpolation of user-supplied text anywhere. `-type f`
  // does not dereference symlinks, and `-size` refuses anything above the
  // model's own 1 MiB state ceiling. FileView is therefore never pointed at a
  // symlink, a device node, a FIFO, a directory, or an unbounded file.
  //
  // The probe is re-run immediately before every write, not only at startup:
  // Qt's QSaveFile (which backs `atomicWrites`) resolves symlinks and renames
  // over the resolved target, so a path check made once at load time would
  // not protect later saves.

  function startProbe(mode) {
    if (statePathProbe.running) return
    root.probeMode = mode
    root.probeResolved = false
    statePathProbe.running = true
  }

  function requestWrite() {
    if (!root.canMutate || root.writePending || root.queuedPayload === "") return
    // A probe is already in flight; its completion re-enters here.
    if (statePathProbe.running) return
    root.writePending = true
    root.startProbe("write")
  }

  function resolveProbe(verdict) {
    if (root.probeResolved) return
    root.probeResolved = true

    // `irregular` is the only outright refusal: the path exists but is not a
    // regular file of a sane size.
    var safe = verdict === "regular" || verdict === "missing" || verdict === ""

    if (root.probeMode === "write") {
      if (!safe) {
        root.pathSafe = false
        root.writePending = false
        root.writeError = true
        root.loadError = true
        root.loadErrorMessage = root.unsafePathMessage
        return
      }
      var payload = root.queuedPayload
      root.queuedPayload = ""
      stateFile.setText(payload)
      return
    }

    if (verdict === "regular") {
      root.pathSafe = true
      stateFile.reload()
    } else if (safe) {
      root.pathSafe = true
      root.load("", true)
    } else {
      root.pathSafe = false
      root.loadError = true
      root.loadErrorMessage = root.unsafePathMessage
      root.ready = true
    }

    // A save requested while the initial probe was still running.
    Qt.callLater(root.requestWrite)
  }

  readonly property string unsafePathMessage:
    "The local state path is not a regular file of a safe size; refusing to touch it."

  Component.onCompleted: root.startProbe("load")

  Process {
    id: statePathProbe
    clearEnvironment: true
    environment: ({ "LC_ALL": "C" })
    command: [
      "/usr/bin/find", root.statePath, "-maxdepth", "0",
      "(", "-type", "f", "-size", "-1025k", "-printf", "regular",
      "-o", "-printf", "irregular", ")"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.resolveProbe(String(text || "").trim())
    }
    onExited: function(exitCode) {
      // find exits 1 when the path does not exist: a normal first run.
      if (exitCode !== 0) root.resolveProbe("missing")
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: if (root.pathSafe) root.load(text())
    // The directory is created by FileView's own writer on first save, so a
    // failed load before that point simply means "no state yet".
    onLoadFailed: if (root.pathSafe && !root.ready) root.load("", true)
    onSaved: {
      root.writePending = false
      root.writeError = false
      if (root.queuedPayload !== "") root.requestWrite()
    }
    onSaveFailed: {
      root.writePending = false
      root.writeError = true
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }
}
