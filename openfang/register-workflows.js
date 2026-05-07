/**
 * OpenFang Workflow Registration Script
 * 
 * Run this to register all workflow JSON files with OpenFang.
 * Usage: node register-workflows.js [api-url]
 * Default API URL: http://localhost:4200
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

const API_URL = process.argv[2] || 'http://localhost:4200';
const WORKFLOWS_DIR = './workflows';

function makeRequest(url, method, data = null) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 4200,
      path: parsedUrl.pathname + parsedUrl.search,
      method: method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let responseData = '';
      res.on('data', (chunk) => {
        responseData += chunk;
      });
      res.on('end', () => {
        try {
          resolve(JSON.parse(responseData));
        } catch {
          resolve(responseData);
        }
      });
    });

    req.on('error', (err) => {
      reject(err);
    });

    if (data) {
      req.write(JSON.stringify(data));
    }
    req.end();
  });
}

async function registerWorkflow(filePath) {
  const filename = path.basename(filePath);
  const workflowData = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const name = workflowData.name;

  if (!name) {
    console.log(`[SKIP] ${filename}: No 'name' field found`);
    return false;
  }

  console.log(`[REGISTER] ${name} (${filename})...`);

  try {
    // Check if already exists
    const existing = await makeRequest(`${API_URL}/api/workflows`, 'GET');
    const existingWorkflow = existing.find(w => w.name === name);
    
    if (existingWorkflow) {
      console.log(`[EXISTS] Already registered (ID: ${existingWorkflow.id})`);
      console.log(`         To re-register, delete it first or use a different name`);
      return true;
    }

    // Register the workflow
    const response = await makeRequest(`${API_URL}/api/workflows`, 'POST', workflowData);
    
    if (response.id) {
      console.log(`[SUCCESS] Registered (ID: ${response.id})`);
      return true;
    } else {
      console.log(`[ERROR] Failed to register: ${JSON.stringify(response)}`);
      return false;
    }
  } catch (err) {
    console.log(`[ERROR] ${err.message}`);
    return false;
  }
}

async function main() {
  console.log('='.repeat(80));
  console.log('  OpenFang Workflow Registration Tool');
  console.log('='.repeat(80));
  console.log('');
  console.log(`API Endpoint: ${API_URL}`);
  console.log(`Workflows directory: ${WORKFLOWS_DIR}`);
  console.log('');

  // Check if OpenFang is accessible
  console.log('[CHECK] Testing connection to OpenFang...');
  try {
    await makeRequest(`${API_URL}/api/health`, 'GET');
    console.log('[CHECK] OpenFang is running and accessible');
  } catch (err) {
    console.log('[ERROR] Cannot connect to OpenFang');
    console.log('');
    console.log('Make sure OpenFang is running:');
    console.log('  docker compose -f openfang/docker-compose.yaml up -d openfang');
    console.log('');
    process.exit(1);
  }
  console.log('');

  // Get all workflow files
  const files = fs.readdirSync(WORKFLOWS_DIR)
    .filter(f => f.endsWith('.json'))
    .map(f => path.join(WORKFLOWS_DIR, f));

  console.log(`[SCAN] Found ${files.length} workflow files`);
  console.log('');
  console.log('='.repeat(80));
  console.log('  Registering Workflows...');
  console.log('='.repeat(80));
  console.log('');

  let successCount = 0;
  let errorCount = 0;

  for (const file of files.sort()) {
    const success = await registerWorkflow(file);
    if (success) {
      successCount++;
    } else {
      errorCount++;
    }
    console.log('');
  }

  // Summary
  console.log('='.repeat(80));
  console.log('  Registration Summary');
  console.log('='.repeat(80));
  console.log('');
  console.log(`Total workflows: ${files.length}`);
  console.log(`Successfully registered: ${successCount}`);
  console.log(`Errors: ${errorCount}`);
  console.log('');

  // List all workflows
  console.log('Currently registered workflows:');
  console.log('-'.repeat(80));
  try {
    const workflows = await makeRequest(`${API_URL}/api/workflows`, 'GET');
    for (const wf of workflows) {
      console.log(`  * ${wf.name} (ID: ${wf.id})`);
    }
  } catch {
    console.log('  (Could not retrieve workflow list)');
  }

  console.log('');
  console.log('='.repeat(80));
  console.log('');
  console.log('Next steps:');
  console.log('  1. Start the scheduler for automated execution:');
  console.log('     docker compose -f openfang/docker-compose.yaml up -d openfang-scheduler');
  console.log('');
  console.log('  2. Or manually trigger a workflow:');
  console.log(`     curl -X POST ${API_URL}/api/workflows/<workflow-id>/run`);
  console.log('       -H "Content-Type: application/json"');
  console.log('       -d \'{"input": "test"}\'');
  console.log('');
  console.log('='.repeat(80));
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
