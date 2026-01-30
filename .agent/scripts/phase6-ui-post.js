#!/usr/bin/env node
/**
 * phase6-ui-post.js - Verify layer separation after UI implementation
 *
 * Purpose: Check that UI follows proper layer architecture
 * Hook: PostToolUse (Write) for phase-6-ui-integration skill
 *
 * Converted from: scripts/phase6-ui-post.sh
 */

const { readStdinSync, parseHookInput, isUiFile, outputAllow, outputEmpty } = require('../lib/common.js');

// Read input from stdin
const input = readStdinSync();
const { filePath } = parseHookInput(input);

// Check layer patterns
const isUiLayer = isUiFile(filePath) ||
  filePath.includes('/pages/') ||
  filePath.includes('/components/') ||
  filePath.includes('/features/');

const isServiceLayer = filePath.includes('/services/') ||
  filePath.includes('/api/') ||
  filePath.includes('/lib/');

if (isUiLayer) {
  const message = `🔍 UI Layer Check:
- Components should use hooks, not direct fetch
- Follow: Components → hooks → services → apiClient
- No business logic in UI components`;

  outputAllow(message, 'PostToolUse');
} else if (isServiceLayer) {
  const message = `🔍 Service Layer Check:
- Services should only call apiClient
- No direct DOM manipulation
- Keep domain logic isolated`;

  outputAllow(message, 'PostToolUse');
} else {
  outputEmpty();
}
