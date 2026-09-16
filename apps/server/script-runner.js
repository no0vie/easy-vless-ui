import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { fileURLToPath } from 'node:url'

const execFileAsync = promisify(execFile)
const defaultScript = fileURLToPath(new URL('../../scripts/service.sh', import.meta.url))
const statusCodes = { VALIDATION_ERROR: 400, NOT_FOUND: 404, CONFLICT: 409 }

export class ApiError extends Error {
  constructor(message, status = 500) {
    super(message)
    this.status = status
  }
}

export function createScriptRunner({ scriptPath = process.env.SCRIPT_PATH || defaultScript,
  timeout = 15000, env = process.env, execute = execFileAsync } = {}) {
  return async args => {
    let stdout
    try {
      // Never interpolate request data into a shell command.
      ;({ stdout } = await execute('bash', [scriptPath, ...args, '--format', 'json'], {
        env, timeout, maxBuffer: 8 * 1024 * 1024, encoding: 'utf8',
      }))
    } catch (error) {
      if (error.killed || error.code === 'ETIMEDOUT') throw new ApiError('Profile operation timed out.', 504)
      let result
      try { result = JSON.parse(error.stdout) } catch { /* Not a structured script error. */ }
      const status = statusCodes[result?.code]
      if (status && typeof result.error === 'string') throw new ApiError(result.error, status)
      // Do not expose filesystem paths, secrets, or process output to API consumers.
      throw new ApiError('Profile script failed. Check server configuration and profile files.')
    }
    let result
    try { result = JSON.parse(stdout) } catch {
      throw new ApiError('Profile script returned invalid JSON.')
    }
    if (!result || typeof result !== 'object' || Array.isArray(result)) {
      throw new ApiError('Profile script returned an invalid response.')
    }
    if (result.error || result.success === false) {
      throw new ApiError(statusCodes[result.code] ? result.error : 'Profile operation failed.', statusCodes[result.code] || 500)
    }
    return result
  }
}
