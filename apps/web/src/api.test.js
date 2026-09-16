import test from 'node:test'
import assert from 'node:assert/strict'
import { api, namePattern, setToken, transports } from './api.js'
import { initialProfileForm, profileFormBody } from './profile-form.js'

const originalFetch = globalThis.fetch

test('API uses name-based same-origin routes, methods and bodies', async () => {
  const calls = []
  globalThis.fetch = async (url, options) => {
    calls.push({ url, ...options })
    return new Response(JSON.stringify({ success: true, client: { name: 'phone' } }))
  }
  try {
    await api.list()
    await api.status()
    await api.get('phone')
    await api.create({ name: 'phone', transport: 'raw', flow: 'none', expiryDays: 30 })
    await api.update('phone', { transport: 'xhttp' })
    await api.clone('phone', 'laptop')
    await api.remove('phone')
    assert.deepEqual(calls.map(call => [call.url, call.method]), [
      ['/api/clients', 'GET'], ['/api/status', 'GET'], ['/api/clients/phone', 'GET'],
      ['/api/clients', 'POST'], ['/api/clients/phone', 'PUT'],
      ['/api/clients/phone/clone', 'POST'], ['/api/clients/phone', 'DELETE'],
    ])
    assert.deepEqual(JSON.parse(calls[3].body), { name: 'phone', transport: 'raw', flow: 'none', expiryDays: 30 })
    assert.deepEqual(JSON.parse(calls[4].body), { transport: 'xhttp', flow: 'none' })
    assert.deepEqual(JSON.parse(calls[5].body), { newName: 'laptop' })
    assert.equal(calls[0].cache, 'no-store')
  } finally { globalThis.fetch = originalFetch }
})

test('only supported REALITY transports and raw flows are accepted', () => {
  assert.deepEqual(transports, ['raw', 'xhttp'])
  for (const transport of ['grpc', 'ws', 'tcp', '', undefined]) {
    assert.throws(() => api.create({ name: 'phone', transport }), /Only raw and xhttp/)
    assert.throws(() => api.update('phone', { transport }), /Only raw and xhttp/)
  }
  assert.throws(() => api.update('phone', { transport: 'raw', flow: 'invalid' }), /Invalid raw flow/)
})

test('API normalizes xhttp and empty raw flows without clearing omitted expiry', async () => {
  const bodies = []
  globalThis.fetch = async (_url, options) => {
    bodies.push(JSON.parse(options.body))
    return new Response('{}')
  }
  try {
    await api.create({ name: 'phone', transport: 'xhttp', flow: 'xtls-rprx-vision', expiryDays: 0 })
    await api.update('phone', { transport: 'xhttp', flow: '' })
    await api.update('phone', { transport: 'raw', flow: '' })
    await api.update('phone', { transport: 'raw', flow: 'none', expiryDays: 0 })
    await api.update('phone', { transport: 'raw', flow: 'xtls-rprx-vision', expiryDays: 30 })
    await api.update('phone', { transport: 'raw' })
    assert.deepEqual(bodies, [
      { name: 'phone', transport: 'xhttp', flow: 'none', expiryDays: 0 },
      { transport: 'xhttp', flow: 'none' },
      { transport: 'raw', flow: 'none' },
      { transport: 'raw', flow: 'none', expiryDays: 0 },
      { transport: 'raw', flow: 'xtls-rprx-vision', expiryDays: 30 },
      { transport: 'raw' },
    ])
  } finally { globalThis.fetch = originalFetch }
})

test('expiry rejects negatives, fractions and nonnumeric values before fetch', () => {
  for (const expiryDays of [-1, 1.5, NaN, Infinity, '0', null, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => api.create({ name: 'phone', transport: 'raw', expiryDays }), /nonnegative whole number/)
    assert.throws(() => api.update('phone', { transport: 'raw', expiryDays }), /nonnegative whole number/)
  }
})

test('editing normalizes returned empty flow and preserves expiry unless explicitly changed', () => {
  for (const transport of transports) {
    const form = initialProfileForm({ name: 'phone', transport, flow: '', expiry: '2030-01-01T00:00:00Z' })
    assert.equal(form.flow, 'none')
    assert.equal(form.expiryDays, '')
    assert.deepEqual(profileFormBody('edit', form), { transport, flow: 'none' })
    form.expiryDays = 0
    assert.equal(profileFormBody('edit', form).expiryDays, 0)
    form.expiryDays = '0'
    assert.equal(profileFormBody('edit', form).expiryDays, 0)
    form.expiryDays = '7'
    assert.equal(profileFormBody('edit', form).expiryDays, 7)
    form.expiryDays = ''
    assert.equal(Object.hasOwn(profileFormBody('edit', form), 'expiryDays'), false)
  }
  assert.equal(initialProfileForm({ transport: 'xhttp', flow: 'xtls-rprx-vision' }).flow, 'none')
  assert.equal(initialProfileForm({ transport: 'raw', flow: 'xtls-rprx-vision' }).flow, 'xtls-rprx-vision')
  assert.equal(profileFormBody('edit', { transport: 'xhttp', flow: 'xtls-rprx-vision', expiryDays: '' }).flow, 'none')
})

test('creation and cloning only submit their intended fields', () => {
  const form = initialProfileForm()
  form.name = 'phone'
  assert.deepEqual(profileFormBody('create', form), { name: 'phone', transport: 'raw', flow: 'none' })
  form.expiryDays = 0
  assert.equal(profileFormBody('create', form).expiryDays, 0)
  assert.deepEqual(profileFormBody('clone', form), { newName: 'phone' })
})

test('optional bearer token can be set and cleared', async () => {
  const headers = []
  globalThis.fetch = async (_url, options) => {
    headers.push(options.headers)
    return new Response('{}')
  }
  try {
    setToken(' session-only ')
    await api.list()
    setToken('')
    await api.list()
    assert.equal(headers[0].Authorization, 'Bearer session-only')
    assert.equal(headers[1].Authorization, undefined)
  } finally { setToken(''); globalThis.fetch = originalFetch }
})

test('unsafe profile identities are rejected before fetch', () => {
  for (const name of ['../secret', 'a/b', '-name', 'a b', '', 'a'.repeat(65)]) {
    assert.equal(namePattern.test(name), false)
    assert.throws(() => api.get(name), /Invalid profile name/)
  }
  for (const name of ['A', 'phone-1_test', 'a'.repeat(64)]) assert.equal(namePattern.test(name), true)
})

test('API errors are actionable without exposing HTML responses', async () => {
  try {
    globalThis.fetch = async () => new Response('{"error":"Unauthorized"}', { status: 401 })
    await assert.rejects(api.list(), /valid API bearer token/)
    globalThis.fetch = async () => new Response('{"error":"Profile already exists"}', { status: 409 })
    await assert.rejects(api.list(), /Profile already exists/)
    globalThis.fetch = async () => new Response('<html>proxy failure</html>', { status: 502 })
    await assert.rejects(api.list(), /invalid response.*502/)
    globalThis.fetch = async () => { throw new TypeError('Failed to fetch') }
    await assert.rejects(api.list(), /Cannot reach the API/)
    globalThis.fetch = async () => new Response('{"success":false,"message":"Operation failed"}')
    await assert.rejects(api.list(), /Operation failed/)
  } finally { globalThis.fetch = originalFetch }
})
