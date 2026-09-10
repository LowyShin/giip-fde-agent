/**
 * Windows Hook Doctor
 *
 * FDE가 소유한 .agent 훅만 진단한다. 외부 플러그인, 사용자 설정, 명령 내용은
 * 수정하지 않으며 UTF-8 BOM/CRLF 정규화만 backup-once 방식으로 복구한다.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const MANIFEST_PATH = path.join('hooks', 'hooks.json');
const CRITICAL_EVENTS = new Set(['PreToolUse']);
const MAX_HEALTH_LOG_LINES = 50;

function relativePortable(root, target) {
  return path.relative(root, target).split(path.sep).join('/');
}

function isInside(root, target) {
  const resolvedRoot = fs.existsSync(root) ? fs.realpathSync(root) : path.resolve(root);
  const resolvedTarget = fs.existsSync(target) ? fs.realpathSync(target) : path.resolve(target);
  const relative = path.relative(resolvedRoot, resolvedTarget);
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function normalizeText(raw) {
  return raw.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
}

function commandTarget(command) {
  if (typeof command !== 'string') return null;
  const match = command.match(/\$\{CLAUDE_PLUGIN_ROOT\}[\\/]+([^\s"'`;&|]+)/);
  return match ? match[1].replace(/[\\/]+/g, path.sep) : null;
}

function collectCommandHooks(manifest) {
  const commands = [];
  const eventMap = manifest && manifest.hooks;
  if (!eventMap || typeof eventMap !== 'object') return commands;

  for (const [event, groups] of Object.entries(eventMap)) {
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      if (!group || !Array.isArray(group.hooks)) continue;
      for (const hook of group.hooks) {
        if (hook && hook.type === 'command') {
          commands.push({ event, command: hook.command });
        }
      }
    }
  }
  return commands;
}

function defaultProbeNode() {
  const result = spawnSync(process.execPath, ['-e', 'process.exit(0)'], {
    windowsHide: true,
    timeout: 3000,
    stdio: 'ignore',
  });
  return !result.error && result.status === 0;
}

function issue(code, severity, event, target) {
  const value = { code, severity };
  if (event) value.event = event;
  if (target) value.target = target;
  return value;
}

function inspect(root, probeNode) {
  const issues = [];
  const manifestFile = path.join(root, MANIFEST_PATH);
  let raw;

  if (!isInside(root, manifestFile)) {
    return { issues: [issue('manifest-outside-agent-root', 'critical')], commands: [] };
  }

  try {
    raw = fs.readFileSync(manifestFile, 'utf8');
  } catch (_error) {
    return { issues: [issue('manifest-unreadable', 'critical')], commands: [] };
  }

  if (raw.startsWith('\uFEFF')) issues.push(issue('utf8-bom', 'repairable', null, MANIFEST_PATH));
  if (raw.includes('\r\n')) issues.push(issue('crlf', 'repairable', null, MANIFEST_PATH));

  let manifest;
  try {
    manifest = JSON.parse(raw.replace(/^\uFEFF/, ''));
  } catch (_error) {
    return { issues: [...issues, issue('manifest-invalid-json', 'critical')], commands: [] };
  }

  const commands = collectCommandHooks(manifest);
  if (!probeNode()) issues.push(issue('node-unavailable', 'critical'));

  for (const entry of commands) {
    const relativeTarget = commandTarget(entry.command);
    if (!relativeTarget) continue;
    const target = path.resolve(root, relativeTarget);
    const severity = CRITICAL_EVENTS.has(entry.event) ? 'critical' : 'warning';

    if (!isInside(root, target)) {
      issues.push(issue('outside-agent-root', severity, entry.event, relativeTarget.split(path.sep).join('/')));
      continue;
    }

    if (!fs.existsSync(target)) {
      issues.push(issue('missing-target', severity, entry.event, relativeTarget.split(path.sep).join('/')));
      continue;
    }

    let targetRaw;
    try {
      targetRaw = fs.readFileSync(target, 'utf8');
    } catch (_error) {
      issues.push(issue('target-unreadable', severity, entry.event, relativeTarget.split(path.sep).join('/')));
      continue;
    }
    if (targetRaw.startsWith('\uFEFF')) issues.push(issue('utf8-bom', 'repairable', entry.event, relativeTarget.split(path.sep).join('/')));
    if (targetRaw.includes('\r\n')) issues.push(issue('crlf', 'repairable', entry.event, relativeTarget.split(path.sep).join('/')));
  }

  return { issues, commands };
}

function repairFile(root, target, changedFiles) {
  if (!isInside(root, target) || !fs.existsSync(target)) return;
  const raw = fs.readFileSync(target, 'utf8');
  const normalized = normalizeText(raw);
  if (normalized === raw) return;

  const backup = path.join(root, 'runtime', 'hook-backups', `${relativePortable(root, target)}.bak`);
  if (!fs.existsSync(backup)) {
    fs.mkdirSync(path.dirname(backup), { recursive: true });
    fs.copyFileSync(target, backup);
  }
  fs.writeFileSync(target, normalized, 'utf8');
  changedFiles.push(relativePortable(root, target));
}

function repairOwnedFiles(root, commands) {
  const changedFiles = [];
  repairFile(root, path.join(root, MANIFEST_PATH), changedFiles);

  const targets = new Set();
  for (const entry of commands) {
    const relativeTarget = commandTarget(entry.command);
    if (!relativeTarget) continue;
    const target = path.resolve(root, relativeTarget);
    if (isInside(root, target)) targets.add(target);
  }
  for (const target of targets) repairFile(root, target, changedFiles);
  return changedFiles;
}

function statusFor(issues) {
  if (issues.some((entry) => entry.severity === 'critical')) return 'blocked';
  if (issues.some((entry) => entry.severity === 'warning')) return 'warning';
  if (issues.some((entry) => entry.severity === 'repairable')) return 'repairable';
  return 'healthy';
}

function appendHealthLog(root, result) {
  const runtimeDir = path.join(root, 'runtime');
  const logFile = path.join(runtimeDir, 'windows-hook-health.jsonl');
  fs.mkdirSync(runtimeDir, { recursive: true });

  let previous = [];
  if (fs.existsSync(logFile)) {
    previous = fs.readFileSync(logFile, 'utf8').split('\n').filter(Boolean);
  }
  const record = JSON.stringify({
    at: new Date().toISOString(),
    status: result.status,
    issueCodes: result.issues.map((entry) => entry.code),
    changedFiles: result.changedFiles,
  });
  const lines = [...previous, record].slice(-MAX_HEALTH_LOG_LINES);
  fs.writeFileSync(logFile, `${lines.join('\n')}\n`, 'utf8');
}

function run(options = {}) {
  const root = path.resolve(options.root || path.join(__dirname, '..'));
  const platform = options.platform || process.platform;
  const changedFiles = [];

  if (platform !== 'win32') {
    return { status: 'skipped', issues: [], changedFiles, inspectedHooks: 0 };
  }

  const probeNode = options.probeNode || defaultProbeNode;
  let inspection = inspect(root, probeNode);

  const hasRepairableIssue = inspection.issues.some((entry) => entry.severity === 'repairable');
  if (options.repair && hasRepairableIssue) {
    changedFiles.push(...repairOwnedFiles(root, inspection.commands));
    inspection = inspect(root, probeNode);
  }

  const result = {
    status: statusFor(inspection.issues),
    issues: inspection.issues,
    changedFiles,
    inspectedHooks: inspection.commands.length,
  };

  if (options.writeLog !== false) {
    try {
      appendHealthLog(root, result);
    } catch (_error) {
      // 진단 자체의 성공/실패를 부가 로그 오류로 가리지 않는다.
    }
  }
  return result;
}

module.exports = {
  collectCommandHooks,
  commandTarget,
  normalizeText,
  run,
};
