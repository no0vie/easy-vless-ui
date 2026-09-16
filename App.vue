<!-- App.vue -->
<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Header -->
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex justify-between items-center">
        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2">
            <svg class="w-8 h-8 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
            </svg>
            <h1 class="text-xl font-semibold text-gray-900">BoRIS VLESS Manager</h1>
          </div>
          <div class="flex items-center space-x-2">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
              {{ serverStatus }}
            </span>
            <span class="text-sm text-gray-500">{{ serverAddress }}</span>
          </div>
        </div>
        <button
          @click="showCreateModal = true"
          class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <svg class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
          Add Client
        </button>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Stats -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Total Clients</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.total }}</p>
            </div>
            <div class="p-3 bg-blue-100 rounded-full">
              <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Active</p>
              <p class="text-2xl font-semibold text-green-600">{{ stats.active }}</p>
            </div>
            <div class="p-3 bg-green-100 rounded-full">
              <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Traffic Today</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.trafficToday }}</p>
            </div>
            <div class="p-3 bg-yellow-100 rounded-full">
              <svg class="w-6 h-6 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Uptime</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.uptime }}</p>
            </div>
            <div class="p-3 bg-purple-100 rounded-full">
              <svg class="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Clients Table -->
      <div class="bg-white rounded-lg shadow overflow-hidden">
        <div class="px-4 py-5 border-b border-gray-200 sm:px-6 flex justify-between items-center">
          <h3 class="text-lg leading-6 font-medium text-gray-900">Clients</h3>
          <div class="flex space-x-2">
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Search..."
              class="shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-48 sm:text-sm border-gray-300 rounded-md"
            >
            <select
              v-model="filterTransport"
              class="shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-32 sm:text-sm border-gray-300 rounded-md"
            >
              <option value="">All transports</option>
              <option value="raw">Raw</option>
              <option value="xhttp">XHTTP</option>
              <option value="grpc">gRPC</option>
              <option value="ws">WebSocket</option>
            </select>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Client</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Transport</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Expiry</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr v-for="client in filteredClients" :key="client.id">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div>
                      <div class="text-sm font-medium text-gray-900">{{ client.name }}</div>
                      <div class="text-xs text-gray-500">{{ client.id }}</div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span :class="getTransportColor(client.transport)" class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full">
                    {{ client.transport }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span :class="getStatusColor(client.status)" class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full">
                    {{ client.status }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {{ formatDate(client.created) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {{ formatDate(client.expiry) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <div class="flex space-x-2">
                    <button
                      @click="copyConfig(client)"
                      class="text-blue-600 hover:text-blue-900"
                      title="Copy config"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/>
                      </svg>
                    </button>
                    <button
                      @click="cloneClient(client)"
                      class="text-green-600 hover:text-green-900"
                      title="Clone client"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                      </svg>
                    </button>
                    <button
                      @click="changeTransport(client)"
                      class="text-yellow-600 hover:text-yellow-900"
                      title="Change transport"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
                      </svg>
                    </button>
                    <button
                      @click="deleteClient(client)"
                      class="text-red-600 hover:text-red-900"
                      title="Delete client"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                      </svg>
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </main>

    <!-- Create Client Modal -->
    <div v-if="showCreateModal" class="fixed inset-0 overflow-y-auto">
      <div class="flex items-center justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <div class="fixed inset-0 transition-opacity" @click="showCreateModal = false">
          <div class="absolute inset-0 bg-gray-500 opacity-75"></div>
        </div>

        <div class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Add New Client</h3>
            <button @click="showCreateModal = false" class="text-gray-400 hover:text-gray-500">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>

          <form @submit.prevent="createClient">
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700">Client Name</label>
                <input
                  v-model="newClient.name"
                  type="text"
                  required
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="e.g., boris-phone"
                >
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Transport</label>
                <select
                  v-model="newClient.transport"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="raw">Raw (TCP)</option>
                  <option value="xhttp">XHTTP</option>
                  <option value="grpc">gRPC</option>
                  <option value="ws">WebSocket</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Flow</label>
                <select
                  v-model="newClient.flow"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="xtls-rprx-vision">xtls-rprx-vision</option>
                  <option value="none">None</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Expiry (days)</label>
                <input
                  v-model.number="newClient.expiryDays"
                  type="number"
                  min="1"
                  max="365"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="30"
                >
              </div>
            </div>

            <div class="mt-5 sm:mt-6">
              <button
                type="submit"
                class="w-full inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                :disabled="loading"
              >
                <svg v-if="loading" class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                {{ loading ? 'Creating...' : 'Create Client' }}
              </button>
            </div>
          </form>

          <div v-if="newClient.connectionString" class="mt-4">
            <label class="block text-sm font-medium text-gray-700">Connection String</label>
            <div class="mt-1 flex rounded-md shadow-sm">
              <input
                :value="newClient.connectionString"
                readonly
                class="flex-1 block w-full rounded-none rounded-l-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              >
              <button
                @click="copyConnectionString"
                class="inline-flex items-center px-3 py-2 border border-l-0 border-gray-300 rounded-r-md bg-gray-50 text-gray-700 text-sm hover:bg-gray-100"
              >
                Copy
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted } from 'vue'
import axios from 'axios'

export default {
  setup() {
    const clients = ref([])
    const stats = ref({
      total: 0,
      active: 0,
      trafficToday: '0 GB',
      uptime: '0d'
    })
    const serverStatus = ref('Unknown')
    const serverAddress = ref('')
    const searchQuery = ref('')
    const filterTransport = ref('')
    const showCreateModal = ref(false)
    const loading = ref(false)
    const newClient = ref({
      name: '',
      transport: 'xhttp',
      flow: 'xtls-rprx-vision',
      expiryDays: 30,
      connectionString: ''
    })

    const fetchClients = async () => {
      try {
        const response = await axios.get('/api/clients')
        clients.value = response.data.clients
        stats.value = {
          total: response.data.total,
          active: response.data.clients.filter(c => c.status === 'active').length,
          trafficToday: '1.2 GB',
          uptime: response.data.serverInfo?.uptime || '0d'
        }
        serverStatus.value = response.data.serverInfo?.status || 'Unknown'
        serverAddress.value = response.data.serverInfo?.address || ''
      } catch (error) {
        console.error('Failed to fetch clients:', error)
      }
    }

    const filteredClients = computed(() => {
      return clients.value.filter(client => {
        const matchesSearch = client.name.toLowerCase().includes(searchQuery.value.toLowerCase())
        const matchesTransport = !filterTransport.value || client.transport === filterTransport.value
        return matchesSearch && matchesTransport
      })
    })

    const createClient = async () => {
      loading.value = true
      try {
        const response = await axios.post('/api/clients', newClient.value)
        newClient.value.connectionString = response.data.connectionString
        await fetchClients()
        setTimeout(() => {
          showCreateModal.value = false
          newClient.value = {
            name: '',
            transport: 'xhttp',
            flow: 'xtls-rprx-vision',
            expiryDays: 30,
            connectionString: ''
          }
        }, 3000)
      } catch (error) {
        console.error('Failed to create client:', error)
      } finally {
        loading.value = false
      }
    }

    const copyConfig = (client) => {
      // Copy VLESS config to clipboard
      navigator.clipboard.writeText(JSON.stringify(client.config, null, 2))
    }

    const cloneClient = async (client) => {
      try {
        await axios.post(`/api/clients/${client.id}/clone`, {
          newName: `${client.name}-copy`
        })
        await fetchClients()
      } catch (error) {
        console.error('Failed to clone client:', error)
      }
    }

    const changeTransport = (client) => {
      // Show transport selection modal
      const transports = ['raw', 'xhttp', 'grpc', 'ws']
      const currentIndex = transports.indexOf(client.transport)
      const nextTransport = transports[(currentIndex + 1) % transports.length]

      if (confirm(`Change transport from ${client.transport} to ${nextTransport}?`)) {
        // API call to update transport
      }
    }

    const deleteClient = async (client) => {
      if (confirm(`Delete client "${client.name}"?`)) {
        try {
          await axios.delete(`/api/clients/${client.id}`)
          await fetchClients()
        } catch (error) {
          console.error('Failed to delete client:', error)
        }
      }
    }

    const copyConnectionString = () => {
      navigator.clipboard.writeText(newClient.value.connectionString)
    }

    const formatDate = (dateString) => {
      if (!dateString) return '-'
      const date = new Date(dateString)
      return date.toLocaleDateString()
    }

    const getStatusColor = (status) => {
      const colors = {
        active: 'bg-green-100 text-green-800',
        inactive: 'bg-gray-100 text-gray-800',
        expired: 'bg-red-100 text-red-800'
      }
      return colors[status] || 'bg-gray-100 text-gray-800'
    }

    const getTransportColor = (transport) => {
      const colors = {
        raw: 'bg-blue-100 text-blue-800',
        xhttp: 'bg-purple-100 text-purple-800',
        grpc: 'bg-green-100 text-green-800',
        ws: 'bg-yellow-100 text-yellow-800'
      }
      return colors[transport] || 'bg-gray-100 text-gray-800'
    }

    onMounted(() => {
      fetchClients()
    })

    return {
      clients,
      stats,
      serverStatus,
      serverAddress,
      searchQuery,
      filterTransport,
      filteredClients,
      showCreateModal,
      loading,
      newClient,
      createClient,
      copyConfig,
      cloneClient,
      changeTransport,
      deleteClient,
      copyConnectionString,
      formatDate,
      getStatusColor,
      getTransportColor
    }
  }
}
</script>
<!-- App.vue -->
<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Header -->
    <header class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex justify-between items-center">
        <div class="flex items-center space-x-4">
          <div class="flex items-center space-x-2">
            <svg class="w-8 h-8 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
            </svg>
            <h1 class="text-xl font-semibold text-gray-900">BoRIS VLESS Manager</h1>
          </div>
          <div class="flex items-center space-x-2">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
              {{ serverStatus }}
            </span>
            <span class="text-sm text-gray-500">{{ serverAddress }}</span>
          </div>
        </div>
        <button 
          @click="showCreateModal = true"
          class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <svg class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
          </svg>
          Add Client
        </button>
      </div>
    </header>

    <!-- Main Content -->
    <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Stats -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Total Clients</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.total }}</p>
            </div>
            <div class="p-3 bg-blue-100 rounded-full">
              <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Active</p>
              <p class="text-2xl font-semibold text-green-600">{{ stats.active }}</p>
            </div>
            <div class="p-3 bg-green-100 rounded-full">
              <svg class="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Traffic Today</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.trafficToday }}</p>
            </div>
            <div class="p-3 bg-yellow-100 rounded-full">
              <svg class="w-6 h-6 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"/>
              </svg>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <div class="flex items-center">
            <div class="flex-1">
              <p class="text-sm font-medium text-gray-600">Uptime</p>
              <p class="text-2xl font-semibold text-gray-900">{{ stats.uptime }}</p>
            </div>
            <div class="p-3 bg-purple-100 rounded-full">
              <svg class="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </div>
          </div>
        </div>
      </div>

      <!-- Clients Table -->
      <div class="bg-white rounded-lg shadow overflow-hidden">
        <div class="px-4 py-5 border-b border-gray-200 sm:px-6 flex justify-between items-center">
          <h3 class="text-lg leading-6 font-medium text-gray-900">Clients</h3>
          <div class="flex space-x-2">
            <input 
              v-model="searchQuery"
              type="text" 
              placeholder="Search..." 
              class="shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-48 sm:text-sm border-gray-300 rounded-md"
            >
            <select 
              v-model="filterTransport"
              class="shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-32 sm:text-sm border-gray-300 rounded-md"
            >
              <option value="">All transports</option>
              <option value="raw">Raw</option>
              <option value="xhttp">XHTTP</option>
              <option value="grpc">gRPC</option>
              <option value="ws">WebSocket</option>
            </select>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Client</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Transport</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Expiry</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr v-for="client in filteredClients" :key="client.id">
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex items-center">
                    <div>
                      <div class="text-sm font-medium text-gray-900">{{ client.name }}</div>
                      <div class="text-xs text-gray-500">{{ client.id }}</div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span :class="getTransportColor(client.transport)" class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full">
                    {{ client.transport }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span :class="getStatusColor(client.status)" class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full">
                    {{ client.status }}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {{ formatDate(client.created) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {{ formatDate(client.expiry) }}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  <div class="flex space-x-2">
                    <button 
                      @click="copyConfig(client)"
                      class="text-blue-600 hover:text-blue-900"
                      title="Copy config"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/>
                      </svg>
                    </button>
                    <button 
                      @click="cloneClient(client)"
                      class="text-green-600 hover:text-green-900"
                      title="Clone client"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                      </svg>
                    </button>
                    <button 
                      @click="changeTransport(client)"
                      class="text-yellow-600 hover:text-yellow-900"
                      title="Change transport"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
                      </svg>
                    </button>
                    <button 
                      @click="deleteClient(client)"
                      class="text-red-600 hover:text-red-900"
                      title="Delete client"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                      </svg>
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </main>

    <!-- Create Client Modal -->
    <div v-if="showCreateModal" class="fixed inset-0 overflow-y-auto">
      <div class="flex items-center justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <div class="fixed inset-0 transition-opacity" @click="showCreateModal = false">
          <div class="absolute inset-0 bg-gray-500 opacity-75"></div>
        </div>

        <div class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Add New Client</h3>
            <button @click="showCreateModal = false" class="text-gray-400 hover:text-gray-500">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>

          <form @submit.prevent="createClient">
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700">Client Name</label>
                <input 
                  v-model="newClient.name"
                  type="text" 
                  required
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="e.g., boris-phone"
                >
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Transport</label>
                <select 
                  v-model="newClient.transport"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="raw">Raw (TCP)</option>
                  <option value="xhttp">XHTTP</option>
                  <option value="grpc">gRPC</option>
                  <option value="ws">WebSocket</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Flow</label>
                <select 
                  v-model="newClient.flow"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="xtls-rprx-vision">xtls-rprx-vision</option>
                  <option value="none">None</option>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700">Expiry (days)</label>
                <input 
                  v-model.number="newClient.expiryDays"
                  type="number" 
                  min="1"
                  max="365"
                  class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="30"
                >
              </div>
            </div>

            <div class="mt-5 sm:mt-6">
              <button 
                type="submit"
                class="w-full inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                :disabled="loading"
              >
                <svg v-if="loading" class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                {{ loading ? 'Creating...' : 'Create Client' }}
              </button>
            </div>
          </form>

          <div v-if="newClient.connectionString" class="mt-4">
            <label class="block text-sm font-medium text-gray-700">Connection String</label>
            <div class="mt-1 flex rounded-md shadow-sm">
              <input 
                :value="newClient.connectionString" 
                readonly
                class="flex-1 block w-full rounded-none rounded-l-md border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              >
              <button 
                @click="copyConnectionString"
                class="inline-flex items-center px-3 py-2 border border-l-0 border-gray-300 rounded-r-md bg-gray-50 text-gray-700 text-sm hover:bg-gray-100"
              >
                Copy
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted } from 'vue'
import axios from 'axios'

export default {
  setup() {
    const clients = ref([])
    const stats = ref({
      total: 0,
      active: 0,
      trafficToday: '0 GB',
      uptime: '0d'
    })
    const serverStatus = ref('Unknown')
    const serverAddress = ref('')
    const searchQuery = ref('')
    const filterTransport = ref('')
    const showCreateModal = ref(false)
    const loading = ref(false)
    const newClient = ref({
      name: '',
      transport: 'xhttp',
      flow: 'xtls-rprx-vision',
      expiryDays: 30,
      connectionString: ''
    })

    const fetchClients = async () => {
      try {
        const response = await axios.get('/api/clients')
        clients.value = response.data.clients
        stats.value = {
          total: response.data.total,
          active: response.data.clients.filter(c => c.status === 'active').length,
          trafficToday: '1.2 GB',
          uptime: response.data.serverInfo?.uptime || '0d'
        }
        serverStatus.value = response.data.serverInfo?.status || 'Unknown'
        serverAddress.value = response.data.serverInfo?.address || ''
      } catch (error) {
        console.error('Failed to fetch clients:', error)
      }
    }

    const filteredClients = computed(() => {
      return clients.value.filter(client => {
        const matchesSearch = client.name.toLowerCase().includes(searchQuery.value.toLowerCase())
        const matchesTransport = !filterTransport.value || client.transport === filterTransport.value
        return matchesSearch && matchesTransport
      })
    })

    const createClient = async () => {
      loading.value = true
      try {
        const response = await axios.post('/api/clients', newClient.value)
        newClient.value.connectionString = response.data.connectionString
        await fetchClients()
        setTimeout(() => {
          showCreateModal.value = false
          newClient.value = {
            name: '',
            transport: 'xhttp',
            flow: 'xtls-rprx-vision',
            expiryDays: 30,
            connectionString: ''
          }
        }, 3000)
      } catch (error) {
        console.error('Failed to create client:', error)
      } finally {
        loading.value = false
      }
    }

    const copyConfig = (client) => {
      // Copy VLESS config to clipboard
      navigator.clipboard.writeText(JSON.stringify(client.config, null, 2))
    }

    const cloneClient = async (client) => {
      try {
        await axios.post(`/api/clients/${client.id}/clone`, {
          newName: `${client.name}-copy`
        })
        await fetchClients()
      } catch (error) {
        console.error('Failed to clone client:', error)
      }
    }

    const changeTransport = (client) => {
      // Show transport selection modal
      const transports = ['raw', 'xhttp', 'grpc', 'ws']
      const currentIndex = transports.indexOf(client.transport)
      const nextTransport = transports[(currentIndex + 1) % transports.length]
      
      if (confirm(`Change transport from ${client.transport} to ${nextTransport}?`)) {
        // API call to update transport
      }
    }

    const deleteClient = async (client) => {
      if (confirm(`Delete client "${client.name}"?`)) {
        try {
          await axios.delete(`/api/clients/${client.id}`)
          await fetchClients()
        } catch (error) {
          console.error('Failed to delete client:', error)
        }
      }
    }

    const copyConnectionString = () => {
      navigator.clipboard.writeText(newClient.value.connectionString)
    }

    const formatDate = (dateString) => {
      if (!dateString) return '-'
      const date = new Date(dateString)
      return date.toLocaleDateString()
    }

    const getStatusColor = (status) => {
      const colors = {
        active: 'bg-green-100 text-green-800',
        inactive: 'bg-gray-100 text-gray-800',
        expired: 'bg-red-100 text-red-800'
      }
      return colors[status] || 'bg-gray-100 text-gray-800'
    }

    const getTransportColor = (transport) => {
      const colors = {
        raw: 'bg-blue-100 text-blue-800',
        xhttp: 'bg-purple-100 text-purple-800',
        grpc: 'bg-green-100 text-green-800',
        ws: 'bg-yellow-100 text-yellow-800'
      }
      return colors[transport] || 'bg-gray-100 text-gray-800'
    }

    onMounted(() => {
      fetchClients()
    })

    return {
      clients,
      stats,
      serverStatus,
      serverAddress,
      searchQuery,
      filterTransport,
      filteredClients,
      showCreateModal,
      loading,
      newClient,
      createClient,
      copyConfig,
      cloneClient,
      changeTransport,
      deleteClient,
      copyConnectionString,
      formatDate,
      getStatusColor,
      getTransportColor
    }
  }
}
</script>