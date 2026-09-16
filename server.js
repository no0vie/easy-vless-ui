// server.js
const express = require('express');
const cors = require('cors');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const { promisify } = require('util');

const execAsync = promisify(exec);
const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

const SCRIPT_PATH = '/opt/boris/vless-client/vless-manager.sh';
const PROFILES_DIR = '/opt/boris/vless-client/profiles';

// Helper: Execute script with arguments
const executeScript = async (args) => {
  try {
    const { stdout, stderr } = await execAsync(`${SCRIPT_PATH} ${args} --format json`);
    if (stderr) console.error('Script stderr:', stderr);
    return JSON.parse(stdout);
  } catch (error) {
    console.error('Script execution error:', error);
    throw new Error(error.message);
  }
};

// API: Get all clients
app.get('/api/clients', async (req, res) => {
  try {
    const result = await executeScript('--list-clients');
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Create client
app.post('/api/clients', async (req, res) => {
  const { name, transport, flow, expiryDays } = req.body;
  try {
    const result = await executeScript(
      `--create-client --name "${name}" --transport "${transport}" --flow "${flow}" --expiry ${expiryDays}`
    );
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Get client details
app.get('/api/clients/:id', async (req, res) => {
  try {
    const result = await executeScript(`--get-client --id "${req.params.id}"`);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Update client transport
app.put('/api/clients/:id', async (req, res) => {
  const { transport } = req.body;
  try {
    const result = await executeScript(
      `--update-client --id "${req.params.id}" --transport "${transport}"`
    );
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Clone client
app.post('/api/clients/:id/clone', async (req, res) => {
  const { newName } = req.body;
  try {
    const result = await executeScript(
      `--copy-client --id "${req.params.id}" --new-name "${newName}"`
    );
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Delete client
app.delete('/api/clients/:id', async (req, res) => {
  try {
    await executeScript(`--delete-client --id "${req.params.id}"`);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// API: Server status
app.get('/api/status', async (req, res) => {
  try {
    const result = await executeScript('--status');
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`VLESS Manager API running on http://localhost:${PORT}`);
});
