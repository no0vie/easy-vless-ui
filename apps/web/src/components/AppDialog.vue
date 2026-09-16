<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue'
defineProps({ title: String, busy: Boolean })
const emit = defineEmits(['close'])
const dialog = ref(null)
let previousFocus
onMounted(() => { previousFocus = document.activeElement; dialog.value.showModal() })
onBeforeUnmount(() => { previousFocus?.focus() })
</script>

<template>
  <dialog ref="dialog" aria-labelledby="dialog-title" @cancel.prevent="!busy && emit('close')">
    <header class="dialog-header">
      <h2 id="dialog-title">{{ title }}</h2>
      <button type="button" :disabled="busy" aria-label="Close dialog" @click="emit('close')">Close</button>
    </header>
    <slot />
  </dialog>
</template>
