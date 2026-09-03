"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const context = vm.createContext({})
const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
vm.runInContext(source, context, { filename: "Model.js" })

function stamp(day, hour) {
  return {
    atMs: Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)), hour || 12),
    offsetMinutes: 0
  }
}

assert.equal(context.addDays("2024-02-28", 1), "2024-02-29")
assert.equal(context.addDays("2024-02-28", 2), "2024-03-01")
assert.equal(context.localDayFromStamp({ atMs: Date.UTC(2026, 0, 1, 1), offsetMinutes: 120 }), "2025-12-31")
assert.equal(context.parseStateResult("", false).error, true)
assert.equal(context.parseStateResult("", true).error, false)
assert.equal(context.parseStateResult('{"version":2}', false).error, true)
assert.equal(context.parseStateResult('{"version":1,"observations":[{}],"activeCountermeasure":null,"wins":[]}', false).error, true)
assert.equal(context.localDayFromStamp({ atMs: 9000000000000000, offsetMinutes: 0 }), "")
assert.equal(context.cleanText("a\u0000b\u007fc", 60), "a b c")

let state = context.defaultState()
let result = context.logObservation(state, {
  type: "muda",
  title: "  Waiting   for tests  ",
  impactMinutes: 5
}, stamp("2026-09-01", 9))
assert.equal(result.ok, true)
state = result.state
assert.equal(state.observations[0].title, "Waiting for tests")
assert.equal(state.observations[0].localDay, "2026-09-01")

result = context.quickLogIssue(state, state.observations[0].issueKey, stamp("2026-09-02", 10))
assert.equal(result.ok, true)
state = result.state
assert.equal(state.observations.length, 2)
assert.notEqual(state.observations[0].id, state.observations[1].id)

result = context.logObservation(state, {
  type: "mura",
  title: "Batch workload swings",
  impactMinutes: 10
}, stamp("2026-09-02", 11))
state = result.state

result = context.logObservation(state, {
  type: "muri",
  title: "Too many active tasks",
  impactMinutes: 2
}, stamp("2026-09-02", 12))
state = result.state

const today = context.aggregate(state, "2026-09-02", 1)
assert.equal(today.observationCount, 3)
assert.equal(today.totalImpactMinutes, 17)
assert.equal(today.byType.muda.count, 1)
assert.equal(today.byType.mura.impactMinutes, 10)

const week = context.aggregate(state, "2026-09-02", 7)
assert.equal(week.observationCount, 4)
assert.equal(week.totalImpactMinutes, 22)
assert.equal(week.dominantType, "muda")
assert.equal(week.topIssue.title, "Waiting for tests")
assert.equal(week.topIssue.count, 2)

result = context.startCountermeasure(state, week.topIssue.issueKey, stamp("2026-09-02", 13))
assert.equal(result.ok, true)
state = result.state
assert.equal(state.activeCountermeasure.title, "Waiting for tests")
assert.equal(context.actionLabel(state.activeCountermeasure.type), "ELIMINATE")
assert.equal(context.startCountermeasure(
  context.defaultState(),
  "missing",
  stamp("2026-09-02", 13)
).error, "issue_not_found")

const blocked = context.startCountermeasure(state, week.issues[1].issueKey, stamp("2026-09-02", 14))
assert.equal(blocked.ok, false)
assert.equal(blocked.error, "countermeasure_active")

result = context.quickLogIssue(state, week.topIssue.issueKey, stamp("2026-09-03", 9))
state = result.state
assert.equal(context.countermeasureProgress(state).count, 1)

result = context.resolveCountermeasure(state, "Enabled incremental builds", stamp("2026-09-03", 10))
assert.equal(result.ok, true)
state = result.state
assert.equal(state.activeCountermeasure, null)
assert.equal(state.wins.length, 1)
assert.equal(state.wins[0].note, "Enabled incremental builds")
assert.equal(context.winLabel(state.wins[0].type), "ELIMINATED")
assert.equal(context.issueStatus(state, state.wins[0].issueKey), "resolved")

const equalTimeRecurrence = context.quickLogIssue(state, state.wins[0].issueKey, {
  atMs: state.wins[0].resolvedAtMs,
  offsetMinutes: 0
})
assert.equal(equalTimeRecurrence.ok, true)
assert.equal(equalTimeRecurrence.value.atMs, state.wins[0].resolvedAtMs + 1)
assert.equal(context.issueStatus(equalTimeRecurrence.state, state.wins[0].issueKey), "returned")
const rollbackRecurrence = context.quickLogIssue(state, state.wins[0].issueKey, {
  atMs: state.wins[0].resolvedAtMs - 1000,
  offsetMinutes: 0
})
assert.equal(rollbackRecurrence.ok, true)
assert.equal(rollbackRecurrence.value.atMs, state.wins[0].resolvedAtMs + 1)
assert.equal(context.issueStatus(rollbackRecurrence.state, state.wins[0].issueKey), "returned")

const resolvedWeek = context.aggregate(state, "2026-09-03", 7)
const resolvedKey = state.wins[0].issueKey
assert.equal(resolvedWeek.issues.some(row => row.issueKey === resolvedKey), false)
assert.equal(resolvedWeek.observationCount, 2)
assert.equal(resolvedWeek.totalImpactMinutes, 12)
assert.equal(resolvedWeek.topIssue.title, "Batch workload swings")
assert.equal(context.recurringIssues(state, "2026-09-03", 7, 10).some(
  row => row.issueKey === resolvedKey
), false)
assert.equal(context.startCountermeasure(
  state,
  resolvedKey,
  stamp("2026-09-03", 11)
).error, "issue_resolved")

const recurrence = context.quickLogIssue(state, resolvedKey, stamp("2026-09-03", 12))
assert.equal(recurrence.ok, true)
assert.equal(context.issueStatus(recurrence.state, resolvedKey), "returned")
const returnedIssue = context.aggregate(recurrence.state, "2026-09-03", 7).issues.find(
  row => row.issueKey === resolvedKey
)
assert.equal(returnedIssue.status, "returned")
assert.equal(returnedIssue.count, 1)
assert.equal(returnedIssue.impactMinutes, 5)
assert.equal(context.recurringIssues(recurrence.state, "2026-09-03", 7, 10).some(
  row => row.issueKey === resolvedKey
), true)
const reopenedTarget = context.startCountermeasure(
  recurrence.state,
  resolvedKey,
  stamp("2026-09-03", 13)
)
assert.equal(reopenedTarget.ok, true)
const secondResolution = context.resolveCountermeasure(
  reopenedTarget.state,
  "Adjusted the build queue",
  stamp("2026-09-03", 14)
)
assert.equal(secondResolution.ok, true)
assert.equal(secondResolution.state.wins.length, 2)
assert.equal(context.isLatestResolution(secondResolution.state, secondResolution.state.wins[0].id), false)
assert.equal(context.isLatestResolution(secondResolution.state, secondResolution.state.wins[1].id), true)
assert.equal(context.issueStatus(secondResolution.state, resolvedKey), "resolved")
assert.equal(context.aggregate(secondResolution.state, "2026-09-03", 7).issues.some(
  row => row.issueKey === resolvedKey
), false)
const secondRecurrence = context.quickLogIssue(
  secondResolution.state,
  resolvedKey,
  stamp("2026-09-03", 15)
)
assert.equal(context.issueStatus(secondRecurrence.state, resolvedKey), "returned")
const secondReturnedIssue = context.aggregate(secondRecurrence.state, "2026-09-03", 7).issues.find(
  row => row.issueKey === resolvedKey
)
assert.equal(secondReturnedIssue.count, 1)
assert.equal(secondReturnedIssue.impactMinutes, 5)

const historicalWeek = context.aggregate(secondRecurrence.state, "2026-09-02", 7)
assert.equal(historicalWeek.issues.find(row => row.issueKey === resolvedKey).status, "open")

const durableResolution = context.normalizeState({
  version: 1,
  observations: secondResolution.state.observations,
  activeCountermeasure: null,
  wins: [],
  resolutions: secondResolution.state.resolutions
})
assert.equal(context.issueStatus(durableResolution, resolvedKey), "resolved")
assert.equal(context.aggregate(durableResolution, "2026-09-03", 7).issues.some(
  row => row.issueKey === resolvedKey
), false)

const winOnly = context.normalizeState({
  version: 1,
  observations: [],
  activeCountermeasure: null,
  wins: [state.wins[0]]
})
const restoredFromWin = context.quickLogIssue(winOnly, resolvedKey, stamp("2026-09-04", 9))
assert.equal(restoredFromWin.ok, true)
assert.equal(restoredFromWin.value.impactMinutes, 5)
assert.equal(context.issueStatus(restoredFromWin.state, resolvedKey), "returned")

const chronologyState = context.startCountermeasure(
  { version: 1, observations: [state.observations[0]], activeCountermeasure: null, wins: [] },
  state.observations[0].issueKey,
  { atMs: state.observations[0].atMs, offsetMinutes: 0 }
)
assert.equal(chronologyState.error, "invalid_chronology")

result = context.startCountermeasure(state, week.issues[1].issueKey, stamp("2026-09-02", 13))
assert.notEqual(result.value.id, state.wins[0].countermeasureId)
state = result.state
assert.equal(context.abandonCountermeasure(state, "c_stale_0").error, "stale_countermeasure")
assert.equal(context.resolveCountermeasure(
  state,
  "",
  stamp("2026-09-02", 14),
  "c_stale_0"
).error, "stale_countermeasure")
result = context.abandonCountermeasure(state)
assert.equal(result.ok, true)
assert.equal(result.state.activeCountermeasure, null)
assert.equal(result.state.wins.length, 1)

assert.equal(context.logObservation(state, { type: "bad", title: "x", impactMinutes: 5 }, stamp("2026-09-03")).error, "invalid_type")
assert.equal(context.logObservation(state, { type: "muda", title: "x", impactMinutes: 7 }, stamp("2026-09-03")).error, "invalid_impact")
assert.equal(context.formatMinutes(138), "2h 18m")

const serialized = context.serializeState(state)
const parsed = context.parseStateResult(serialized, false)
assert.equal(parsed.error, false)
assert.equal(parsed.state.observations.length, state.observations.length)

const duplicate = JSON.parse(serialized)
duplicate.observations.push(duplicate.observations[0])
assert.equal(context.parseStateResult(JSON.stringify(duplicate), false).error, true)

const invalidWin = JSON.parse(serialized)
invalidWin.wins[0].resolvedAtMs = invalidWin.wins[0].startedAtMs - 1
assert.equal(context.parseStateResult(JSON.stringify(invalidWin), false).error, true)

const contradictory = JSON.parse(serialized)
contradictory.wins.push({
  id: "w_contradictory_0",
  countermeasureId: contradictory.activeCountermeasure.id,
  type: contradictory.activeCountermeasure.type,
  title: contradictory.activeCountermeasure.title,
  impactMinutes: contradictory.activeCountermeasure.impactMinutes,
  startedAtMs: contradictory.activeCountermeasure.startedAtMs,
  startedOffsetMinutes: 0,
  resolvedAtMs: contradictory.activeCountermeasure.startedAtMs + 1000,
  resolvedOffsetMinutes: 0,
  note: ""
})
assert.equal(context.parseStateResult(JSON.stringify(contradictory), false).error, true)

let fullWins = context.startCountermeasure(
  { version: 1, observations: [state.observations[0]], activeCountermeasure: null, wins: [] },
  state.observations[0].issueKey,
  { atMs: state.observations[0].atMs + 1000, offsetMinutes: 0 }
).state
for (let i = 0; i < 100; i++) {
  const startedAtMs = state.observations[0].atMs + 10000 + i * 2000
  fullWins.wins.push({
    id: "w_retained" + i.toString(36) + "_0",
    countermeasureId: "c_retained" + i.toString(36) + "_0",
    type: "mura",
    title: "Retained win " + i,
    impactMinutes: 2,
    startedAtMs,
    startedOffsetMinutes: 0,
    resolvedAtMs: startedAtMs + 1000,
    resolvedOffsetMinutes: 0,
    note: ""
  })
}
const discardedWin = context.resolveCountermeasure(
  fullWins,
  "Must remain active",
  { atMs: state.observations[0].atMs + 2000, offsetMinutes: 0 }
)
assert.equal(discardedWin.error, "win_outside_retention")
assert.notEqual(discardedWin.state.activeCountermeasure, null)
assert.equal(discardedWin.state.wins.length, 100)

const base = stamp("2026-01-01", 1).atMs
const capObservations = []
const capResolutions = []
const capWins = []
for (let i = 0; i < 500; i++) {
  const title = ("Issue " + i + " " + "\\".repeat(60)).slice(0, 60)
  const observedAtMs = base + i * 10000
  capObservations.push({
    id: "o_cap" + i.toString(36) + "_0",
    type: "muda",
    title,
    impactMinutes: 10,
    atMs: observedAtMs,
    offsetMinutes: 0
  })
  capResolutions.push({
    type: "muda",
    title,
    impactMinutes: 10,
    resolvedAtMs: observedAtMs + 5000,
    resolvedOffsetMinutes: 0
  })
  if (i < 100) capWins.push({
    id: "w_cap" + i.toString(36) + "_0",
    countermeasureId: "c_cap" + i.toString(36) + "_0",
    type: "muda",
    title: ("Win " + i + " " + "\\".repeat(60)).slice(0, 60),
    impactMinutes: 10,
    startedAtMs: observedAtMs + 1000,
    startedOffsetMinutes: 0,
    resolvedAtMs: observedAtMs + 5000,
    resolvedOffsetMinutes: 0,
    note: "\\".repeat(240)
  })
}
for (let i = 0; i < 600; i++) {
  capResolutions.push({
    type: "mura",
    title: "Irrelevant " + i,
    impactMinutes: 2,
    resolvedAtMs: base + 10000000 + i * 1000,
    resolvedOffsetMinutes: 0
  })
}
const maximumState = context.normalizeState({
  version: 1,
  observations: capObservations,
  activeCountermeasure: null,
  wins: capWins,
  resolutions: capResolutions
})
assert.equal(maximumState.resolutions.length, 600)
assert.equal(context.aggregate(maximumState, "2026-01-01", 1).issues.length, 0)
const maximumSerialized = context.serializeState(maximumState)
assert.ok(maximumSerialized.length > 262144)
assert.ok(maximumSerialized.length <= context.MAX_JSON_LENGTH)
assert.equal(context.parseStateResult(maximumSerialized, false).error, false)

const duplicateCountermeasure = JSON.parse(maximumSerialized)
duplicateCountermeasure.wins[1].countermeasureId = duplicateCountermeasure.wins[0].countermeasureId
assert.equal(context.parseStateResult(JSON.stringify(duplicateCountermeasure), false).error, true)

let bounded = context.defaultState()
for (let i = 0; i < 500; i++) {
  bounded = context.logObservation(bounded, {
    type: "muda",
    title: "Issue " + i,
    impactMinutes: 2
  }, { atMs: base + i * 60000, offsetMinutes: 0 }).state
}
const backdated = context.logObservation(bounded, {
  type: "muda",
  title: "Backdated issue",
  impactMinutes: 2
}, { atMs: base - 1, offsetMinutes: 0 })
assert.equal(backdated.ok, false)
assert.equal(backdated.error, "observation_outside_retention")
assert.equal(backdated.state.observations.length, 500)
assert.equal(backdated.state.observations.some(row => row.title === "Backdated issue"), false)

console.log("OmaGemba model tests passed")
