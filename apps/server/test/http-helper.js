import { once } from 'node:events'

export async function serve(t, app) {
  const server = app.listen(0, '127.0.0.1')
  t.after(() => new Promise((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve())
    server.closeAllConnections()
  }))
  await once(server, 'listening')
  const base = `http://127.0.0.1:${server.address().port}`
  return async (path, { body, raw, headers, ...options } = {}) => {
    const response = await fetch(`${base}${path}`, {
      ...options,
      headers: { ...(body !== undefined || raw !== undefined ? { 'Content-Type': 'application/json' } : {}), ...headers },
      body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
      signal: AbortSignal.timeout(10000),
    })
    return { status: response.status, headers: response.headers, data: await response.json() }
  }
}
