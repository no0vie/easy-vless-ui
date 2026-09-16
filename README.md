# TODO

- Добавить проверку на безопасность для createScriptRunner
- Добавить поддержку 'grpc', 'ws', 'tcp'

# Easy VLESS UI

An npm-workspace monorepo with a Vue 3 SPA and an Express API around `scripts/service.sh`. Two Docker images deploy the API and nginx-hosted frontend separately.

## What this application manages

The original script generates **client connection profiles**, not server-side accounts. The UI manages the same `profiles/<name>.json` files:

- List/search/filter, create, inspect JSON and copy VLESS URI, edit transport/flow/expiry, clone, delete.
- Supported transports: **RAW and XHTTP with REALITY**. The original UI advertised gRPC/WebSocket, but the script does not implement them.
- New profiles use your existing server UUID and REALITY settings. Cloning preserves credentials. Deleting a profile **does not revoke server access**.
- Expiry is metadata only; no scheduler or server-side expiry enforcement exists.
- Live status, active connections, traffic and uptime are unavailable (`unknown`/`null`), not simulated.
- Changing a transport does not reconfigure the server. Its address, transport, flow and XHTTP settings must match your existing Xray deployment.

## Structure

```text
apps/
  server/
    server.js           Express routes, validation, auth and startup
    script-runner.js    Bounded execFile bridge; no shell interpolation
    test/               Route, runner and real-script integration tests
    Dockerfile
  web/
    src/
      App.vue           Profile dashboard
      components/       Dialog and profile form
      api.js            Same-origin HTTP client; token held in memory
      profile-form.js   Form defaults and payload shaping
    index.html
    vite.config.js      Development /api proxy
    nginx.conf          Production /api proxy and SPA fallback
    Dockerfile
scripts/
  service.sh            Original interactive tool + noninteractive JSON actions
  test_service.py       Isolated profile integration tests
compose.yaml
contract.md             HTTP/CLI contract and data semantics
```

The initial repository had a duplicated Vue SFC, no HTML/JavaScript SPA entry point, mixed frontend/backend dependencies, hardcoded server paths and shell-interpolated API commands. These have been replaced with runnable workspaces, a shared lockfile, name-based routes, argument-array execution and tests.

## Local development

Requirements: **Node.js 22.9+**, npm, Bash and Python 3.9+. JSON operations do not need root, Docker, jq or a running Xray process. The original interactive menu still requires its original Linux/root dependencies.

```sh
npm ci
cp .env.example .env
```

Edit `.env`:

1. Set `BASE_DIR` to an **absolute writable directory**, e.g. a directory under `.local/` in this checkout. The script creates `profiles/` there. If omitted, the existing `/opt/boris/vless-client` layout is used.
2. Set `VLESS_PUBLIC_HOST`, `VLESS_UUID`, `REALITY_PUBLIC_KEY` and `REALITY_SHORT_ID` from your existing server. Also set any non-default port/SNI/XHTTP settings.
3. Set `API_TOKEN` to a strong secret. It is optional for trusted localhost development, but required by Compose. You can generate one with `openssl rand -hex 32`.

Alternatively, set `ENV_FILE` to the original `client.env` and optionally `SECRETS_DIR` to the existing server secrets directory. **Remove VLESS/REALITY/XHTTP assignments from `.env` when they should come from `client.env`**: process environment takes precedence, including empty values. Missing credential values can fall back to `uuid`, `public.key` and `short-id` files in `SECRETS_DIR`.

```sh
npm run dev
```

Open the Vite URL (normally `http://localhost:5173`). Enter the token under **API authentication** and click Connect. It is held only in browser memory; reloading clears it. The API defaults to `127.0.0.1:3000`. Vite proxies `/api` to it, so no permissive CORS configuration is necessary.

Useful commands:

```sh
npm run dev:server       # API watch mode; loads root .env
npm run dev:web          # Vite only
npm run build            # Production SPA -> apps/web/dist
npm start                # API without watch mode; loads root .env
npm test                 # Node unit/integration tests + Python script tests
npm run test:script
```

`API_TARGET` overrides Vite's proxy destination. `HOST`, `PORT`, and `SCRIPT_PATH` configure API startup. Script paths are resolved independently of the process working directory; custom `SCRIPT_PATH` should be absolute. The production API does not serve the SPA: use nginx/the web container or a separate static host with an API proxy.

## Docker: two containers

Requirements: Docker Engine and **Docker Compose v2**. Populate the root `.env` as above; Compose requires the token and existing server connection settings.

```sh
docker compose up --build -d
docker compose logs -f server web
```

Open **http://localhost:8080** and enter `API_TOKEN`. `WEB_PORT` changes the published port.

- `web`: multi-stage Vue build, nginx static hosting and `/api` proxy to `server:3000`.
- `server`: Node 22, Bash and Python 3; runs as the non-root `node` user (UID/GID 1000), with a health check and no published API port.
- Named volume `profiles` persists `/data` across rebuilds. `docker compose down` retains it; **`down -v` deletes it**.
- No Docker socket, privileged container, host service control or Xray private key is needed.
- `.env`, local profile data and dependencies are excluded from Docker build contexts. Runtime environment credentials are still visible to Docker administrators.

Build separately from the repository root:

```sh
docker build -f apps/server/Dockerfile -t easy-vless-server .
docker build -f apps/web/Dockerfile -t easy-vless-web .
```

### Use existing profiles in Docker

Back up the existing directory first. Replace `profiles:/data` in the server volume configuration with a bind mount of the existing **base directory**, which contains `profiles/` and optionally `client.env`:

```yaml
volumes:
  - /absolute/path/to/vless-client:/data
```

The directory and files must be readable/writable by container UID 1000 (or configure `user:` for the intended host UID/GID). Existing script directories often have root-only `0700`/`0600` permissions; do not simply make credential files world-readable. Grant access deliberately or copy profiles into a dedicated app-owned directory. Compose passes connection settings as environment variables; these override a mounted `client.env`.

Profiles created by the original script load without migration. Legacy creation/expiry metadata is unknown. API writes keep the existing profile shape and add `_profile` metadata; returned `config` excludes that metadata. Names must match `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`; files with incompatible names are omitted, not modified. Back up and rename such files deliberately before managing them here.

## Security and operational limits

- Keep the app private. Compose binds only to localhost. Use an authenticated HTTPS reverse proxy or SSH tunnel for remote access; do not publish the Vite development server to the internet.
- A configured bearer token gates all `/api` routes. `/healthz` is a public liveness check, not a validation of server credentials or Xray reachability. This is single-admin authentication, not a multi-user/roles system.
- Profile JSON and VLESS URIs contain credentials. API responses are marked `no-store`; avoid logging/exporting them publicly.
- The API passes fixed actions and validated arguments to Bash via `execFile`, with time and output limits. JSON-mode configuration loading parses literal environment assignments and never sources shell code.
- JSON operations use private file permissions, atomic replacements and a cross-process lock. The legacy interactive tool does **not** share the lock: do not mutate profiles through both interfaces concurrently.
- API changes have no automatic backup/rollback. Back up the data volume. Deletion is irreversible without a backup.
- Native menu mode retains its existing behavior and dependencies; it is not the intended interface inside the minimal API image.
