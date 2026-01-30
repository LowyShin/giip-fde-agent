#!/usr/bin/env node
/**
 * gap-detector-post.js - Guide next steps after Gap Analysis completion
 *
 * Purpose: Suggest pdca-iterator when match rate is low
 * Hook: PostToolUse (Write) for gap-detector agent
 *
 * Converted from: scripts/gap-detector-post.sh
 */

const { readStdinSync, parseHookInput, outputAllow, outputEmpty } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath } = parseHookInput(input);

// Check if this is an analysis report file
if (filePath.includes('.analysis.md') || filePath.includes('-analysis.md')) {
  const message = `Gap Analysis completed.

If match rate is below 70%, run /pdca-iterate to automatically improve the implementation.`;

  outputAllow(message, 'PostToolUse');
} else {
  outputEmpty();
}
