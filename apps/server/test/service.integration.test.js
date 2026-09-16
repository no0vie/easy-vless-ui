import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, readFile, rm, stat } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from '../server.js'
import { createScriptRunner } from '../script-runner.js'
import { serve } from './http-helper.js'

const uuid = '12345678-1234-4234-8234-123456789abc'

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'vless-api-test-'))
  t.after(() => rm(root, { recursive: true, force: true }))
  const env = {
    PATH: process.env.PATH,
    BORIS_ROOT: root,
    BASE_DIR: join(root, 'base'),
    PROFILE_DIR: join(root, 'profiles'),
    SECRETS_DIR: join(root, 'secrets'),
    ENV_FILE: join(root, 'client.env'),
    BACKUP_DIR: join(root, 'backups'),
    LOG: join(root, 'unused.log'),
  }
  await mkdir(env.SECRETS_DIR)
  const secrets = { uuid, 'public.key': 'fixture-public-key', 'short-id': 'aabb' }
  for (const [name, value] of Object.entries(secrets)) await writeFile(join(env.SECRETS_DIR, name), `${value}\n`)
  await writeFile(env.ENV_FILE, "VLESS_PUBLIC_HOST='vpn.example.com'\nVLESS_PORT='8443'\n")
  const runScript = createScriptRunner({ env, scriptPath: fileURLToPath(new URL('../../../scripts/service.sh', import.meta.url)) })
  const request = await serve(t, createApp({ apiToken: 'integration-token', runScript }))
  const call = async (method, path, body, status = 200) => {
    const response = await request(path, { method, body, headers: { authorization: 'Bearer integration-token' } })
    assert.equal(response.status, status, JSON.stringify(response.data))
    return response.data
  }
  return { root, env, secrets, call }
}

function assertExpiry(expiry, days, before, after) {
  assert.match(expiry, /Z$/)
  const value = Date.parse(expiry)
  assert.ok(value >= before + days * 86400000, `${expiry} precedes requested expiry`)
  assert.ok(value <= after + days * 86400000, `${expiry} exceeds requested expiry`)
}

test('real service HTTP lifecycle uses profile names, preserves credentials and stores expiry days', { timeout: 30000 }, async t => {
  const { root, env, secrets, call } = await fixture(t)
  assert.equal((await call('GET', '/api/clients')).total, 0)
  const before = Date.now()
  const created = await call('POST', '/api/clients', { name: 'phone', expiryDays: 1 }, 201)
  const phone = created.client
  assert.equal(created.success, true)
  assert.equal(phone.id, 'phone')
  assert.equal(phone.name, 'phone')
  assert.equal(phone.config.users[0].id, uuid)
  assert.equal(phone.port, 8443)
  assert.equal(phone.config.streamSettings.realitySettings.publicKey, 'fixture-public-key')
  assert.equal(phone.config.streamSettings.realitySettings.shortId, 'aabb')
  assert.equal(phone.transport, 'raw')
  assert.equal(phone.flow, 'xtls-rprx-vision')
  assert.ok(Number.isFinite(Date.parse(phone.created)))
  assertExpiry(phone.expiry, 1, before, Date.now())
  assert.equal((await stat(join(env.PROFILE_DIR, 'phone.json'))).mode & 0o777, 0o600)
  assert.deepEqual(await call('GET', '/api/clients/phone'), phone)
  await call('GET', `/api/clients/${uuid}`, undefined, 404)
  await call('POST', '/api/clients', { name: 'phone' }, 409)

  const updateBefore = Date.now()
  const changed = (await call('PUT', '/api/clients/phone', { transport: 'xhttp', expiryDays: 30 })).client
  assert.equal(changed.id, 'phone')
  assert.equal(changed.transport, 'xhttp')
  assert.equal(changed.flow, '')
  assertExpiry(changed.expiry, 30, updateBefore, Date.now())
  const uri = new URL(changed.connectionString)
  assert.equal(uri.username, uuid)
  assert.equal(uri.hostname, 'vpn.example.com')
  assert.equal(uri.port, '8443')
  assert.equal(uri.searchParams.get('type'), 'xhttp')
  assert.equal(uri.searchParams.get('path'), '/xhttp')
  assert.equal(uri.searchParams.has('flow'), false)
  assert.deepEqual(await call('GET', '/api/clients/phone'), changed)

  const copied = (await call('POST', '/api/clients/phone/clone', { newName: 'tablet' }, 201)).client
  assert.equal(copied.id, 'tablet')
  assert.equal(copied.name, 'tablet')
  assert.deepEqual(copied.config, changed.config)
  assert.equal(copied.expiry, changed.expiry)
  assert.deepEqual(await call('GET', '/api/clients/tablet'), copied)
  await call('POST', '/api/clients/phone/clone', { newName: 'tablet' }, 409)
  const listed = await call('GET', '/api/clients')
  assert.equal(listed.total, 2)
  assert.deepEqual(listed.clients.map(client => client.id).sort(), ['phone', 'tablet'])
  const status = await call('GET', '/api/status')
  assert.equal(status.server.status, 'unknown')
  assert.equal(status.clients.total, 2)
  assert.equal(status.clients.active, null)
  assert.deepEqual(status.traffic, { today: null, total: null })

  assert.equal((await call('PUT', '/api/clients/phone', { expiryDays: 0 })).client.expiry, null)
  assert.equal((await call('GET', '/api/clients/phone')).expiry, null)
  assert.equal((await call('GET', '/api/clients/tablet')).expiry, copied.expiry)
  for (const name of ['phone', 'tablet']) {
    assert.deepEqual(await call('DELETE', `/api/clients/${name}`), { success: true })
    await call('GET', `/api/clients/${name}`, undefined, 404)
    await call('DELETE', `/api/clients/${name}`, undefined, 404)
    await assert.rejects(stat(join(env.PROFILE_DIR, `${name}.json`)), { code: 'ENOENT' })
  }
  assert.equal((await call('GET', '/api/clients')).total, 0)
  assert.equal((await call('GET', '/api/status')).clients.total, 0)
  for (const [name, value] of Object.entries(secrets)) assert.equal(await readFile(join(env.SECRETS_DIR, name), 'utf8'), `${value}\n`)
  await assert.rejects(stat(env.BACKUP_DIR), { code: 'ENOENT' })
  await assert.rejects(stat(join(root, 'unused.log')), { code: 'ENOENT' })
})

test('real service clears expiry at creation and rejects incompatible persisted transport settings', { timeout: 30000 }, async t => {
  const { call } = await fixture(t)
  const created = (await call('POST', '/api/clients', { name: 'zero', transport: 'xhttp', expiryDays: 0 }, 201)).client
  assert.equal(created.expiry, null)
  await call('PUT', '/api/clients/zero', { flow: 'xtls-rprx-vision' }, 400)
  assert.deepEqual(await call('GET', '/api/clients/zero'), created)
  const before = Date.now()
  const changed = (await call('PUT', '/api/clients/zero', { transport: 'raw', flow: 'none', expiryDays: 365 })).client
  assertExpiry(changed.expiry, 365, before, Date.now())
  assert.equal(changed.flow, '')
  assert.equal(changed.config.users[0].flow, '')
  assert.equal(new URL(changed.connectionString).searchParams.has('flow'), false)
  assert.deepEqual(await call('GET', '/api/clients/zero'), changed)
  await call('PUT', '/api/clients/missing', { expiryDays: 1 }, 404)
  await call('POST', '/api/clients/missing/clone', { newName: 'copy' }, 404)
})
