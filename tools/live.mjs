import assert from 'node:assert/strict'
import { lua, ui, call } from './check.mjs'

const wait = ms => new Promise(resolve => setTimeout(resolve, ms))
const ge = code => lua(`return jsonEncode((function() ${code} end)())`)
const settings = () => ge('return extensions.advancedRPC.getSettings()')

async function until(fn, label) {
  for (let attempt = 0; attempt < 32; attempt++) {
    if (await fn()) return
    await wait(250)
  }
  throw new Error('Timed out: ' + label)
}
async function open() {
  await call('set_ui_state', { route: 'pause' })
  await until(() => ui('return [...document.querySelectorAll("button")].some(b=>b.textContent.trim().endsWith("Mods"))'), 'Mods tab')
  await ui('const b=[...document.querySelectorAll("button")].find(b=>b.textContent.trim().endsWith("Mods"));b.click();return true')
  await until(() => ui('return [...document.querySelectorAll("button")].some(b=>b.textContent.trim().endsWith("AdvancedRPC"))'), 'AdvancedRPC entry')
  await ui('const b=[...document.querySelectorAll("button")].find(b=>b.textContent.trim().endsWith("AdvancedRPC"));b.click();return true')
  await until(() => ui('return !!document.querySelector("[data-tab=Profiles]") && !document.querySelector(".arpc-error")'), 'settings mount')
}
async function tab(name) {
  await ui(`document.querySelector('[data-tab=${JSON.stringify(name)}]').click();return true`)
}
async function click(action) {
  await ui(`document.querySelector('[data-action=${JSON.stringify(action)}]').click();return true`)
}
async function input(field, value) {
  await ui(`const e=document.querySelector('[data-field=${JSON.stringify(field)}] input');if(!e)throw new Error('Missing input');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,${JSON.stringify(value)});e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return true`)
}

const initial = await settings()
const initialCount = initial.settings.profiles.length
const created = []
try {
  await open()
  assert.equal(await ui('return document.querySelector(".arpc-credit").textContent'), 'made by wolary (w0kx)')
  assert.equal(await ui('return document.querySelector(".arpc-version").textContent'), 'v1.0.0')
  await until(() => ui('const icon=document.querySelector(".arpc-logo");return !!icon && icon.complete && icon.naturalWidth>0'), 'mod icon')
  assert((await settings()).contexts.includes('career_delivery'))
  assert((await settings()).variables.career_activity)
  await input('updateInterval', '1')
  await until(async () => (await settings()).settings.updateInterval === 1, 'fast interval autosave')
  await input('updateInterval', '8')
  await until(async () => (await settings()).settings.updateInterval === 8, 'interval autosave')
  assert.equal((await settings()).saved, true)
  console.log('PASS native menu, icon, credit, version, career controls and fast interval autosave')
  await tab('Profiles')
  await click('duplicate')
  await until(async () => (await settings()).settings.profiles.length === initialCount + 1, 'profile duplication')
  let snapshot = await settings()
  const duplicated = snapshot.settings.profiles.at(-1).id
  created.push(duplicated)
  await input('name', 'RPC validation')
  await until(async () => (await settings()).settings.profiles.some(p => p.id === duplicated && p.name === 'RPC validation'), 'profile rename')
  await tab('Text')
  const text = 'Cruising {map|Main menu} — "quoted" \\ route'
  await input('details', text)
  await until(async () => (await settings()).settings.profiles.some(p => p.id === duplicated && p.details === text), 'template autosave')
  await tab('Profiles')
  await click('export')
  await until(() => ui('return document.querySelector("[data-field=profileJson] textarea").value.length > 10'), 'profile export')
  const exported = await ui('return document.querySelector("[data-field=profileJson] textarea").value')
  assert.equal(JSON.parse(exported).profile.details, text)
  await click('import')
  await until(async () => (await settings()).settings.profiles.length === initialCount + 2, 'profile import')
  snapshot = await settings()
  created.push(snapshot.settings.profiles.at(-1).id)
  console.log('PASS duplicate, rename, Unicode/quote serialization, export and import')
  await tab('Rules')
  await click('add-rule')
  await until(async () => Array.isArray((await settings()).settings.rules) && (await settings()).settings.rules.length > 0, 'automatic rule')
  await until(async () => (await ge('return extensions.advancedRPC.getStatus()')).profileId === created.at(-1), 'rule activation')
  await tab('Images')
  await input('largeImage', 'lvl_italy')
  await until(async () => (await settings()).settings.profiles.at(-1).largeImage === 'lvl_italy', 'image edit')
  const externalImages = true
  if (externalImages) {
    await input('largeImage', 'https://cdn.discordapp.com/embed/avatars/0.png')
    await input('smallImage', 'https://cdn.discordapp.com/embed/avatars/1.png')
    await input('largeText', 'Карта: {map|Main menu}')
    await input('smallText', 'made by wolary (w0kx)')
    await until(async () => (await settings()).settings.profiles.at(-1).smallText === 'made by wolary (w0kx)', 'image captions autosave')
  }
  await tab('Preview')
  await until(() => ui('return !!document.querySelector(".arpc-presence")'), 'preview')
  assert((await ui('return document.querySelector(".arpc-presence").textContent')).includes('Cruising '))
  if (externalImages) {
    await until(() => ui('return document.querySelectorAll(".arpc-art [title]").length===2'), 'both image captions in preview')
    const titles = await ui('return [...document.querySelectorAll(".arpc-art [title]")].map(e=>e.title)')
    assert(titles[0].startsWith('Карта: '))
    assert.equal(titles[1], 'made by wolary (w0kx)')
    console.log('PASS both HTTPS image fields, Cyrillic captions and resolved preview hover text')
  }
  console.log('PASS ordered rules, image settings and rendered preview')
  await call('reload_ui')
  await until(() => ui('return window.bngUiBootstrap?.status?.done===true'), 'CEF reload')
  await open()
  snapshot = await settings()
  assert.equal(snapshot.settings.updateInterval, 8)
  assert.equal(snapshot.settings.profiles.length, initialCount + 2)
  assert.equal(snapshot.saved, true)
  console.log('PASS persistence after closing and reloading CEF')
} finally {
  await call('set_ui_state', { route: 'pause' })
  await wait(600)
  let current = await settings()
  const rules = JSON.stringify(initial.settings.rules).startsWith('[') ? initial.settings.rules : []
  const general = Object.fromEntries(['enabled', 'transport', 'applicationId', 'updateInterval', 'units', 'automatic', 'selectedProfileId'].map(key => [key, initial.settings[key]]))
  const args = JSON.stringify({ revision: current.revision, patch: { general, rules } })
  const patched = await ge(`return extensions.advancedRPC.setSettingsFromUI(jsonDecode([========[${args}]========]))`)
  assert(patched.settings && !patched.conflict, 'Restore initial settings')
  for (const id of created) {
    current = await settings()
    const request = JSON.stringify({ revision: current.revision, action: 'delete', id })
    const result = await ge(`return extensions.advancedRPC.profileAction(jsonDecode([========[${request}]========]))`)
    assert(result.settings, 'Remove validation profile')
  }
  const final = await settings()
  assert.equal(final.settings.profiles.length, initialCount)
  assert.equal(final.settings.updateInterval, initial.settings.updateInterval)
  assert.deepEqual(final.settings, initial.settings)
  console.log('PASS validation profiles removed; initial settings restored')
}
