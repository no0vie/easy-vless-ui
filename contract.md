# 1 Получение списка клиентов

## Запрос
/opt/boris/vless-client/vless-manager.sh --list-clients --format json

## Ответ
{
  "clients": [
    {
      "id": "uuid",
      "name": "boris-phone",
      "status": "active|inactive|expired",
      "created": "2026-01-15T10:30:00Z",
      "expiry": "2026-12-31T23:59:59Z",
      "transport": "xhttp|raw|grpc|ws",
      "flow": "xtls-rprx-vision|none",
      "publicKey": "base64...",
      "shortId": "abcd1234",
      "serverName": "www.cloudflare.com",
      "fingerprint": "chrome",
      "lastHandshake": "2026-09-09T08:15:00Z"
    }
  ],
  "total": 5,
  "serverInfo": {
    "version": "2.0",
    "address": "192.168.1.200",
    "port": 443
  }
}

# 2 Создание клиента

## Запрос
/opt/boris/vless-client/vless-manager.sh --create-client \
  --name "boris-phone" \
  --transport "xhttp" \
  --flow "xtls-rprx-vision" \
  --format json

## Ответ
{
  "success": true,
  "client": {
    "id": "uuid",
    "name": "boris-phone",
    "status": "active",
    "config": {
      "address": "192.168.1.200",
      "port": 443,
      "uuid": "uuid",
      "flow": "xtls-rprx-vision",
      "transport": "xhttp",
      "reality": {
        "publicKey": "base64...",
        "shortId": "abcd1234",
        "serverName": "www.cloudflare.com",
        "fingerprint": "chrome"
      }
    },
    "connectionString": "vless://uuid@host:443?..."
  }
}

# 3 Получение конфига клиента

## Запрос
/opt/boris/vless-client/vless-manager.sh --get-client --name "boris-phone" --format json

## Ответ
{
  "id": "uuid",
  "name": "boris-phone",
  "status": "active",
  "config": { ... },
  "connectionString": "vless://..."
}

# 4 Изменение транспорта клиента

## Запрос
/opt/boris/vless-client/vless-manager.sh --update-client \
  --name "boris-phone" \
  --transport "grpc" \
  --format json

## Ответ
{
  "success": true,
  "message": "Transport updated",
  "client": { ... }
}

# 5 Копирование клиента

## Запрос
/opt/boris/vless-client/vless-manager.sh --copy-client \
  --name "boris-phone" \
  --new-name "boris-laptop" \
  --format json

## Ответ
{
  "success": true,
  "client": { ... }
}

# 6 Удаление клиента

## Запрос
/opt/boris/vless-client/vless-manager.sh --delete-client --name "boris-phone" --format json

## Ответ
{
  "success": true
}

# 7 Статус сервера 

## Запрос
/opt/boris/vless-client/vless-manager.sh --status --format json

## Ответ
{
  "server": {
    "status": "running",
    "address": "192.168.1.200",
    "port": 443,
    "uptime": "15d 4h 32m"
  },
  "clients": {
    "active": 3,
    "total": 5
  },
  "traffic": {
    "today": "1.2 GB",
    "total": "45.6 GB"
  }
}
