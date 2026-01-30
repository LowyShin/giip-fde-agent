#!/usr/bin/env node
/**
 * phase5-design-post.js - Verify design token consistency after component write
 *
 * Purpose: Check for design token usage in UI component files
 * Hook: PostToolUse (Write) for phase-5-design-system skill
 *
 * Converted from: scripts/phase5-design-post.sh
 */

const {
  readStdinSync,
  parseHookInput,
  isUiFile,
  outputAllow,
  outputEmpty
} = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath, content } = parseHookInput(input);

// Only process UI files
if (!isUiFile(filePath)) {
  outputEmpty();
  process.exit(0);
}

// Check for design token patterns
const warnings = [];

// Check for hardcoded colors (hex, rgb, hsl)
const colorPatterns = [
  /#[0-9a-fA-F]{3,8}\b/,
  /rgb\s*\(/i,
  /hsl\s*\(/i
];

for (const pattern of colorPatterns) {
  if (pattern.test(content)) {
    warnings.push('Hardcoded color detected. Consider using design tokens (e.g., colors.primary).');
    break;
  }
}

// Check for hardcoded spacing (px values)
if (/\d+px/.test(content) && !/className/.test(content)) {
  warnings.push('Hardcoded px values detected. Consider using spacing tokens.');
}

// Check for hardcoded font sizes
if (/font-size:\s*\d+/.test(content)) {
  warnings.push('Hardcoded font-size detected. Consider using typography tokens.');
}

// Output warnings if any
if (warnings.length > 0) {
  outputAllow(`Design System Check: ${warnings.join(' | ')}`, 'PostToolUse');
} else {
  outputEmpty();
}
