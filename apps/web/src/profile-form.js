export function initialProfileForm(client) {
  return {
    name: '',
    transport: client?.transport || 'raw',
    flow: client?.transport === 'xhttp' ? 'none' : client?.flow || 'none',
    // A stored expiry date is not a new duration; omit it unless explicitly edited.
    expiryDays: '',
  }
}

export function profileFormBody(mode, form) {
  if (mode === 'clone') return { newName: form.name }
  const body = { transport: form.transport, flow: form.transport === 'raw' ? form.flow || 'none' : 'none' }
  if (mode === 'create') body.name = form.name
  if (form.expiryDays !== '') body.expiryDays = Number(form.expiryDays)
  return body
}
