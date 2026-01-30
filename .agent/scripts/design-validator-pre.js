#!/usr/bin/env node
/**
 * design-validator-pre.js - Auto-detect new design files and trigger validation
 *
 * Purpose: Provide validation checklist when writing design documents
 * Hook: PreToolUse (Write) for design-validator agent
 *
 * Converted from: scripts/design-validator-pre.sh
 */

const { readStdinSync, parseHookInput, outputAllow, outputEmpty } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath } = parseHookInput(input);

// Check if file is a design document
if (filePath.includes('docs/02-design/') && filePath.endsWith('.md')) {
  const message = `📋 Design Document Detected!

Validation checklist:
- [ ] Overview section
- [ ] Requirements section
- [ ] Architecture diagram
- [ ] Data model
- [ ] API specification
- [ ] Error handling

After writing, run validation to check completeness.`;

  // v1.4.0: PreToolUse hook에 맞는 스키마 사용
  outputAllow(message, 'PreToolUse');
} else {
  outputEmpty();
}
