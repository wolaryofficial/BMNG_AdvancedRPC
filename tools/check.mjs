import assert from 'node:assert/strict'
import { readFile, readdir } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
let requestId = Date.now()
export async function call(name, args = {}) {
  const response = await fetch('http://127.0.0.1:29292/mcp', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++requestId, method: 'tools/call', params: { name, arguments: args } }),
    signal: AbortSignal.timeout(30000),
  })
  if (!response.ok) throw new Error(`BeamNG MCP HTTP ${response.status}`)
  const data = await response.json()
  if (data.error || data.result?.isError) throw new Error(JSON.stringify(data))
  return data.result?.content?.find(x => x.type === 'text')?.text ?? data.result
}
export async function lua(code) {
  const result = await call('run_lua', { code })
  if (/^(error|compile error):/i.test(result)) throw new Error(result)
  try { return JSON.parse(result) } catch { return result }
}
export async function ui(js) {
  const tag = 'arpc-' + ++requestId
  const body = `if(window.__advancedRpcProbe?.tag===${JSON.stringify(tag)})return window.__advancedRpcProbe;try{return window.__advancedRpcProbe={tag:${JSON.stringify(tag)},data:(function(){${js}})()}}catch(e){return window.__advancedRpcProbe={tag:${JSON.stringify(tag)},error:String(e)}}`
  for (let i = 0; i < 8; i++) {
    const result = await call('ui_eval', { js: body })
    let decoded
    try { decoded = JSON.parse(result) } catch { decoded = result }
    if (decoded?.tag === tag) { if (decoded.error) throw new Error(decoded.error); return decoded.data }
    await new Promise(resolve => setTimeout(resolve, 250))
  }
  throw new Error('The BeamNG UI did not return the probe result.')
}

const quote = value => '[========[' + value + ']========]'
async function walk(path) {
  const entries = await readdir(path, { withFileTypes: true })
  return (await Promise.all(entries.filter(x => !['dist', 'github', '.git'].includes(x.name)).map(async x => x.isDirectory() ? walk(resolve(path, x.name)) : resolve(path, x.name)))).flat()
}

async function main() {
  const files = await walk(root)
  assert(!files.some(x => /readme/i.test(x)), 'No README files')
  const luaSources = {}
  for (const path of files) {
    if (/\.(lua|js|mjs|vue|ps1|cs)$/.test(path)) {
      const source = await readFile(path, 'utf8')
      assert(!/^\s*(--|\/\/|\/\*|<!--)/m.test(source), `No comments: ${path}`)
      if (path.endsWith('.lua')) luaSources[path.replaceAll('\\', '/')] = source
    }
  }
  const sourceTable = '{' + Object.entries(luaSources).map(([path, source]) => `[ ${quote(path)} ]=${quote(source)}`).join(',') + '}'
  const results = await lua(`local sources=${sourceTable} local results={} for path,source in pairs(sources) do local fn,err=loadstring(source,path) results[#results+1]={name='compile '..path,passed=fn~=nil,error=err} end local testSource=sources[ ${quote(root.replaceAll('\\', '/') + '/tests/unit.lua')} ] local test=assert(loadstring(testSource,'tests'))() local extra=test(sources) for _,result in ipairs(extra) do results[#results+1]=result end return jsonEncode(results)`)
  for (const result of results) console.log(`${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ': ' + result.error : ''}`)
  assert(results.every(x => x.passed), 'Lua checks failed')

  const { createSettingsModel, mergePatch, applyPatch } = await import(pathToFileURL(resolve(root, 'ui/ui-vue/mods/AdvancedRPC/settingsModel.js')))
  assert.deepEqual(mergePatch({ general: { enabled: false }, profiles: { a: { details: 'old' } } }, { general: { units: 'metric' }, profiles: { a: { state: 'new' } } }), { general: { enabled: false, units: 'metric' }, profiles: { a: { details: 'old', state: 'new' } } })
  let settings = { enabled: true, units: 'game', profiles: [{ id: 'a', details: 'before', state: 'state' }], rules: [] }, revision = 1, fail = false, conflict = true
  const state = { error: '', ready: false, revision: 0 }
  const model = createSettingsModel(state, async (method, args) => {
    if (method === 'getSettings') return { settings, revision, saved: true }
    if (method === 'getStatus') return { state: 'native' }
    if (method === 'setSettingsFromUI') {
      if (fail) throw new Error('Simulated connection failure')
      if (conflict) { conflict = false; settings.units = 'imperial'; revision++; return { settings, revision, conflict: true } }
      assert.equal(args.revision, revision)
      settings = applyPatch(settings, args.patch)
      return { settings, revision: ++revision, saved: true }
    }
  }, 100000)
  await model.load()
  model.edit({ profiles: { a: { details: 'after' } } })
  assert.equal(await model.flush(), true)
  assert.equal(settings.units, 'imperial')
  assert.equal(settings.profiles[0].details, 'after')
  fail = true
  model.edit({ profiles: { a: { state: 'retry me' } } })
  assert.equal(await model.flush(), false)
  assert.equal(state.config.profiles[0].state, 'retry me')
  fail = false
  assert.equal(await model.flush(), true)
  assert.equal(settings.profiles[0].state, 'retry me')
  model.edit({ general: { enabled: false } })
  await model.dispose()
  assert.equal(settings.enabled, false)
  console.log('PASS UI patch merging, revision conflict, failed-save retry, close flush, source hygiene')
  console.log(`PASS ${results.length} Lua checks and UI settings checks`)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  if (process.argv[2] === 'lua') console.log(JSON.stringify(await lua(process.argv[3]), null, 2))
  else if (process.argv[2] === 'ui') console.log(JSON.stringify(await ui(process.argv[3]), null, 2))
  else await main()
}
