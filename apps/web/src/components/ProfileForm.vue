<script setup>
import { reactive, watch } from 'vue'
import { transports } from '../api.js'
import { initialProfileForm, profileFormBody } from '../profile-form.js'
const props = defineProps({ mode: String, client: Object, busy: Boolean })
const emit = defineEmits(['submit', 'cancel'])
const form = reactive(initialProfileForm(props.client))
watch(() => form.transport, value => { if (value !== 'raw') form.flow = 'none' })
function submit() {
  emit('submit', profileFormBody(props.mode, form))
}
</script>

<template>
  <form @submit.prevent="submit">
    <fieldset :disabled="busy">
      <label v-if="mode !== 'edit'">{{ mode === 'clone' ? 'New profile name' : 'Profile name' }}
        <input v-model="form.name" required maxlength="64" pattern="[A-Za-z0-9][A-Za-z0-9_\-]{0,63}" autofocus autocomplete="off" aria-describedby="name-help">
      </label>
      <p v-if="mode !== 'edit'" id="name-help" class="muted">1–64 characters: letters, numbers, underscores or hyphens. Start with a letter or number.</p>
      <template v-if="mode !== 'clone'">
        <label>Transport<select v-model="form.transport"><option v-for="transport in transports" :key="transport">{{ transport }}</option></select></label>
        <label>Flow<select v-model="form.flow" :disabled="form.transport !== 'raw'"><option value="none">None</option><option value="xtls-rprx-vision">xtls-rprx-vision</option></select></label>
        <label>Expiry in days (optional)<input v-model="form.expiryDays" type="number" min="0" step="1" :placeholder="mode === 'edit' ? 'Leave unchanged' : 'No expiry'"></label>
        <p class="muted">Expiry is metadata only and does not enforce access restrictions. Enter 0 for no expiry{{ mode === 'edit' ? ' (clears existing expiry); leave blank to keep the current expiry' : '; leave blank for no expiry' }}.</p>
                <p class="muted">Only raw and xhttp REALITY are supported. XHTTP always uses no flow; raw allows None or xtls-rprx-vision.</p>
      </template>
    </fieldset>
    <footer class="actions"><button type="button" :disabled="busy" @click="emit('cancel')">Cancel</button><button class="primary" :disabled="busy">{{ busy ? 'Saving…' : mode === 'edit' ? 'Save changes' : mode === 'clone' ? 'Clone profile' : 'Create profile' }}</button></footer>
  </form>
</template>
