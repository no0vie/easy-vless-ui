<script setup>
import { computed, onMounted, ref } from 'vue'
import { api, namePattern, setToken, transports } from './api.js'
import AppDialog from './components/AppDialog.vue'
import ProfileForm from './components/ProfileForm.vue'

const clients = ref([])
const total = ref(null)
const status = ref(null)
const loading = ref(false)
const loaded = ref(false)
const listError = ref('')
const statusError = ref('')
const notice = ref('')
const tokenInput = ref('')
const authenticated = ref(false)
const query = ref('')
const transport = ref('')
const modal = ref(null)
const selected = ref(null)
const details = ref(null)
const busy = ref(false)
const detailLoading = ref(false)
const modalError = ref('')
const filtered = computed(() => clients.value.filter(client =>
  client.name.toLowerCase().includes(query.value.toLowerCase()) && (!transport.value || client.transport === transport.value)))
const display = value => value == null || value === '' ? 'Not available' : value
function date(value) {
  if (!value) return 'Not set'
  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString()
}
async function refresh() {
  if (loading.value) return
  loading.value = true
  listError.value = ''; statusError.value = ''
  await Promise.all([
    api.list().then(data => {
      if (!Array.isArray(data?.clients)) throw new Error('API returned an invalid profile list.')
      clients.value = data.clients; total.value = data.total; loaded.value = true
    }).catch(error => { listError.value = error.message }),
    api.status().then(data => { status.value = data }).catch(error => { status.value = null; statusError.value = error.message }),
  ])
  loading.value = false
}
async function reconnect(clear = false) {
  setToken(clear ? '' : tokenInput.value)
  authenticated.value = !clear && Boolean(tokenInput.value.trim())
  tokenInput.value = ''; clients.value = []; total.value = null; loaded.value = false; status.value = null; notice.value = ''
  await refresh()
}
function open(mode, client = null) {
  selected.value = client; details.value = null; modalError.value = ''; notice.value = ''; modal.value = mode
  if (mode === 'config') loadDetails()
}
function close() { if (!busy.value && !detailLoading.value) modal.value = null }
async function loadDetails() {
  detailLoading.value = true; modalError.value = ''
  try { details.value = await api.get(selected.value.name) } catch (error) { modalError.value = error.message }
  finally { detailLoading.value = false }
}
async function copyUri() {
  modalError.value = ''
  try {
    if (!details.value?.connectionString) throw new Error('No connection URI is available for this profile.')
    if (!navigator.clipboard) throw new Error('Clipboard requires HTTPS or localhost. Select and copy the URI below manually.')
    await navigator.clipboard.writeText(details.value.connectionString)
    notice.value = 'Connection URI copied.'
  } catch (error) { modalError.value = error.message || 'Clipboard access denied. Copy the URI manually.' }
}
async function save(body) {
  modalError.value = ''
  if ((modal.value === 'create' || modal.value === 'clone') && !namePattern.test(body.name ?? body.newName)) {
    modalError.value = 'Enter a valid profile name.'; return
  }
  if (body.expiryDays !== undefined && (!Number.isSafeInteger(body.expiryDays) || body.expiryDays < 0)) {
    modalError.value = 'Expiry days must be a nonnegative whole number (0 means no expiry).'; return
  }
  busy.value = true
  try {
    if (modal.value === 'create') await api.create(body)
    else if (modal.value === 'clone') await api.clone(selected.value.name, body.newName)
    else if (modal.value === 'edit') await api.update(selected.value.name, body)
    else await api.remove(selected.value.name)
    notice.value = modal.value === 'delete' ? 'Profile deleted.' : 'Profile saved.'
    modal.value = null
    await refresh()
  } catch (error) { modalError.value = error.message }
  finally { busy.value = false }
}
onMounted(refresh)
</script>

<template>
  <main>
    <header class="page-header">
      <div><p class="eyebrow">EASY VLESS</p><h1>Connection profiles</h1></div>
      <button class="primary" :disabled="loading || busy" @click="open('create')">Create profile</button>
    </header>
    <p class="intro">Manage local connection profiles, not server-provisioned accounts. Creating, editing or deleting a profile does not provision or revoke server access. Expiry is metadata only, not enforcement.</p>

    <details class="panel token-panel">
      <summary>API authentication · {{ authenticated ? 'token in memory' : 'no token set' }}</summary>
      <form class="token-form" @submit.prevent="reconnect()">
        <label>Optional bearer token<input v-model="tokenInput" type="password" autocomplete="off" placeholder="Enter API_TOKEN" :disabled="loading || busy"></label>
        <button :disabled="loading || busy || !tokenInput.trim()">Connect</button>
        <button type="button" :disabled="loading || busy" @click="reconnect(true)">Clear token</button>
      </form>
      <p class="muted">Only required when the backend sets API_TOKEN. Held in memory, never saved; reload clears it. Use HTTPS outside localhost.</p>
    </details>

    <section class="stats" aria-label="API-reported status">
      <div class="panel"><span>Server status</span><strong>{{ display(status?.server?.status) }}</strong><small>{{ display(status?.server?.address) }}<template v-if="status?.server?.port">:{{ status.server.port }}</template></small></div>
      <div class="panel"><span>Profiles</span><strong>{{ display(total) }}</strong><small>Active metadata: {{ display(status?.clients?.active) }} · not live connections</small></div>
      <div class="panel"><span>Reported traffic today</span><strong>{{ display(status?.traffic?.today) }}</strong><small>Total: {{ display(status?.traffic?.total) }}</small></div>
      <div class="panel"><span>Reported uptime</span><strong>{{ display(status?.server?.uptime) }}</strong><small>Unavailable metrics are not estimated.</small></div>
    </section>
    <p v-if="statusError" class="error" role="alert">Status unavailable: {{ statusError }}</p>
    <p v-if="notice" class="success" role="status">{{ notice }}</p>

    <section class="panel profiles" :aria-busy="loading">
      <div class="toolbar">
        <label>Search by name<input v-model="query" type="search" placeholder="Find a profile"></label>
        <label>Transport<select v-model="transport"><option value="">All transports</option><option v-for="item in transports" :key="item">{{ item }}</option></select></label>
        <button :disabled="loading || busy" @click="refresh">{{ loading ? 'Loading…' : 'Refresh' }}</button>
      </div>
      <p v-if="listError" class="error" role="alert">{{ listError }} <span v-if="loaded">Showing the last loaded list.</span> Use Refresh to retry.</p>
      <p v-if="loading" class="empty" role="status">Loading profiles…</p>
      <div v-if="filtered.length" class="table-scroll">
        <table>
          <thead><tr><th>Name</th><th>Transport / flow</th><th>Status metadata</th><th>Created</th><th>Expiry metadata</th><th>Actions</th></tr></thead>
          <tbody><tr v-for="client in filtered" :key="client.name">
            <td><strong>{{ client.name }}</strong><small class="identifier">{{ client.id }}</small></td>
            <td><span class="badge">{{ client.transport }}</span><small>{{ client.flow || 'none' }}</small></td>
            <td>{{ display(client.status) }}</td><td>{{ date(client.created) }}</td><td>{{ date(client.expiry) }}</td>
            <td><div class="row-actions">
              <button :disabled="loading || busy" @click="open('config', client)">Config / copy URI</button>
              <button :disabled="loading || busy" @click="open('clone', client)">Clone</button>
              <button :disabled="loading || busy" @click="open('edit', client)">Edit</button>
              <button class="danger" :disabled="loading || busy" @click="open('delete', client)">Delete</button>
            </div></td>
          </tr></tbody>
        </table>
      </div>
      <p v-else-if="!loading && !listError" class="empty">{{ clients.length ? 'No profiles match your filters.' : 'No profiles yet. Create your first connection profile.' }}</p>
    </section>

    <AppDialog v-if="modal" :title="modal === 'create' ? 'Create profile' : `${modal === 'config' ? 'Configuration' : modal === 'edit' ? 'Edit' : modal === 'clone' ? 'Clone' : 'Delete'} · ${selected.name}`" :busy="busy || detailLoading" @close="close">
      <p v-if="modalError" class="error" role="alert">{{ modalError }}</p>
      <ProfileForm v-if="['create', 'clone', 'edit'].includes(modal)" :mode="modal" :client="selected" :busy="busy" @submit="save" @cancel="close" />
      <template v-else-if="modal === 'config'">
        <p v-if="detailLoading" role="status">Loading configuration…</p>
        <template v-if="details">
          <p class="muted">Connection details contain credentials. Share only with trusted recipients.</p>
          <label>Connection URI<textarea readonly :value="details.connectionString || ''" rows="4" @focus="$event.target.select()" /></label>
          <button :disabled="!details.connectionString" @click="copyUri">Copy URI</button>
          <p v-if="notice" class="success" role="status">{{ notice }}</p>
          <h3>Configuration</h3><pre tabindex="0">{{ JSON.stringify(details.config ?? {}, null, 2) }}</pre>
        </template>
        <button v-else-if="!detailLoading" @click="loadDetails">Retry</button>
      </template>
      <template v-else>
        <p>Delete profile <strong>{{ selected.name }}</strong>? This removes its local configuration and cannot be undone. It does not revoke server access.</p>
        <footer class="actions"><button :disabled="busy" @click="close">Cancel</button><button class="danger" :disabled="busy" @click="save({})">{{ busy ? 'Deleting…' : 'Delete profile' }}</button></footer>
      </template>
    </AppDialog>
  </main>
</template>
