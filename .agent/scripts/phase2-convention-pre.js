#!/usr/bin/env node
/**
 * phase2-convention-pre.js - Check coding style conventions before write
 *
 * Purpose: Remind developers of naming conventions
 * Hook: PreToolUse (Write|Edit) for phase-2-convention skill
 *
 * Converted from: scripts/phase2-convention-pre.sh
 */

const { readStdinSync, parseHookInput, outputAllow, outputEmpty } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath } = parseHookInput(input);

// Check file type and provide appropriate convention hints
const codeExtensions = ['.ts', '.tsx', '.js', '.jsx'];
const isCodeFile = codeExtensions.some(ext => filePath.endsWith(ext));
const isEnvFile = filePath.includes('.env');

if (isCodeFile) {
  const message = `📏 Convention Check:
- Components: PascalCase
- Functions: camelCase
- Constants: UPPER_SNAKE_CASE
- Files: kebab-case or PascalCase

See CONVENTIONS.md for full rules`;

  // v1.4.0: PreToolUse hook에 맞는 스키마 사용
  outputAllow(message, 'PreToolUse');
} else if (isEnvFile) {
  const message = `🔒 Environment Variable Convention:
- NEXT_PUBLIC_* for client
- DB_* for database
- API_* for external APIs
- AUTH_* for authentication`;

  // v1.4.0: PreToolUse hook에 맞는 스키마 사용
  outputAllow(message, 'PreToolUse');
} else {
  outputEmpty();
}
