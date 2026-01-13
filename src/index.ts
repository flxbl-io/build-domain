import * as core from '@actions/core';
import * as exec from '@actions/exec';
import * as fs from 'fs';
import * as yaml from 'yaml';
import * as path from 'path';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { version: VERSION } = require('../package.json');
const ACTION_NAME = 'build-domain';

interface ReleaseConfig {
  releaseName: string;
  [key: string]: unknown;
}

interface ExecOutput {
  stdout: string;
  stderr: string;
  exitCode: number;
}

function printHeader(
  repository: string,
  branch: string,
  buildNumber: string,
  releaseConfig: string,
  diffCheck: string,
  serverUrl: string,
  serialize: boolean,
  releaseName: string
): void {
  const line = '-'.repeat(90);
  console.log(line);
  console.log(`flxbl-actions  -- ❤️  by flxbl.io ❤️  -Version:${VERSION}`);
  console.log(line);
  console.log(`Action        : ${ACTION_NAME}`);
  console.log(`Repository    : ${repository}`);
  console.log(`Branch        : ${branch}`);
  console.log(`Build Number  : ${buildNumber}`);
  console.log(`Release Config: ${releaseConfig}`);
  console.log(`Release Name  : ${releaseName}`);
  console.log(`Diff Check    : ${diffCheck}`);
  console.log(`Serialize     : ${serialize}`);
  console.log(`SFP Server    : ${serverUrl}`);
  console.log(line);
  console.log();
}

// Execute command with output captured (for commands needing output parsing)
async function execCommandWithOutput(
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

// Execute command with streaming output (for heavy log commands like build)
async function execCommandStreaming(
  command: string,
  args: string[]
): Promise<number> {
  const exitCode = await exec.exec(command, args, {
    listeners: {
      stdout: (data: Buffer) => {
        process.stdout.write(data);
      },
      stderr: (data: Buffer) => {
        process.stderr.write(data);
      }
    },
    ignoreReturnCode: true
  });

  return exitCode;
}

function readReleaseConfig(configPath: string): ReleaseConfig {
  const fullPath = path.resolve(configPath);

  if (!fs.existsSync(fullPath)) {
    throw new Error(`Release config file not found: ${fullPath}`);
  }

  const content = fs.readFileSync(fullPath, 'utf8');
  const config = yaml.parse(content) as ReleaseConfig;

  if (!config.releaseName) {
    throw new Error(`releaseName not found in release config: ${configPath}`);
  }

  return config;
}

async function enqueueResource(
  resource: string,
  repository: string,
  leaseDuration: number,
  serverUrl: string,
  serverToken: string
): Promise<string> {
  const args = [
    'server', 'resource', 'enqueue',
    '--repository', repository,
    '--resource', resource,
    '--leasefor', leaseDuration.toString(),
    '--sfp-server-url', serverUrl,
    '--application-token', serverToken
  ];

  core.info(`Serializing build for resource: ${resource}`);
  core.info(`Lease duration: ${leaseDuration} seconds`);

  const result = await execCommandWithOutput('sfp', args, true);

  if (result.exitCode !== 0) {
    throw new Error(`Failed to enqueue: ${result.stderr || result.stdout}`);
  }

  // Extract ticket ID from output
  const ticketIdMatch = result.stdout.match(/ticket\s*(?:ID|id)?[:\s]+(\d+-\d+-[a-f0-9-]+)/i);

  if (!ticketIdMatch) {
    const lines = result.stdout.trim().split('\n');
    const lastLine = lines[lines.length - 1].trim().replace(/^"|"$/g, '');
    if (lastLine.match(/^\d+-\d+-[a-f0-9-]+$/)) {
      core.info(`Enqueued with ticket ID: ${lastLine}`);
      return lastLine;
    }
    throw new Error(`No ticket ID found in output: ${result.stdout}`);
  }

  const ticketId = ticketIdMatch[1];
  core.info(`Enqueued with ticket ID: ${ticketId}`);
  return ticketId;
}

async function waitForLock(
  resource: string,
  repository: string,
  ticketId: string,
  timeout: number,
  serverUrl: string,
  serverToken: string
): Promise<boolean> {
  const args = [
    'server', 'resource', 'wait',
    '--repository', repository,
    '--resource', resource,
    '--ticketid', ticketId,
    '--wait', timeout.toString(),
    '--sfp-server-url', serverUrl,
    '--application-token', serverToken
  ];

  core.info(`Waiting for build lock acquisition...`);
  core.info(`Timeout: ${timeout} seconds`);

  const result = await execCommandWithOutput('sfp', args, false);

  // Check for timeout message regardless of exit code (CLI may return 0 on timeout)
  if (result.stderr?.includes('Timeout') || result.stdout?.includes('Timeout')) {
    core.warning(`Timeout waiting for lock on resource: ${resource}`);
    return false;
  }

  if (result.exitCode !== 0) {
    throw new Error(`Failed to acquire lock: ${result.stderr || result.stdout}`);
  }

  core.info(`Build lock acquired for resource: ${resource}`);
  return true;
}

async function checkGitDepth(diffCheck: boolean): Promise<void> {
  const result = await execCommandWithOutput('git', ['rev-parse', '--is-shallow-repository'], true);

  if (result.stdout === 'true') {
    core.warning('Shallow clone detected. For diff-check to work correctly, use \'fetch-depth: 0\' in your checkout step.');

    if (diffCheck) {
      core.info('Fetching full history for diff-check...');
      await exec.exec('git', ['fetch', '--unshallow', '--tags'], { ignoreReturnCode: true });
    }
  }

  // Fetch all tags
  core.info('Fetching tags...');
  await exec.exec('git', ['fetch', '--tags'], { ignoreReturnCode: true });
}

async function authenticateDevHub(serverUrl: string, serverToken: string): Promise<void> {
  core.info('Authenticating to default DevHub via SFP Server...');

  const args = [
    'org', 'login',
    '--server',
    '--default-devhub',
    '--alias', 'devhub',
    '--sfp-server-url', serverUrl,
    '-t', serverToken
  ];

  const exitCode = await execCommandStreaming('sfp', args);

  if (exitCode !== 0) {
    throw new Error('Failed to authenticate to DevHub');
  }

  core.info('DevHub authentication successful');
}

async function buildPackages(
  branch: string,
  buildNumber: string,
  releaseConfig: string,
  diffCheck: boolean,
  serverUrl: string,
  serverToken: string,
  repository: string
): Promise<void> {
  core.info('Building packages...');

  const args = [
    'build',
    '-v', 'devhub',
    '--branch', branch,
    '--buildnumber', buildNumber,
    '--artifactdir', 'artifacts',
    '--sfp-server-url', serverUrl,
    '-t', serverToken,
    '--repository', repository,
    '--releaseconfig', releaseConfig
  ];

  if (diffCheck) {
    args.push('--diffcheck');
  }

  const exitCode = await execCommandStreaming('sfp', args);

  if (exitCode !== 0) {
    throw new Error('Build failed');
  }

  core.info('Build completed');
}

async function checkArtifacts(): Promise<{ hasArtifacts: boolean; artifactCount: number }> {
  // Ensure artifacts directory exists
  if (!fs.existsSync('artifacts')) {
    fs.mkdirSync('artifacts', { recursive: true });
  }

  const files = fs.readdirSync('artifacts');
  const zipFiles = files.filter(f => f.endsWith('.zip'));
  const artifactCount = zipFiles.length;

  if (artifactCount === 0) {
    core.warning('No artifacts were produced by the build');
    return { hasArtifacts: false, artifactCount: 0 };
  }

  core.info(`Found ${artifactCount} artifact(s)`);
  return { hasArtifacts: true, artifactCount };
}

async function publishArtifacts(
  repository: string,
  serverUrl: string,
  serverToken: string,
  npmScope: string,
  npm: boolean,
  gitTag: boolean,
  pushGitTag: boolean
): Promise<void> {
  core.info('Publishing artifacts...');

  const args = [
    'publish',
    '-d', 'artifacts',
    '--repository', repository,
    '--sfp-server-url', serverUrl,
    '-t', serverToken
  ];

  if (npmScope) {
    args.push('--scope', npmScope);
  }

  if (npm) {
    args.push('--npm');
  } else {
    args.push('--internal-only');
  }

  if (gitTag) {
    args.push('--gittag');
  }

  if (pushGitTag) {
    args.push('--pushgittag');
  }

  const exitCode = await execCommandStreaming('sfp', args);

  if (exitCode !== 0) {
    throw new Error('Publish failed');
  }

  core.info('Publish completed');
}

async function fetchTagsAfterPublish(): Promise<void> {
  core.info('Fetching newly created tags...');
  await exec.exec('git', ['fetch', '--tags'], { ignoreReturnCode: true });
  core.info('Tags sync completed');
}

async function generateReleaseCandidate(
  releaseName: string,
  branch: string,
  buildNumber: string,
  releaseConfig: string,
  npmScope: string,
  repository: string,
  serverUrl: string,
  serverToken: string
): Promise<void> {
  core.info('Generating release candidate...');

  // Use provided release name or generate default
  const rcName = releaseName || `${branch}-${buildNumber}`;

  const args = [
    'releasecandidate', 'generate',
    '-n', rcName,
    '-c', 'HEAD',
    '-b', branch,
    '-f', releaseConfig,
    '--repository', repository,
    '--sfp-server-url', serverUrl,
    '-t', serverToken
  ];

  if (npmScope) {
    args.push('--scope', `@${npmScope}`);
  }

  const exitCode = await execCommandStreaming('sfp', args);

  if (exitCode !== 0) {
    throw new Error('Release candidate generation failed');
  }

  core.info(`Release candidate '${rcName}' generated successfully`);
}

function printSummary(hasArtifacts: boolean, artifactCount: number): void {
  const line = '-'.repeat(90);
  console.log();
  console.log(line);
  console.log('Build Summary');
  console.log(line);

  if (hasArtifacts) {
    console.log(`Artifacts        : ${artifactCount} package(s) built`);
    console.log('Published        : Yes');
    console.log('Release Candidate: Generated');
  } else {
    console.log('Artifacts        : None (no changes detected)');
    console.log('Published        : Skipped');
    console.log('Release Candidate: Skipped');
  }

  console.log(line);
}

export async function run(): Promise<void> {
  try {
    // Get inputs
    const serverUrl = core.getInput('sfp-server-url', { required: true });
    const serverToken = core.getInput('sfp-server-token', { required: true });
    const releaseConfigPath = core.getInput('release-config', { required: true });
    const repository = core.getInput('repository', { required: false }) || process.env.GITHUB_REPOSITORY || '';
    const branch = core.getInput('branch', { required: false }) || process.env.GITHUB_REF_NAME || 'main';
    const buildNumber = core.getInput('build-number', { required: false }) || process.env.GITHUB_RUN_ID || '1';
    const inputReleaseName = core.getInput('release-name', { required: false }) || '';
    const diffCheck = core.getInput('diff-check') !== 'false';
    const npmScope = core.getInput('npm-scope', { required: false }) || process.env.GITHUB_REPOSITORY_OWNER || '';
    const npm = core.getInput('npm') === 'true';
    const gitTag = core.getInput('git-tag') !== 'false';
    const pushGitTag = core.getInput('push-git-tag') !== 'false';

    // Serialization inputs
    const serialize = core.getInput('serialize') !== 'false';
    const serializeTimeout = parseInt(core.getInput('serialize-timeout') || '900', 10);
    const serializeLease = parseInt(core.getInput('serialize-lease') || '1800', 10);

    // Mark token as secret
    core.setSecret(serverToken);

    // Validate inputs
    if (!repository) {
      throw new Error('Repository not specified and GITHUB_REPOSITORY not set');
    }

    // Read release config to get releaseName
    const releaseConfig = readReleaseConfig(releaseConfigPath);
    const releaseName = releaseConfig.releaseName;

    // Print header
    printHeader(repository, branch, buildNumber, releaseConfigPath, diffCheck.toString(), serverUrl, serialize, releaseName);

    // Step 1: Serialize (if enabled)
    let ticketId = '';
    if (serialize) {
      const resource = `build-${releaseName}`;
      ticketId = await enqueueResource(resource, repository, serializeLease, serverUrl, serverToken);

      const acquired = await waitForLock(resource, repository, ticketId, serializeTimeout, serverUrl, serverToken);

      if (!acquired) {
        core.setFailed(`Failed to acquire build lock for resource: ${resource} within timeout`);
        return;
      }

      // Save state for cleanup
      core.saveState('TICKET_ID', ticketId);
      core.saveState('RESOURCE', resource);
      core.saveState('REPOSITORY', repository);
      core.saveState('SFP_SERVER_URL', serverUrl);
      core.saveState('SFP_SERVER_TOKEN', serverToken);
      core.saveState('SERIALIZE', 'true');
    }

    // Step 2: Check git depth and fetch tags
    await checkGitDepth(diffCheck);

    // Step 3: Authenticate to DevHub
    await authenticateDevHub(serverUrl, serverToken);

    // Step 4: Build packages
    await buildPackages(branch, buildNumber, releaseConfigPath, diffCheck, serverUrl, serverToken, repository);

    // Step 5: Check for artifacts
    const { hasArtifacts, artifactCount } = await checkArtifacts();

    // Set outputs
    core.setOutput('has-artifacts', hasArtifacts.toString());
    core.setOutput('artifact-count', artifactCount.toString());
    core.setOutput('artifacts-dir', 'artifacts');

    if (hasArtifacts) {
      // Step 6: Publish artifacts
      await publishArtifacts(repository, serverUrl, serverToken, npmScope, npm, gitTag, pushGitTag);

      // Step 7: Fetch tags after publish
      await fetchTagsAfterPublish();

      // Step 8: Generate release candidate
      await generateReleaseCandidate(
        inputReleaseName,
        branch,
        buildNumber,
        releaseConfigPath,
        npmScope,
        repository,
        serverUrl,
        serverToken
      );
    }

    // Print summary
    printSummary(hasArtifacts, artifactCount);

  } catch (error) {
    if (error instanceof Error) {
      core.setFailed(error.message);
    } else {
      core.setFailed('Unknown error occurred');
    }
  }
}

// Run when executed directly
if (require.main === module) {
  run();
}
