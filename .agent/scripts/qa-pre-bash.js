#!/usr/bin/env node
/**
 * qa-pre-bash.js - Validate bash commands are safe for QA testing
 *
 * Purpose: Block destructive commands during QA testing sessions
 * Hook: PreToolUse (Bash) for zero-script-qa skill
 *
 * Converted from: scripts/qa-pre-bash.sh
 */

const { readStdinSync, parseHookInput, outputAllow, outputBlock } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { command } = parseHookInput(input);

// List of destructive patterns to block
const DESTRUCTIVE_PATTERNS = [
  'rm -rf',
  'rm -r',
  'DROP TABLE',
  'DROP DATABASE',
  'DELETE FROM',
  'TRUNCATE',
  '> /dev/',
  'mkfs',
  'dd if=',
  ':(){ :|:& };:'  // Fork bomb
];

// Check for destructive patterns
for (const pattern of DESTRUCTIVE_PATTERNS) {
  if (command.includes(pattern)) {
    outputBlock(`Destructive command detected: '${pattern}'. QA testing should not include destructive operations.`);
    process.exit(0);
  }
}

// Allow safe commands with context
// v1.4.0: PreToolUse hook에 맞는 스키마 사용
outputAllow('QA Testing: Command validated as safe for testing environment.', 'PreToolUse');
