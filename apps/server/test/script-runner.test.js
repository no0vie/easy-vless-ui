import test from 'node:test'
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { ApiError, createScriptRunner } from '../script-runner.js'

function isApiError(status, message) {
  return error => {
    assert.ok(error instanceof ApiError)
    assert.equal(error.status, status)
    assert.equal(error.message, message)
    return true
  }
}

test('execute receives a fixed executable and separate literal argv, never a shell command', async () => {
  const env = { PATH: '/fixture/bin', PROFILE_DIR: '/fixture/profiles' }
  const scriptPath = '/fixture/path with spaces/service.sh'
  const args = ['--create-client', '--name', '$(touch marker); echo secret', '--flow', '']
  const original = [...args]
  let calls = 0
  const run = createScriptRunner({ scriptPath, env, timeout: 1234, execute: async (file, argv, options) => {
    calls++
    assert.equal(file, 'bash')
    assert.deepEqual(argv, [scriptPath, ...original, '--format', 'json'])
    assert.deepEqual(options, { env, timeout: 1234, maxBuffer: 8 * 1024 * 1024, encoding: 'utf8' })
    assert.equal(options.shell, undefined)
    assert.equal(options.env, env)
    return { stdout: '{"success":true}', stderr: 'not part of the response' }
  } })
  assert.deepEqual(await run(args), { success: true })
  assert.deepEqual(args, original)
  assert.equal(calls, 1)
})

test('runner defaults resolve the repository script and use bounded execution', async () => {
  const run = createScriptRunner({ execute: async (file, args, options) => {
    assert.equal(file, 'bash')
    assert.equal(args[0], process.env.SCRIPT_PATH || fileURLToPath(new URL('../../../scripts/service.sh', import.meta.url)))
    assert.deepEqual(args.slice(1), ['--status', '--format', 'json'])
    assert.equal(options.timeout, 15000)
    assert.equal(options.env, process.env)
    return { stdout: '{"server":{"status":"unknown"}}' }
  } })
  assert.deepEqual(await run(['--status']), { server: { status: 'unknown' } })
})

test('structured failures map to HTTP statuses on both success and nonzero exit', async () => {
  for (const [code, status] of [['VALIDATION_ERROR', 400], ['NOT_FOUND', 404], ['CONFLICT', 409]]) {
    for (const rejects of [false, true]) {
      const run = createScriptRunner({ execute: async () => {
        const stdout = JSON.stringify({ success: false, code, error: 'Fixture error.' })
        if (rejects) throw Object.assign(new Error('process failed'), { stdout })
        return { stdout }
      } })
      await assert.rejects(run([]), isApiError(status, 'Fixture error.'))
    }
  }
})

test('timeouts are 504 even when stdout contains a structured error', async () => {
  for (const details of [{ killed: true }, { code: 'ETIMEDOUT' }]) {
    const run = createScriptRunner({ execute: async () => {
      throw Object.assign(new Error('secret'), details, { stdout: '{"code":"NOT_FOUND","error":"secret"}' })
    } })
    await assert.rejects(run([]), isApiError(504, 'Profile operation timed out.'))
  }
})

test('unstructured execution failures and unknown error codes do not leak output', async () => {
  for (const details of [
    { code: 'ENOENT' }, { stdout: 'secret' }, { stdout: 'null' },
    { stdout: '{"code":"SCRIPT_ERROR","error":"private path and secret"}' },
    { stdout: '{"code":"NOT_FOUND","error":42}' },
  ]) {
    const run = createScriptRunner({ execute: async () => { throw Object.assign(new Error('secret'), details, { stderr: 'private key' }) } })
    await assert.rejects(run([]), isApiError(500, 'Profile script failed. Check server configuration and profile files.'))
  }
  for (const result of [{ error: 'secret', code: 'SCRIPT_ERROR' }, { success: false }]) {
    const run = createScriptRunner({ execute: async () => ({ stdout: JSON.stringify(result) }) })
    await assert.rejects(run([]), isApiError(500, 'Profile operation failed.'))
  }
})

test('rejects malformed JSON and non-object JSON responses', async () => {
  for (const stdout of ['', '{', 'log line\n{}']) {
    const run = createScriptRunner({ execute: async () => ({ stdout }) })
    await assert.rejects(run([]), isApiError(500, 'Profile script returned invalid JSON.'))
  }
  for (const stdout of ['null', '[]', 'true', '42', '"text"']) {
    const run = createScriptRunner({ execute: async () => ({ stdout }) })
    await assert.rejects(run([]), isApiError(500, 'Profile script returned an invalid response.'))
  }
})
