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
  property bool directoryReady: false
  property bool loadError: false
  property string loadErrorMessage: ""
  property bool writeError: false
  property bool writePending: false
  property string queuedPayload: ""
  property string writingPayload: ""
  property string lastActionError: ""
  property date now: new Date()

  readonly property string todayKey: Model.dateKey(now)
  readonly property var today: Model.aggregate(state, todayKey, 1)
  readonly property var week: Model.aggregate(state, todayKey, 7)
  readonly property var activeCountermeasure: state.activeCountermeasure || null
  readonly property var countermeasureProgress: Model.countermeasureProgress(state)
  readonly property int todayCount: today.observationCount
  readonly property bool canMutate: ready && directoryReady && !loadError

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
    root.flushWrite()
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

  function flushWrite() {
    if (!root.canMutate || stateWriter.running || root.queuedPayload === "") return
    root.writingPayload = root.queuedPayload
    root.queuedPayload = ""
    root.writePending = true
    stateWriter.command = [
      "bash", "-c",
      "set -e; tmp=\"$1.tmp.$$\"; found=0; trap 'rm -f -- \"$tmp\"' EXIT; while IFS= read -r line; do if [[ $line == __OMAGEMBA_STATE_EOF__ ]]; then found=1; break; fi; printf '%s\\n' \"$line\"; done > \"$tmp\"; (( found == 1 )); mv -f -- \"$tmp\" \"$1\"; trap - EXIT",
      "--", root.statePath
    ]
    stateWriter.running = true
  }

  function retryWrite() {
    if (!root.canMutate || stateWriter.running) return
    root.writeError = false
    root.queuedPayload = Model.serializeState(root.state)
    root.flushWrite()
  }

  Component.onCompleted: ensureStateDir.running = true

  Process {
    id: ensureStateDir
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.loadError = true
        root.loadErrorMessage = "Could not create the local state directory."
        root.ready = true
        return
      }
      root.directoryReady = true
      stateProbe.running = true
    }
  }

  Process {
    id: stateProbe
    command: [
      "bash", "-c",
      "if [[ ! -e $1 ]]; then exit 0; elif [[ -f $1 && -r $1 ]]; then exit 10; else exit 20; fi",
      "--", root.statePath
    ]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.load("", true)
      } else if (exitCode === 10) {
        stateFile.reload()
      } else {
        root.loadError = true
        root.loadErrorMessage = "The local state file exists but cannot be read safely."
        root.ready = true
      }
    }
  }

  Process {
    id: stateWriter
    stdinEnabled: true
    onStarted: write(root.writingPayload + "__OMAGEMBA_STATE_EOF__\n")
    onExited: function(exitCode) {
      root.writePending = false
      root.writeError = exitCode !== 0
      if (exitCode !== 0 && root.queuedPayload === "") root.queuedPayload = root.writingPayload
      root.writingPayload = ""
      if (exitCode === 0) root.flushWrite()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    onLoaded: if (root.directoryReady) root.load(text())
    onLoadFailed: if (root.directoryReady) {
      root.loadError = true
      root.loadErrorMessage = "The local state file could not be read safely."
      root.ready = true
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
