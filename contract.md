# Profile API and script contract

All HTTP routes use the `/api` prefix and return JSON. When `API_TOKEN` is configured, send `Authorization: Bearer <token>`. All profile identifiers are **names**, not VLESS UUIDs: profiles may share the same server credentials.

Names match `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` and identify `PROFILE_DIR/<name>.json`.

## Operations

| HTTP | Script action | Payload/options | Response |
| --- | --- | --- | --- |
| GET `/api/clients` | `--list-clients` | — | `{clients, total, serverInfo}` |
| POST `/api/clients` | `--create-client` | `{name, transport?, flow?, expiryDays?}` | 201 `{success: true, client}` |
| GET `/api/clients/:name` | `--get-client --name NAME` | — | Client details |
| PUT `/api/clients/:name` | `--update-client --name NAME` | `{transport?, flow?, expiryDays?}` (at least one) | `{success: true, client}` |
| POST `/api/clients/:name/clone` | `--copy-client --name NAME` | `{newName}` → `--new-name NAME` | 201 `{success: true, client}` |
| DELETE `/api/clients/:name` | `--delete-client --name NAME` | — | `{success: true}` |
| GET `/api/status` | `--status` | — | `{server, clients, traffic}` |

HTTP JSON body fields map to `--name`, `--transport`, `--flow`, `--expiry`, and `--new-name`. Every API invocation appends `--format json`. Requests reject unknown fields, invalid types, unsafe names and unsupported transports. Errors are `{error: "message"}` with 400 (invalid input), 401 (authentication), 404 (not found), 409 (duplicate), 413 (body limit), 500 (execution/configuration failure), or 504 (script timeout).

## Settings

- `transport`: `raw` (default) or `xhttp`. gRPC/WebSocket are not implemented.
- `flow`: `xtls-rprx-vision`, `none` or `""`. `none` normalizes to `""` in stored data and responses. XHTTP requires empty flow. RAW creation defaults to Vision unless configured otherwise.
- `expiryDays`: integer 0–36500. `0` clears expiry; positive values set a UTC timestamp relative to the operation. Omission preserves existing expiry on update. This is **metadata**, not access enforcement.
- Copy retains credentials, settings and expiry and assigns a new creation timestamp. It does not provision a new server user.

## Client shape

List entries contain the following fields; detail and mutation responses additionally include `config` and `connectionString`:

```json
{
  "id": "phone",
  "name": "phone",
  "transport": "raw",
  "flow": "xtls-rprx-vision",
  "created": "2026-09-16T10:00:00Z",
  "expiry": null,
  "status": "unknown",
  "address": "vpn.example.com",
  "port": 443
}
```

`config` is the actual existing script profile schema: `{address, port, users: [{id, encryption, flow}], streamSettings: {network, security, realitySettings, xhttpSettings?}}`. It is a connection-profile fragment, not a full runnable Xray configuration. `connectionString` is a URL-encoded `vless://...` URI derived from that config. Internal `_profile` metadata is not returned in `config`.

List `serverInfo` is `{address, port, version: null}`. Legacy files without metadata return `created: null` and `expiry: null`.

## Status semantics

The script does not query or manage the running Xray server, so unavailable metrics are explicit:

```json
{
  "server": {"status": "unknown", "address": "vpn.example.com", "port": 443, "uptime": null},
  "clients": {"total": 2, "active": null},
  "traffic": {"today": null, "total": null}
}
```

## Direct CLI

```sh
bash scripts/service.sh --list-clients --format json
bash scripts/service.sh --create-client --name phone --transport raw --flow xtls-rprx-vision --expiry 30 --format json
bash scripts/service.sh --get-client --name phone --format json
bash scripts/service.sh --update-client --name phone --transport xhttp --flow none --format json
bash scripts/service.sh --copy-client --name phone --new-name laptop --format json
bash scripts/service.sh --delete-client --name laptop --format json
bash scripts/service.sh --status --format json
```

The CLI additionally accepts ISO dates/timezone-qualified timestamps or `null`/empty values for `--expiry`, and `--new-name` on update. JSON mode uses Bash + Python 3, emits only JSON to stdout, exits nonzero on errors, and never opens the interactive menu. Missing values, unknown flags, multiple actions and inappropriate options are errors rather than silently ignored arguments.

CLI errors are `{error, code}` where `code` is `VALIDATION_ERROR`, `NOT_FOUND`, `CONFLICT`, or `SCRIPT_ERROR`. Running **without arguments** retains the original interactive menu. See [README.md](README.md) for environment variables, storage, deployment and security.
