import * as core from '@actions/core';
import * as exec from '@actions/exec';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { version: VERSION } = require('../package.json');
const ACTION_NAME = 'build-domain (cleanup)';

interface ExecOutput {
  stdout: string;
  stderr: string;
  exitCode: number;
}

function printHeader(resource: string, serverUrl: string): void {
  const line = '-'.repeat(90);
  console.log(line);
  console.log(`flxbl-actions  -- ❤️  by flxbl.io ❤️  -Version:${VERSION}`);
  console.log(line);
  console.log(`Action     : ${ACTION_NAME}`);
  console.log(`Resource   : ${resource}`);
  console.log(`SFP Server : ${serverUrl}`);
  console.log(line);
  console.log();
}

async function execCommand(
  command: string,
  args: string[],
  silent = false
): Promise<ExecOutput> {
  let stdout = '';
  let stderr = '';

  const exitCode = await exec.exec(command, args, {
    silent,
    listeners: {
      stdout: (data: Buffer) => {
        stdout += data.toString();
      },
      stderr: (data: Buffer) => {
        stderr += data.toString();
      }
    },
    ignoreReturnCode: true
  });

  return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode };
}

async function dequeueResource(
  resource: string,
  repository: string,
  ticketId: string,
  serverUrl: string,
  serverToken: string
): Promise<void> {
  const args = [
    'server', 'resource', 'dequeue',
    '--repository', repository,
    '--resource', resource,
    '--ticketid', ticketId,
    '--sfp-server-url', serverUrl,
    '--application-token', serverToken
  ];

  core.info(`Releasing build lock for resource: ${resource}`);
  core.info(`Ticket ID: ${ticketId}`);

  const result = await execCommand('sfp', args, true);

  if (result.exitCode !== 0) {
    if (result.stderr) {
      core.debug(`sfp stderr: ${result.stderr}`);
    }
    throw new Error(`Failed to release lock: ${result.stderr || result.stdout}`);
  }

  core.info('Build lock released successfully');
}

async function run(): Promise<void> {
  try {
    // Retrieve state from main step
    const serialize = core.getState('SERIALIZE');
    const ticketId = core.getState('TICKET_ID');
    const resource = core.getState('RESOURCE');
    const repository = core.getState('REPOSITORY');
    const serverUrl = core.getState('SFP_SERVER_URL');
    const serverToken = core.getState('SFP_SERVER_TOKEN');

    // Check if serialization was enabled
    if (serialize !== 'true') {
      core.info('Serialization was not enabled, skipping cleanup');
      return;
    }

    // Check if we have the required state
    if (!ticketId) {
      core.info('No ticket ID found in state, skipping cleanup');
      return;
    }

    if (!resource || !repository || !serverUrl || !serverToken) {
      core.warning('Missing required state for dequeue. The lock may need to be manually released.');
      core.debug(`ticketId: ${ticketId ? 'present' : 'missing'}`);
      core.debug(`resource: ${resource ? 'present' : 'missing'}`);
      core.debug(`repository: ${repository ? 'present' : 'missing'}`);
      core.debug(`serverUrl: ${serverUrl ? 'present' : 'missing'}`);
      core.debug(`serverToken: ${serverToken ? 'present' : 'missing'}`);
      return;
    }

    // Mark token as secret to prevent exposure in logs
    core.setSecret(serverToken);

    printHeader(resource, serverUrl);

    await dequeueResource(resource, repository, ticketId, serverUrl, serverToken);

    core.info('');
    core.info('Cleanup completed successfully.');

  } catch (error) {
    if (error instanceof Error) {
      core.warning(`Cleanup failed: ${error.message}`);
      core.warning('The lock may need to be manually released or will expire after lease duration.');
    } else {
      core.warning('Cleanup failed with unknown error');
    }
    // Never call setFailed in cleanup - we don't want to fail the job due to cleanup issues
  }
}

run();
