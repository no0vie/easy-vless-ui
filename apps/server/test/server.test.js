import test from 'node:test'
import assert from 'node:assert/strict'
import { createApp } from '../server.js'
import { ApiError } from '../script-runner.js'
import { serve } from './http-helper.js'

test('HTTP routes map profile names and settings to exact argv', async t => {
  const calls = []
  const result = { client: { name: 'phone', id: 'phone', config: { users: [{ id: '12345678-1234-4234-8234-123456789abc' }] } } }
  const request = await serve(t, createApp({ apiToken: '', runScript: async args => { calls.push(args); return result } }))
  const cases = [
    ['GET', '/api/clients', undefined, 200, ['--list-clients']],
    ['GET', '/api/status', undefined, 200, ['--status']],
    ['POST', '/api/clients', { name: 'phone', transport: 'raw', flow: 'xtls-rprx-vision', expiryDays: 30 }, 201, ['--create-client', '--name', 'phone', '--transport', 'raw', '--flow', 'xtls-rprx-vision', '--expiry', '30']],
    ['GET', '/api/clients/phone', undefined, 200, ['--get-client', '--name', 'phone']],
    ['PUT', '/api/clients/phone', { transport: 'xhttp', flow: '', expiryDays: 0 }, 200, ['--update-client', '--name', 'phone', '--transport', 'xhttp', '--flow', '', '--expiry', '0']],
    ['POST', '/api/clients/phone/clone', { newName: 'tablet' }, 201, ['--copy-client', '--name', 'phone', '--new-name', 'tablet']],
    ['DELETE', '/api/clients/phone', undefined, 200, ['--delete-client', '--name', 'phone']],
    ['POST', '/api/clients', { name: 'A'.repeat(64), flow: 'none', expiryDays: 36500 }, 201, ['--create-client', '--name', 'A'.repeat(64), '--flow', 'none', '--expiry', '36500']],
  ]
  for (const [method, path, body, status, args] of cases) {
    const response = await request(path, { method, body })
    assert.equal(response.status, status)
    assert.deepEqual(response.data, result)
    assert.deepEqual(calls.at(-1), args)
    assert.equal(response.headers.get('cache-control'), 'no-store')
    assert.equal(response.headers.get('x-powered-by'), null)
  }
  assert.equal(calls.length, cases.length)
})

test('health is public; bearer authentication gates API before parsing or execution', async t => {
  let calls = 0
  const request = await serve(t, createApp({ apiToken: 'test-token', runScript: async () => { calls++; return { total: 0 } } }))
  assert.deepEqual((await request('/healthz')).data, { status: 'ok' })
  for (const authorization of ['', 'test-token', 'Basic test-token', 'Bearer wrong-token', 'Bearer test-tokeN']) {
    const response = await request('/api/clients', { method: 'POST', raw: '{', headers: { authorization } })
    assert.equal(response.status, 401)
    assert.deepEqual(response.data, { error: 'Unauthorized.' })
    assert.equal(response.headers.get('cache-control'), 'no-store')
  }
  assert.equal(calls, 0)
  assert.equal((await request('/api/clients', { headers: { authorization: 'Bearer test-token' } })).status, 200)
  assert.equal(calls, 1)
})

test('rejects malformed payloads, unknown fields and invalid settings without executing', async t => {
  const calls = []
  const request = await serve(t, createApp({ apiToken: '', runScript: async args => { calls.push(args); return {} } }))
  const cases = [
    ['POST', '/api/clients', {}], ['POST', '/api/clients', []], ['POST', '/api/clients', null],
    ['POST', '/api/clients', { name: 'phone', uuid: 'credential' }],
    ['PUT', '/api/clients/phone', {}], ['PUT', '/api/clients/phone', { name: 'renamed' }],
    ['POST', '/api/clients/phone/clone', {}],
    ['POST', '/api/clients/phone/clone', { newName: 'copy', expiryDays: 1 }],
  ]
  for (const transport of ['tcp', 'grpc', 'ws', '', null, 1]) cases.push(['POST', '/api/clients', { name: 'phone', transport }])
  for (const flow of ['vision', null, 1]) cases.push(['PUT', '/api/clients/phone', { flow }])
  cases.push(['POST', '/api/clients', { name: 'phone', transport: 'xhttp', flow: 'xtls-rprx-vision' }])
  for (const expiryDays of [-1, 1.5, 36501, '30', null, true]) cases.push(['PUT', '/api/clients/phone', { expiryDays }])
  for (const [method, path, body] of cases) {
    const response = await request(path, { method, body })
    assert.equal(response.status, 400, JSON.stringify({ method, path, body }))
    assert.equal(typeof response.data.error, 'string')
  }
  for (const raw of ['{', '"phone"', '42']) {
    assert.equal((await request('/api/clients', { method: 'POST', raw })).status, 400)
  }
  assert.equal((await request('/api/clients', { method: 'POST' })).status, 400)
  const oversized = await request('/api/clients', { method: 'POST', body: { name: 'a'.repeat(17000) } })
  assert.equal(oversized.status, 413)
  assert.deepEqual(oversized.data, { error: 'Request body is too large.' })
  assert.equal((await request('/api/unknown')).status, 404)
  assert.equal((await request('/api/clients', { method: 'PATCH', body: {} })).status, 404)
  assert.deepEqual(calls, [])
})

test('rejects shell injection, path traversal and option-like profile names', async t => {
  let calls = 0
  const request = await serve(t, createApp({ apiToken: '', runScript: async () => { calls++; return {} } }))
  for (const name of ['', '-x', '../escape', 'a/b', 'a.b', 'é', 'a'.repeat(65), 'a;id', '$(id)', '`id`', 'a\nb', 'a\u0000b']) {
    assert.equal((await request('/api/clients', { method: 'POST', body: { name } })).status, 400, name)
    assert.equal((await request('/api/clients/phone/clone', { method: 'POST', body: { newName: name } })).status, 400, name)
    if (!name) continue
    const path = `/api/clients/${encodeURIComponent(name)}`
    for (const method of ['GET', 'PUT', 'DELETE']) {
      assert.equal((await request(path, { method, ...(method === 'PUT' ? { body: { expiryDays: 1 } } : {}) })).status, 400, `${method} ${name}`)
    }
    assert.equal((await request(`${path}/clone`, { method: 'POST', body: { newName: 'safe' } })).status, 400)
  }
  assert.equal(calls, 0)
})

test('async runner errors preserve API status but hide unexpected internals', async t => {
  for (const status of [400, 404, 409, 504, 500]) {
    const request = await serve(t, createApp({ apiToken: '', runScript: async () => { throw new ApiError('Operation failed.', status) } }))
    const response = await request('/api/clients')
    assert.equal(response.status, status)
    assert.deepEqual(response.data, { error: 'Operation failed.' })
  }
  const request = await serve(t, createApp({ apiToken: '', runScript: async () => { throw new Error('/private/secret token=value') } }))
  const response = await request('/api/status')
  assert.equal(response.status, 500)
  assert.deepEqual(response.data, { error: 'Internal server error.' })
})
