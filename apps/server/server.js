import express from 'express'
import { timingSafeEqual } from 'node:crypto'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ApiError, createScriptRunner } from './script-runner.js'

const namePattern = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/
function name(value, field = 'name') {
  if (typeof value !== 'string' || !namePattern.test(value)) {
    throw new ApiError(`${field} must be 1–64 letters, digits, underscores or hyphens, starting with a letter or digit.`, 400)
  }
  return value
}
function bodyFields(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new ApiError('A JSON object is required.', 400)
  if (Object.keys(body).some(key => !allowed.includes(key))) throw new ApiError('Unknown request field.', 400)
}
function settings(body) {
  const args = []
  if (body.transport !== undefined) {
    if (!['raw', 'xhttp'].includes(body.transport)) throw new ApiError('Supported transports are raw and xhttp.', 400)
    args.push('--transport', body.transport)
  }
  if (body.flow !== undefined) {
    if (!['', 'none', 'xtls-rprx-vision'].includes(body.flow)) throw new ApiError('Unsupported flow.', 400)
    if (body.transport === 'xhttp' && body.flow === 'xtls-rprx-vision') throw new ApiError('XHTTP does not support Vision flow.', 400)
    args.push('--flow', body.flow)
  }
  if (body.expiryDays !== undefined) {
    if (!Number.isInteger(body.expiryDays) || body.expiryDays < 0 || body.expiryDays > 36500) {
      throw new ApiError('expiryDays must be an integer from 0 to 36500.', 400)
    }
    args.push('--expiry', String(body.expiryDays))
  }
  return args
}
function authorized(header, token) {
  const actual = Buffer.from(header || '')
  const expected = Buffer.from(`Bearer ${token}`)
  return actual.length === expected.length && timingSafeEqual(actual, expected)
}

export function createApp({ runScript = createScriptRunner(), apiToken = process.env.API_TOKEN || '' } = {}) {
  const app = express()
  app.disable('x-powered-by')
  app.get('/healthz', (_req, res) => res.json({ status: 'ok' }))
  app.use('/api', (_req, res, next) => { res.set('Cache-Control', 'no-store'); next() })
  app.use('/api', (req, _res, next) => {
    if (apiToken && !authorized(req.get('authorization'), apiToken)) return next(new ApiError('Unauthorized.', 401))
    next()
  })
  app.use(express.json({ limit: '16kb' }))
  const route = handler => (req, res, next) => Promise.resolve().then(() => handler(req, res)).catch(next)
  app.get('/api/clients', route(async (_req, res) => res.json(await runScript(['--list-clients']))))
  app.get('/api/status', route(async (_req, res) => res.json(await runScript(['--status']))))
  app.post('/api/clients', route(async (req, res) => {
    bodyFields(req.body, ['name', 'transport', 'flow', 'expiryDays'])
    const args = ['--create-client', '--name', name(req.body.name), ...settings(req.body)]
    res.status(201).json(await runScript(args))
  }))
  app.get('/api/clients/:name', route(async (req, res) => {
    res.json(await runScript(['--get-client', '--name', name(req.params.name)]))
  }))
  app.put('/api/clients/:name', route(async (req, res) => {
    bodyFields(req.body, ['transport', 'flow', 'expiryDays'])
    const args = settings(req.body)
    if (!args.length) throw new ApiError('At least one setting is required.', 400)
    res.json(await runScript(['--update-client', '--name', name(req.params.name), ...args]))
  }))
  app.post('/api/clients/:name/clone', route(async (req, res) => {
    bodyFields(req.body, ['newName'])
    res.status(201).json(await runScript(['--copy-client', '--name', name(req.params.name), '--new-name', name(req.body.newName, 'newName')]))
  }))
  app.delete('/api/clients/:name', route(async (req, res) => {
    res.json(await runScript(['--delete-client', '--name', name(req.params.name)]))
  }))
  app.use((_req, _res, next) => next(new ApiError('Not found.', 404)))
  app.use((error, _req, res, _next) => {
    const status = error instanceof ApiError ? error.status : error.status === 413 ? 413 : error.status === 400 ? 400 : 500
    const message = error instanceof ApiError ? error.message : status === 413 ? 'Request body is too large.' : status === 400 ? 'Invalid JSON request.' : 'Internal server error.'
    if (status >= 500) console.error(`API error (${status}): ${message}`)
    res.status(status).json({ error: message })
  })
  return app
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000)
  const host = process.env.HOST || '127.0.0.1'
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be between 1 and 65535.')
  if (!process.env.API_TOKEN) console.warn('API_TOKEN is unset: use only on a trusted local interface.')
  const server = createApp().listen(port, host, () => console.log(`VLESS profile API listening on ${host}:${port}`))
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      server.close(() => process.exit(0))
      setTimeout(() => process.exit(1), 10000).unref()
    })
  }
}
