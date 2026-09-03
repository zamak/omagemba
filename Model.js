var TYPES = ["muda", "mura", "muri"]
var IMPACTS = [2, 5, 10]
var MAX_OBSERVATIONS = 500
var MAX_WINS = 100
var MAX_RESOLUTIONS = 600
var MAX_RAW_RECORDS = 2000
var MAX_JSON_LENGTH = 1048576

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function dateKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function dateFromKey(key) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""))
  if (!match) return new Date(NaN)
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
}

function validDateKey(key) {
  var date = dateFromKey(key)
  return !isNaN(date.getTime()) && dateKey(date) === String(key)
}

function dayNumber(key) {
  if (!validDateKey(key)) return NaN
  var date = dateFromKey(key)
  return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000)
}

function addDays(key, amount) {
  var number = dayNumber(key)
  if (isNaN(number)) return ""
  var date = new Date((number + amount) * 86400000)
  return date.getUTCFullYear() + "-" + pad2(date.getUTCMonth() + 1) + "-" + pad2(date.getUTCDate())
}

function cleanText(value, maxLength) {
  if (typeof value !== "string") return ""
  return value.replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim().slice(0, maxLength)
}

function normalizedType(value) {
  var type = String(value || "").toLowerCase()
  return TYPES.indexOf(type) >= 0 ? type : ""
}

function normalizedImpact(value) {
  return typeof value === "number" && IMPACTS.indexOf(value) >= 0 ? value : 0
}

function validInteger(value) {
  return typeof value === "number" && isFinite(value) && Math.floor(value) === value
}

function validStamp(stamp) {
  if (!stamp || !validInteger(stamp.atMs) || stamp.atMs <= 0
      || !validInteger(stamp.offsetMinutes)
      || stamp.offsetMinutes < -840 || stamp.offsetMinutes > 840) return false
  return !isNaN(new Date(stamp.atMs).getTime())
    && !isNaN(new Date(stamp.atMs - stamp.offsetMinutes * 60000).getTime())
}

function stampFromDate(date) {
  var value = date instanceof Date ? date : new Date()
  return {
    atMs: Math.floor(value.getTime()),
    offsetMinutes: value.getTimezoneOffset()
  }
}

function localDayFromStamp(stamp) {
  if (!validStamp(stamp)) return ""
  var adjusted = new Date(stamp.atMs - stamp.offsetMinutes * 60000)
  return adjusted.getUTCFullYear() + "-" + pad2(adjusted.getUTCMonth() + 1) + "-" + pad2(adjusted.getUTCDate())
}

function canonicalTitle(value) {
  return cleanText(value, 60)
}

function issueKey(type, title) {
  var normalized = normalizedType(type)
  var cleaned = canonicalTitle(title)
  return normalized && cleaned ? normalized + "|" + cleaned.toLowerCase() : ""
}

function validId(value, prefix) {
  return typeof value === "string"
    && new RegExp("^" + prefix + "_[a-z0-9]+_[0-9]+$").test(value)
}

function nextId(prefix, atMs, state) {
  var base = prefix + "_" + Math.floor(atMs).toString(36) + "_"
  var used = ({})
  var observations = state && Array.isArray(state.observations) ? state.observations : []
  var wins = state && Array.isArray(state.wins) ? state.wins : []
  for (var i = 0; i < observations.length; i++) used[observations[i].id] = true
  for (var j = 0; j < wins.length; j++) {
    used[wins[j].id] = true
    used[wins[j].countermeasureId] = true
  }
  if (state && state.activeCountermeasure) used[state.activeCountermeasure.id] = true
  var suffix = 0
  while (used[base + suffix]) suffix++
  return base + suffix
}

function defaultState() {
  return {
    version: 1,
    observations: [],
    activeCountermeasure: null,
    wins: [],
    resolutions: []
  }
}

function normalizeObservation(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var type = normalizedType(value.type)
  var title = canonicalTitle(value.title)
  var impact = normalizedImpact(value.impactMinutes)
  var stamp = { atMs: value.atMs, offsetMinutes: value.offsetMinutes }
  if (!validId(value.id, "o") || !type || !title || !impact || !validStamp(stamp)) return null
  return {
    id: value.id,
    type: type,
    title: title,
    issueKey: issueKey(type, title),
    impactMinutes: impact,
    atMs: stamp.atMs,
    offsetMinutes: stamp.offsetMinutes,
    localDay: localDayFromStamp(stamp)
  }
}

function normalizeCountermeasure(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var type = normalizedType(value.type)
  var title = canonicalTitle(value.title)
  var stamp = { atMs: value.startedAtMs, offsetMinutes: value.startedOffsetMinutes }
  if (!validId(value.id, "c") || !type || !title || !validStamp(stamp)) return null
  return {
    id: value.id,
    issueKey: issueKey(type, title),
    type: type,
    title: title,
    impactMinutes: normalizedImpact(value.impactMinutes) || 5,
    sourceAtMs: validInteger(value.sourceAtMs)
      && value.sourceAtMs > 0 && value.sourceAtMs < stamp.atMs
      ? value.sourceAtMs
      : 0,
    startedAtMs: stamp.atMs,
    startedOffsetMinutes: stamp.offsetMinutes,
    startedLocalDay: localDayFromStamp(stamp)
  }
}

function normalizeWin(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var type = normalizedType(value.type)
  var title = canonicalTitle(value.title)
  var started = { atMs: value.startedAtMs, offsetMinutes: value.startedOffsetMinutes }
  var resolved = { atMs: value.resolvedAtMs, offsetMinutes: value.resolvedOffsetMinutes }
  if (!validId(value.id, "w") || !validId(value.countermeasureId, "c")
      || !type || !title || !validStamp(started) || !validStamp(resolved)
      || resolved.atMs < started.atMs) return null
  return {
    id: value.id,
    countermeasureId: value.countermeasureId,
    issueKey: issueKey(type, title),
    type: type,
    title: title,
    impactMinutes: normalizedImpact(value.impactMinutes) || 5,
    startedAtMs: started.atMs,
    startedOffsetMinutes: started.offsetMinutes,
    startedLocalDay: localDayFromStamp(started),
    resolvedAtMs: resolved.atMs,
    resolvedOffsetMinutes: resolved.offsetMinutes,
    resolvedLocalDay: localDayFromStamp(resolved),
    note: cleanText(value.note, 240)
  }
}

function normalizeResolution(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var type = normalizedType(value.type)
  var title = canonicalTitle(value.title)
  var stamp = { atMs: value.resolvedAtMs, offsetMinutes: value.resolvedOffsetMinutes }
  if (!type || !title || !validStamp(stamp)) return null
  return {
    issueKey: issueKey(type, title),
    type: type,
    title: title,
    impactMinutes: normalizedImpact(value.impactMinutes) || 5,
    resolvedAtMs: stamp.atMs,
    resolvedOffsetMinutes: stamp.offsetMinutes,
    resolvedLocalDay: localDayFromStamp(stamp)
  }
}

function normalizeUnique(value, normalizer, limit, newestField) {
  if (!Array.isArray(value)) return []
  var byId = ({})
  for (var i = 0; i < value.length; i++) {
    var row = normalizer(value[i])
    if (!row) continue
    if (!byId[row.id] || row[newestField] >= byId[row.id][newestField]) byId[row.id] = row
  }
  var result = []
  for (var key in byId) result.push(byId[key])
  result.sort(function(a, b) {
    var byTime = a[newestField] - b[newestField]
    return byTime !== 0 ? byTime : a.id.localeCompare(b.id)
  })
  return result.slice(Math.max(0, result.length - limit))
}

function normalizeResolutions(value, rawWins, observations, retainedWins) {
  var byIssue = ({})
  var rows = Array.isArray(value) ? value : []
  for (var i = 0; i < rows.length; i++) {
    var resolution = normalizeResolution(rows[i])
    if (resolution && (!byIssue[resolution.issueKey]
        || resolution.resolvedAtMs > byIssue[resolution.issueKey].resolvedAtMs))
      byIssue[resolution.issueKey] = resolution
  }
  var winRows = Array.isArray(rawWins) ? rawWins : []
  for (var j = 0; j < winRows.length; j++) {
    var win = normalizeWin(winRows[j])
    if (!win) continue
    var fromWin = normalizeResolution(win)
    if (!byIssue[fromWin.issueKey]
        || fromWin.resolvedAtMs > byIssue[fromWin.issueKey].resolvedAtMs)
      byIssue[fromWin.issueKey] = fromWin
  }
  var relevantIssues = ({})
  var observationRows = Array.isArray(observations) ? observations : []
  var retainedWinRows = Array.isArray(retainedWins) ? retainedWins : []
  for (var k = 0; k < observationRows.length; k++)
    relevantIssues[observationRows[k].issueKey] = true
  for (var l = 0; l < retainedWinRows.length; l++)
    relevantIssues[retainedWinRows[l].issueKey] = true
  var result = []
  for (var key in byIssue)
    if (relevantIssues[key]) result.push(byIssue[key])
  result.sort(function(a, b) {
    var byTime = a.resolvedAtMs - b.resolvedAtMs
    return byTime !== 0 ? byTime : a.issueKey.localeCompare(b.issueKey)
  })
  return result.slice(Math.max(0, result.length - MAX_RESOLUTIONS))
}

function normalizeState(value) {
  var state = defaultState()
  if (!value || typeof value !== "object" || Array.isArray(value)) return state
  state.observations = normalizeUnique(value.observations, normalizeObservation, MAX_OBSERVATIONS, "atMs")
  state.activeCountermeasure = normalizeCountermeasure(value.activeCountermeasure)
  state.wins = normalizeUnique(value.wins, normalizeWin, MAX_WINS, "resolvedAtMs")
  state.resolutions = normalizeResolutions(
    value.resolutions,
    value.wins,
    state.observations,
    state.wins
  )
  return state
}

function validRecordSet(value, normalizer) {
  if (!Array.isArray(value)) return false
  var ids = ({})
  for (var i = 0; i < value.length; i++) {
    var row = normalizer(value[i])
    if (!row || ids[row.id]) return false
    ids[row.id] = true
  }
  return true
}

function validResolutionSet(value) {
  if (value === undefined) return true
  if (!Array.isArray(value)) return false
  var issueKeys = ({})
  for (var i = 0; i < value.length; i++) {
    var row = normalizeResolution(value[i])
    if (!row || issueKeys[row.issueKey]) return false
    issueKeys[row.issueKey] = true
  }
  return true
}

function validStateRelations(state) {
  var active = state.activeCountermeasure
  var countermeasureIds = ({})
  for (var w = 0; w < state.wins.length; w++) {
    var countermeasureId = state.wins[w].countermeasureId
    if (countermeasureIds[countermeasureId]) return false
    countermeasureIds[countermeasureId] = true
  }
  if (!active) return true
  if (countermeasureIds[active.id]) return false
  var sourceAtMs = active.sourceAtMs
  var latestResolution = null
  for (var i = 0; i < state.observations.length; i++) {
    var observation = state.observations[i]
    if (observation.issueKey === active.issueKey
        && observation.atMs < active.startedAtMs
        && observation.atMs > sourceAtMs) sourceAtMs = observation.atMs
  }
  for (var j = 0; j < state.resolutions.length; j++)
    if (state.resolutions[j].issueKey === active.issueKey) latestResolution = state.resolutions[j]
  return sourceAtMs > 0 && sourceAtMs < active.startedAtMs
    && (!latestResolution || latestResolution.resolvedAtMs < sourceAtMs)
}

function parseStateResult(raw, allowEmpty) {
  var text = String(raw || "").trim()
  if (!text) return allowEmpty === true
    ? { state: defaultState(), error: false, message: "" }
    : { state: defaultState(), error: true, message: "State file is empty." }
  if (text.length > MAX_JSON_LENGTH)
    return { state: defaultState(), error: true, message: "State file is too large." }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
      return { state: defaultState(), error: true, message: "State root must be an object." }
    if (parsed.version !== 1)
      return { state: defaultState(), error: true, message: "Unsupported state version: " + parsed.version }
    if ((Array.isArray(parsed.observations) && parsed.observations.length > MAX_RAW_RECORDS)
        || (Array.isArray(parsed.wins) && parsed.wins.length > MAX_RAW_RECORDS)
        || (Array.isArray(parsed.resolutions) && parsed.resolutions.length > MAX_RAW_RECORDS))
      return { state: defaultState(), error: true, message: "State contains too many records." }
    if (!validRecordSet(parsed.observations, normalizeObservation)
        || !validRecordSet(parsed.wins, normalizeWin)
        || !validResolutionSet(parsed.resolutions)
        || (parsed.activeCountermeasure !== null && !normalizeCountermeasure(parsed.activeCountermeasure)))
      return { state: defaultState(), error: true, message: "State contains invalid records." }
    var normalized = normalizeState(parsed)
    if (!validStateRelations(normalized))
      return { state: defaultState(), error: true, message: "State contains contradictory lifecycle records." }
    return { state: normalized, error: false, message: "" }
  } catch (error) {
    return { state: defaultState(), error: true, message: String(error) }
  }
}

function serializeState(state) {
  return JSON.stringify(normalizeState(state), null, 2) + "\n"
}

function commandResult(ok, state, value, error) {
  return { ok: ok, state: state, value: value || null, error: error || "" }
}

function logObservation(state, values, stamp) {
  var next = normalizeState(state)
  var type = normalizedType(values ? values.type : "")
  var title = canonicalTitle(values ? values.title : "")
  var impact = normalizedImpact(values ? values.impactMinutes : 0)
  if (!type) return commandResult(false, next, null, "invalid_type")
  if (!title) return commandResult(false, next, null, "invalid_title")
  if (!impact) return commandResult(false, next, null, "invalid_impact")
  if (!validStamp(stamp)) return commandResult(false, next, null, "invalid_stamp")
  var effectiveStamp = { atMs: stamp.atMs, offsetMinutes: stamp.offsetMinutes }
  var key = issueKey(type, title)
  var latestObservation = issueForKey(next, key)
  var latestResolution = latestResolutionForKey(next, key)
  var latestEventAtMs = Math.max(
    latestObservation ? latestObservation.atMs : 0,
    latestResolution ? latestResolution.resolvedAtMs : 0
  )
  if (effectiveStamp.atMs <= latestEventAtMs) effectiveStamp.atMs = latestEventAtMs + 1
  var row = {
    id: nextId("o", effectiveStamp.atMs, next),
    type: type,
    title: title,
    issueKey: key,
    impactMinutes: impact,
    atMs: effectiveStamp.atMs,
    offsetMinutes: effectiveStamp.offsetMinutes,
    localDay: localDayFromStamp(effectiveStamp)
  }
  next.observations.push(row)
  next.observations = normalizeUnique(next.observations, normalizeObservation, MAX_OBSERVATIONS, "atMs")
  var retained = false
  for (var i = 0; i < next.observations.length; i++)
    if (next.observations[i].id === row.id) retained = true
  if (!retained) return commandResult(false, next, null, "observation_outside_retention")
  return commandResult(true, next, row, "")
}

function issueForKey(state, key) {
  var normalized = normalizeState(state)
  for (var i = normalized.observations.length - 1; i >= 0; i--)
    if (normalized.observations[i].issueKey === key) return normalized.observations[i]
  return null
}

function latestResolutionForKey(state, key) {
  var normalized = normalizeState(state)
  for (var i = normalized.resolutions.length - 1; i >= 0; i--)
    if (normalized.resolutions[i].issueKey === key) return normalized.resolutions[i]
  return null
}

function isLatestResolution(state, winId) {
  var normalized = normalizeState(state)
  var win = null
  for (var i = 0; i < normalized.wins.length; i++)
    if (normalized.wins[i].id === winId) win = normalized.wins[i]
  if (!win) return false
  var latest = latestResolutionForKey(normalized, win.issueKey)
  return latest !== null && latest.resolvedAtMs === win.resolvedAtMs
}

function issueStatus(state, key) {
  var observation = issueForKey(state, key)
  var resolution = latestResolutionForKey(state, key)
  if (!resolution) return "open"
  return observation && observation.atMs > resolution.resolvedAtMs ? "returned" : "resolved"
}

function quickLogIssue(state, key, stamp) {
  var row = issueForKey(state, key)
  if (!row) row = latestResolutionForKey(state, key)
  if (!row) return commandResult(false, normalizeState(state), null, "issue_not_found")
  return logObservation(state, {
    type: row.type,
    title: row.title,
    impactMinutes: row.impactMinutes
  }, stamp)
}

function startCountermeasure(state, key, stamp) {
  var next = normalizeState(state)
  if (next.activeCountermeasure) return commandResult(false, next, null, "countermeasure_active")
  if (!validStamp(stamp)) return commandResult(false, next, null, "invalid_stamp")
  var source = issueForKey(next, key)
  if (!source) return commandResult(false, next, null, "issue_not_found")
  if (issueStatus(next, key) === "resolved") return commandResult(false, next, null, "issue_resolved")
  if (stamp.atMs <= source.atMs) return commandResult(false, next, null, "invalid_chronology")
  var countermeasure = {
    id: nextId("c", stamp.atMs, next),
    issueKey: source.issueKey,
    type: source.type,
    title: source.title,
    impactMinutes: source.impactMinutes,
    sourceAtMs: source.atMs,
    startedAtMs: stamp.atMs,
    startedOffsetMinutes: stamp.offsetMinutes,
    startedLocalDay: localDayFromStamp(stamp)
  }
  next.activeCountermeasure = countermeasure
  return commandResult(true, next, countermeasure, "")
}

function abandonCountermeasure(state, expectedId) {
  var next = normalizeState(state)
  if (!next.activeCountermeasure) return commandResult(false, next, null, "no_active_countermeasure")
  if (expectedId && next.activeCountermeasure.id !== expectedId)
    return commandResult(false, next, null, "stale_countermeasure")
  var abandoned = next.activeCountermeasure
  next.activeCountermeasure = null
  return commandResult(true, next, abandoned, "")
}

function resolveCountermeasure(state, note, stamp, expectedId) {
  var next = normalizeState(state)
  var active = next.activeCountermeasure
  if (!active) return commandResult(false, next, null, "no_active_countermeasure")
  if (expectedId && active.id !== expectedId)
    return commandResult(false, next, null, "stale_countermeasure")
  if (!validStamp(stamp)) return commandResult(false, next, null, "invalid_stamp")
  if (stamp.atMs < active.startedAtMs) return commandResult(false, next, null, "invalid_chronology")
  var win = {
    id: nextId("w", stamp.atMs, next),
    countermeasureId: active.id,
    issueKey: active.issueKey,
    type: active.type,
    title: active.title,
    impactMinutes: active.impactMinutes,
    startedAtMs: active.startedAtMs,
    startedOffsetMinutes: active.startedOffsetMinutes,
    startedLocalDay: active.startedLocalDay,
    resolvedAtMs: stamp.atMs,
    resolvedOffsetMinutes: stamp.offsetMinutes,
    resolvedLocalDay: localDayFromStamp(stamp),
    note: cleanText(note, 240)
  }
  next.wins.push(win)
  next.wins = normalizeUnique(next.wins, normalizeWin, MAX_WINS, "resolvedAtMs")
  var retained = false
  for (var i = 0; i < next.wins.length; i++)
    if (next.wins[i].id === win.id) retained = true
  if (!retained) return commandResult(false, next, null, "win_outside_retention")
  next.resolutions.push(normalizeResolution(win))
  next.resolutions = normalizeResolutions(
    next.resolutions,
    next.wins,
    next.observations,
    next.wins
  )
  next.activeCountermeasure = null
  return commandResult(true, next, win, "")
}

function emptyTypeTotals() {
  return {
    muda: { count: 0, impactMinutes: 0 },
    mura: { count: 0, impactMinutes: 0 },
    muri: { count: 0, impactMinutes: 0 }
  }
}

function issueSort(a, b) {
  if (a.impactMinutes !== b.impactMinutes) return b.impactMinutes - a.impactMinutes
  if (a.count !== b.count) return b.count - a.count
  if (a.latestAtMs !== b.latestAtMs) return b.latestAtMs - a.latestAtMs
  return a.issueKey.localeCompare(b.issueKey)
}

function aggregate(state, throughDay, calendarDays) {
  var normalized = normalizeState(state)
  var days = Math.max(1, Math.min(365, Math.floor(Number(calendarDays) || 1)))
  var end = validDateKey(throughDay) ? throughDay : dateKey(new Date())
  var start = addDays(end, -(days - 1))
  var totals = emptyTypeTotals()
  var issueMap = ({})
  var latestResolutionByIssue = ({})
  var latestObservationByIssue = ({})
  for (var r = 0; r < normalized.resolutions.length; r++) {
    var resolution = normalized.resolutions[r]
    if (resolution.resolvedLocalDay <= end
        && (!latestResolutionByIssue[resolution.issueKey]
          || resolution.resolvedAtMs > latestResolutionByIssue[resolution.issueKey]))
      latestResolutionByIssue[resolution.issueKey] = resolution.resolvedAtMs
  }
  for (var o = 0; o < normalized.observations.length; o++) {
    var observation = normalized.observations[o]
    if (observation.localDay <= end
        && (!latestObservationByIssue[observation.issueKey]
        || observation.atMs > latestObservationByIssue[observation.issueKey])
      ) latestObservationByIssue[observation.issueKey] = observation.atMs
  }
  var count = 0
  var impact = 0
  for (var i = 0; i < normalized.observations.length; i++) {
    var row = normalized.observations[i]
    var issueResolvedAtMs = latestResolutionByIssue[row.issueKey] || 0
    if (issueResolvedAtMs > 0 && row.atMs <= issueResolvedAtMs) continue
    if (row.localDay < start || row.localDay > end) continue
    count++
    impact += row.impactMinutes
    totals[row.type].count++
    totals[row.type].impactMinutes += row.impactMinutes
    if (!issueMap[row.issueKey]) issueMap[row.issueKey] = {
      issueKey: row.issueKey,
      type: row.type,
      title: row.title,
      count: 0,
      impactMinutes: 0,
      latestAtMs: 0,
      latestImpactMinutes: row.impactMinutes
    }
    var issue = issueMap[row.issueKey]
    issue.count++
    issue.impactMinutes += row.impactMinutes
    if (row.atMs >= issue.latestAtMs) {
      issue.latestAtMs = row.atMs
      issue.latestImpactMinutes = row.impactMinutes
      issue.title = row.title
    }
  }
  var issues = []
  for (var key in issueMap) {
    var issue = issueMap[key]
    var resolvedAtMs = latestResolutionByIssue[key] || 0
    issue.resolvedAtMs = resolvedAtMs
    issue.status = resolvedAtMs === 0
      ? "open"
      : (latestObservationByIssue[key] > resolvedAtMs ? "returned" : "resolved")
    issues.push(issue)
  }
  issues.sort(issueSort)
  var topIssue = null
  for (var k = 0; k < issues.length; k++) {
    if (issues[k].status !== "resolved") {
      topIssue = issues[k]
      break
    }
  }
  var dominant = null
  for (var j = 0; j < TYPES.length; j++) {
    var type = TYPES[j]
    if (totals[type].count === 0) continue
    if (!dominant
        || totals[type].impactMinutes > totals[dominant].impactMinutes
        || (totals[type].impactMinutes === totals[dominant].impactMinutes
          && totals[type].count > totals[dominant].count)) dominant = type
  }
  return {
    fromDay: start,
    throughDay: end,
    observationCount: count,
    totalImpactMinutes: impact,
    byType: totals,
    dominantType: dominant,
    topIssue: topIssue,
    issues: issues
  }
}

function recurringIssues(state, throughDay, calendarDays, limit) {
  var issues = aggregate(state, throughDay, calendarDays).issues
  var active = []
  for (var i = 0; i < issues.length; i++)
    if (issues[i].status !== "resolved") active.push(issues[i])
  return active.slice(0, Math.max(1, Number(limit) || 3))
}

function countermeasureProgress(state) {
  var normalized = normalizeState(state)
  var active = normalized.activeCountermeasure
  var result = { count: 0, impactMinutes: 0 }
  if (!active) return result
  for (var i = 0; i < normalized.observations.length; i++) {
    var row = normalized.observations[i]
    if (row.issueKey === active.issueKey && row.atMs > active.startedAtMs) {
      result.count++
      result.impactMinutes += row.impactMinutes
    }
  }
  return result
}

function typeName(type) {
  var normalized = normalizedType(type)
  if (normalized === "muda") return "MUDA"
  if (normalized === "mura") return "MURA"
  if (normalized === "muri") return "MURI"
  return ""
}

function typeMeaning(type) {
  var normalized = normalizedType(type)
  if (normalized === "muda") return "WASTE"
  if (normalized === "mura") return "UNEVENNESS"
  if (normalized === "muri") return "OVERLOAD"
  return ""
}

function actionLabel(type) {
  var normalized = normalizedType(type)
  if (normalized === "muda") return "ELIMINATE"
  if (normalized === "mura") return "LEVEL"
  if (normalized === "muri") return "RELIEVE"
  return "IMPROVE"
}

function winLabel(type) {
  var normalized = normalizedType(type)
  if (normalized === "muda") return "ELIMINATED"
  if (normalized === "mura") return "STABILIZED"
  if (normalized === "muri") return "RELIEVED"
  return "IMPROVED"
}

function formatMinutes(value) {
  var minutes = Math.max(0, Math.floor(Number(value) || 0))
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  var remainder = minutes % 60
  return hours + "h" + (remainder > 0 ? " " + remainder + "m" : "")
}
