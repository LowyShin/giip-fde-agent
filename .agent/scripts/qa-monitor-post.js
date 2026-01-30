#!/usr/bin/env node
/**
 * qa-monitor-post.js - Trigger pdca-iterator on critical issues
 *
 * Purpose: Suggest auto-fix when critical QA issues are found
 * Hook: PostToolUse (Write) for qa-monitor agent
 *
 * Converted from: scripts/qa-monitor-post.sh
 */

const { readStdinSync, parseHookInput, outputAllow, outputEmpty } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath, content } = parseHookInput(input);

// Check if this is a QA report
const isQaReport = filePath.includes('docs/03-analysis/') && filePath.toLowerCase().includes('qa');

if (isQaReport) {
  // Check for critical issues in the content
  const hasCritical = /🔴 Critical|Critical.*[1-9]/i.test(content);

  if (hasCritical) {
    const message = `🚨 Critical issues detected in QA report!

Recommended actions:
1. Fix critical issues immediately
2. Run /pdca-iterate for auto-fix
3. Re-run Zero Script QA after fixes`;

    outputAllow(message, 'PostToolUse');
  } else {
    const message = `✅ QA Report saved. No critical issues detected.

Next steps:
1. Review warning items if any
2. Proceed to next phase when ready`;

    outputAllow(message, 'PostToolUse');
  }
} else {
  outputEmpty();
}
