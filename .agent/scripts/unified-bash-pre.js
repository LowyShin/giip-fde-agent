#!/usr/bin/env node
/**
 * unified-bash-pre.js - Unified Bash PreToolUse Handler (v1.4.4)
 *
 * GitHub Issue #9354 Workaround:
 * Consolidates Bash PreToolUse hooks from:
 * - phase-9-deployment: phase9-deploy-pre.js
 * - zero-script-qa: qa-pre-bash.js
 * - qa-monitor: qa-pre-bash.js (same as zero-script-qa)
 */

const {
  readStdinSync,
  parseHookInput,
  outputAllow,
  outputBlock,
  debugLog,
  getActiveSkill,
  getActiveAgent
} = require('../lib/common.js');

// ============================================================
// Handler: phase9-deploy-pre
// ============================================================

/**
 * Phase 9 deployment safety checks
 * @param {Object} input - Hook input
 * @returns {boolean} True if blocked
 */
function handlePhase9DeployPre(input) {
  const { command } = parseHookInput(input);
  if (!command) return false;

  // Dangerous deployment patterns that require manual confirmation
  const dangerousPatterns = [
    { pattern: 'kubectl delete', reason: 'Kubernetes resource deletion' },
    { pattern: 'terraform destroy', reason: 'Infrastructure destruction' },
    { pattern: 'aws ec2 terminate', reason: 'EC2 instance termination' },
    { pattern: 'helm uninstall', reason: 'Helm release removal' },
    { pattern: '--force', reason: 'Force flag detected' },
    { pattern: 'production', reason: 'Production environment detected' }
  ];

  for (const { pattern, reason } of dangerousPatterns) {
    if (command.toLowerCase().includes(pattern.toLowerCase())) {
      outputBlock(`Deployment safety: ${reason}. Command '${pattern}' requires manual confirmation.`);
      return true;
    }
  }

  return false;
}

// ============================================================
// Handler: qa-pre-bash (shared by zero-script-qa and qa-monitor)
// ============================================================

/**
 * QA destructive command prevention
 * @param {Object} input - Hook input
 * @returns {boolean} True if blocked
 */
function handleQaPreBash(input) {
  const { command } = parseHookInput(input);
  if (!command) return false;

  const DESTRUCTIVE_PATTERNS = [
    { pattern: 'rm -rf', reason: 'Recursive force deletion' },
    { pattern: 'rm -r', reason: 'Recursive deletion' },
    { pattern: 'DROP TABLE', reason: 'SQL table drop' },
    { pattern: 'DROP DATABASE', reason: 'SQL database drop' },
    { pattern: 'DELETE FROM', reason: 'SQL mass deletion' },
    { pattern: 'TRUNCATE', reason: 'SQL table truncation' },
    { pattern: '> /dev/', reason: 'Device write' },
    { pattern: 'mkfs', reason: 'Filesystem creation' },
    { pattern: 'dd if=', reason: 'Low-level disk operation' }
  ];

  for (const { pattern, reason } of DESTRUCTIVE_PATTERNS) {
    if (command.includes(pattern)) {
      outputBlock(`QA safety: ${reason}. Destructive command '${pattern}' blocked during testing.`);
      return true;
    }
  }

  return false;
}

// ============================================================
// Main Execution
// ============================================================

debugLog('UnifiedBashPre', 'Hook started');

// Read hook context
let input = {};
try {
  input = readStdinSync();
  if (typeof input === 'string') {
    input = JSON.parse(input);
  }
} catch (e) {
  debugLog('UnifiedBashPre', 'Failed to parse input', { error: e.message });
}

// Get current context
const activeSkill = getActiveSkill();
const activeAgent = getActiveAgent();

debugLog('UnifiedBashPre', 'Context', { activeSkill, activeAgent });

let blocked = false;

// Phase 9 deployment checks
if (activeSkill === 'phase-9-deployment') {
  blocked = handlePhase9DeployPre(input);
}

// QA checks (zero-script-qa skill or qa-monitor agent)
if (!blocked && (activeSkill === 'zero-script-qa' || activeAgent === 'qa-monitor')) {
  blocked = handleQaPreBash(input);
}

// Allow if not blocked
if (!blocked) {
  const contextMsg = activeSkill || activeAgent
    ? `Bash command validated for ${activeSkill || activeAgent}.`
    : 'Bash command validated.';
  outputAllow(contextMsg, 'PreToolUse');
}

debugLog('UnifiedBashPre', 'Hook completed', { blocked });
