let token = ''
export const namePattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/
export const transports = ['raw', 'xhttp']
export function setToken(value) { token = value.trim() }

async function request(path, method = 'GET', body) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 20000)
  try {
    const response = await fetch(`/api${path}`, {
      method,
      signal: controller.signal,
      cache: 'no-store',
      headers: {
        Accept: 'application/json',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    })
    const text = await response.text()
    let data
    try { data = text ? JSON.parse(text) : null } catch {
      throw new Error(`API returned an invalid response (HTTP ${response.status}). Check the API proxy.`)
    }
    if (!response.ok || data?.success === false) {
      const detail = typeof data?.error === 'string' ? data.error : data?.message
      throw new Error(response.status === 401 || response.status === 403
        ? 'Access denied. Enter a valid API bearer token and reconnect.'
        : typeof detail === 'string' ? detail : `Request failed (HTTP ${response.status}).`)
    }
    return data
  } catch (error) {
    if (error.name === 'AbortError') throw new Error('API request timed out. Please retry.')
    if (error instanceof TypeError) throw new Error('Cannot reach the API. Check your connection and retry.')
    throw error
  } finally { clearTimeout(timeout) }
}

function path(name) {
  if (!namePattern.test(name)) throw new Error('Invalid profile name.')
  return `/clients/${encodeURIComponent(name)}`
}

function profileBody(body) {
  if (!transports.includes(body.transport)) throw new Error('Only raw and xhttp REALITY transports are supported.')
  if (body.expiryDays !== undefined && (!Number.isSafeInteger(body.expiryDays) || body.expiryDays < 0)) {
    throw new Error('Expiry days must be a nonnegative whole number (0 means no expiry).')
  }
  const normalized = { ...body }
  if (body.transport === 'xhttp') normalized.flow = 'none'
  else if (body.flow !== undefined) {
    normalized.flow = body.flow === '' ? 'none' : body.flow
    if (!['none', 'xtls-rprx-vision'].includes(normalized.flow)) throw new Error('Invalid raw flow.')
  }
  return normalized
}

export const api = {
  list: () => request('/clients'),
  status: () => request('/status'),
  get: name => request(path(name)),
  create: body => request('/clients', 'POST', profileBody(body)),
  update: (name, body) => request(path(name), 'PUT', profileBody(body)),
  clone: (name, newName) => request(`${path(name)}/clone`, 'POST', { newName }),
  remove: name => request(path(name), 'DELETE'),
}
