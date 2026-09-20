export const VERSION = "1.0.0"
export const clone = value => JSON.parse(JSON.stringify(value))

export function normalize(settings) {
  const result = clone(settings)
  result.rules = Array.isArray(result.rules) ? result.rules : []
  for (const profile of result.profiles) {
    for (const key of ['buttons', 'detailsVariants', 'stateVariants', 'mapImages', 'vehicleImages']) profile[key] = Array.isArray(profile[key]) ? profile[key] : []
  }
  return result
}

export function mergePatch(older = {}, newer = {}) {
  const result = { general: { ...older.general, ...newer.general }, profiles: {} }
  for (const [id, fields] of Object.entries(older.profiles || {})) result.profiles[id] = { ...fields }
  for (const [id, fields] of Object.entries(newer.profiles || {})) result.profiles[id] = { ...result.profiles[id], ...fields }
  if (older.rules !== undefined) result.rules = clone(older.rules)
  if (newer.rules !== undefined) result.rules = clone(newer.rules)
  return result
}

export function applyPatch(settings, patch) {
  const result = clone(settings)
  Object.assign(result, patch.general || {})
  for (const profile of result.profiles) Object.assign(profile, patch.profiles?.[profile.id] || {})
  if (patch.rules !== undefined) result.rules = clone(patch.rules)
  return result
}

const hasChanges = patch => Object.keys(patch.general || {}).length || Object.keys(patch.profiles || {}).length || patch.rules !== undefined

export function createSettingsModel(state, call, delay = 400) {
  let pending = {}, inFlight = {}, timer, saving, disposed = false
  let baseline, baselineRevision = -1

  function accept(result) {
    if (!result?.settings || typeof result.revision !== "number" || result.revision < baselineRevision) return
    baseline = normalize(result.settings)
    baselineRevision = result.revision
    state.revision = result.revision
    state.config = applyPatch(baseline, mergePatch(inFlight, pending))
    state.saved = result.saved !== false
  }

  async function load() {
    state.error = ""
    try {
      const result = await call("getSettings")
      if (!result?.settings) throw new Error(result?.error || "Enable AdvancedRPC in Mod Manager, then retry.")
      accept(result)
      state.variables = result.variables || {}
      state.contexts = result.contexts || ["any"]
      state.ready = true
      state.error = result.error || ""
      state.status = await call("getStatus")
    } catch (error) { state.error = error.message || String(error) }
  }

  function flush() {
    clearTimeout(timer)
    if (saving) return saving
    if (!hasChanges(pending)) return Promise.resolve(!state.error)
    state.busy = true
    saving = (async () => {
      while (hasChanges(pending)) {
        inFlight = pending
        pending = {}
        try {
          let result
          for (let attempt = 0; attempt < 4; attempt++) {
            result = await call("setSettingsFromUI", { revision: state.revision, patch: inFlight })
            if (!result?.conflict) break
            accept(result)
          }
          if (result?.conflict) throw new Error("Settings changed repeatedly. Retry saving.")
          if (!result?.settings) throw new Error(result?.error || "The settings controller did not respond.")
          inFlight = {}
          accept(result)
          state.error = result.error || ""
        } catch (error) {
          pending = mergePatch(inFlight, pending)
          inFlight = {}
          state.error = error.message || String(error)
          state.dirty = true
          return false
        }
      }
      state.dirty = false
      return true
    })().finally(() => { state.busy = false; saving = null })
    return saving
  }

  function edit(patch) {
    if (disposed || !state.ready) return
    pending = mergePatch(pending, patch)
    state.config = applyPatch(state.config, patch)
    state.dirty = true
    clearTimeout(timer)
    timer = setTimeout(flush, delay)
  }

  async function action(method, args = {}) {
    if (!await flush()) return null
    state.busy = true
    try {
      const result = await call(method, { ...args, revision: state.revision })
      if (result?.conflict) {
        accept(result)
        throw new Error("Settings changed. Please repeat this action.")
      }
      if (result?.error && !result?.settings) throw new Error(result.error)
      accept(result)
      state.error = result?.error || ""
      return result
    } catch (error) {
      state.error = error.message || String(error)
      return null
    } finally { state.busy = false }
  }

  function discard() {
    if (saving) return
    pending = {}
    state.dirty = false
    state.error = ""
    if (baseline) state.config = clone(baseline)
  }

  async function dispose() {
    disposed = true
    clearTimeout(timer)
    return flush()
  }

  return { load, accept, edit, flush, action, discard, dispose }
}
