# @easy-vless/web

Vue 3 SPA for local VLESS connection profiles. Profile operations do not provision server accounts or revoke access; expiry and status are metadata. Metrics are displayed only as reported by `/api/status`.

From the repository root (Node 22):

```sh
npm ci
npm run dev --workspace=@easy-vless/web
npm run build --workspace=@easy-vless/web
npm run preview --workspace=@easy-vless/web
```

Root workspace manifests and package-lock.json must include this workspace before `npm ci`. Vite development and preview proxy `/api` to `http://127.0.0.1:3000`. Override with `API_TARGET` in the process environment or an apps/web `.env.local` file. This is server-side Vite configuration, not a browser secret.

If the backend uses `API_TOKEN`, enter its value under **API authentication**. It is sent as a bearer header only to same-origin `/api`, kept only in memory, and cleared on reload or with **Clear token**. Never put it in a `VITE_*` variable or bundle it into the build. Use HTTPS in deployments; clipboard access also requires HTTPS or localhost. Configuration views expose connection credentials intentionally.

## Supported profile settings

Only `raw` and `xhttp` REALITY transports are supported; gRPC and WebSocket are not supported. Raw allows `none` or `xtls-rprx-vision` flow. XHTTP always sends `flow: "none"`, which the script normalizes to an empty flow. Returned empty flows display as **none** and initialize the editor as **None**.

`expiryDays` is an optional nonnegative integer:

- `0` means no expiry and explicitly clears existing expiry metadata on edit.
- A positive integer sets expiry metadata in days.
- Leaving the field blank on edit omits `expiryDays`, preserving the existing expiry. It is deliberately not initialized from the stored expiry date.
- Leaving it blank on creation uses the backend's no-expiry default.

Expiry metadata never enforces server access restrictions.

Run frontend API and form-state regression tests from the repository root:

```sh
node --test apps/web/src/api.test.js
```

## Container

Build with the repository root context after the root lockfile is installed:

```sh
docker build -f apps/web/Dockerfile -t easy-vless-web .
```

The Node 22 build stage uses the root workspace lockfile with `npm ci`. nginx serves the SPA on port 80 and forwards `/api` unchanged, including Authorization, to `http://server:3000`. The backend must resolve as `server` on the container network. Terminate TLS at your deployment ingress. `API_TARGET` affects Vite only; the production upstream is defined in `nginx.conf`.
