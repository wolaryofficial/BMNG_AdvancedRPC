export function classifyImage(source, transport = 'native') {
  const value = typeof source === 'string' ? source : ''
  if (!value) return { code: 'empty' }
  const limit = transport === 'native' ? 127 : 512
  if (new TextEncoder().encode(value).length > limit) return { code: 'too_long', limit }
  if (/\s|[\u0000-\u001f\u007f\\]/.test(value)) return { code: 'invalid' }
  if (!value.includes(':') && !value.includes('/')) return { code: 'asset', source: value }
  try {
    const parsed = new URL(value)
    if (!value.startsWith('https://') || parsed.protocol !== 'https:' || !parsed.hostname || parsed.username || parsed.password) return { code: 'invalid' }
  } catch { return { code: 'invalid' } }
  return { code: 'url', source: value }
}

export async function checkImage(source, transport, { signal, timeout = 8000, createImage = () => new Image(), fetchHead = globalThis.fetch, policyTarget = globalThis.document } = {}) {
  const result = classifyImage(source, transport)
  if (result.code !== 'url') return result
  if (signal?.aborted) return { code: 'cancelled' }
  const controller = new AbortController()
  let metadata, blockedByPolicy = false
  const policyViolation = event => {
    if (event.blockedURI === result.source || event.blockedURI === new URL(result.source).origin) blockedByPolicy = true
  }
  policyTarget?.addEventListener('securitypolicyviolation', policyViolation)
  if (fetchHead) {
    Promise.resolve().then(() => fetchHead(result.source, { method: 'HEAD', credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-cache', signal: controller.signal }))
      .then(response => { metadata = { status: response.status, type: response.headers.get('content-type') || '' } })
      .catch(() => {})
  }
  return await new Promise(resolve => {
    const image = createImage()
    let timer, settled = false
    const finish = value => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      controller.abort()
      policyTarget?.removeEventListener('securitypolicyviolation', policyViolation)
      signal?.removeEventListener('abort', abort)
      image.onload = image.onerror = null
      image.removeAttribute('src')
      resolve(value)
    }
    const abort = () => finish({ code: 'cancelled' })
    const failure = code => {
      if (metadata?.status >= 400 && ![403, 405, 501].includes(metadata.status)) return finish({ code: 'http_error', status: metadata.status })
      if (metadata?.status >= 200 && metadata.status < 300 && metadata.type && !/^(image\/|application\/octet-stream)/i.test(metadata.type)) return finish({ code: 'not_image', type: metadata.type.split(';')[0] })
      finish({ code: blockedByPolicy ? 'blocked' : code })
    }
    image.referrerPolicy = 'no-referrer'
    image.onload = () => image.naturalWidth > 0 && image.naturalHeight > 0 ? finish({ code: 'loaded', width: image.naturalWidth, height: image.naturalHeight }) : failure('unavailable')
    image.onerror = () => failure('unavailable')
    timer = setTimeout(() => failure('timeout'), timeout)
    signal?.addEventListener('abort', abort, { once: true })
    if (signal?.aborted) abort()
    else image.src = result.source
  })
}
