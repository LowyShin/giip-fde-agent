#!/usr/bin/env node
/**
 * pre-write.js - Unified PreToolUse/BeforeTool hook for Write|Edit operations (v1.4.2)
 * Supports: Claude Code (PreToolUse), Gemini CLI (BeforeTool)
 *
 * Purpose: PDCA check, task classification, convention hints, permission check
 * Hook: PreToolUse (Claude Code) / BeforeTool (Gemini CLI)
 * Philosophy: Automation First - Guide, don't block
 *
 * v1.4.2 Changes:
 * - Added permission check integration (FR-05)
 *
 * v1.4.0 Changes:
 * - Added debug logging for hook verification
 * - Added PDCA status update for "do" phase
 *
 * Converted from: scripts/pre-write.sh
 */

const {
  readStdinSync,
  parseHookInput,
  isSourceFile,
  isCodeFile,
  isEnvFile,
  extractFeature,
  findDesignDoc,
  findPlanDoc,
  classifyTaskByLines,
  getPdcaLevel,
  outputAllow,
  outputBlock,
  outputEmpty,
  generateTaskGuidance,
  debugLog,
  updatePdcaStatus
} = require('../lib/common.js');

// v1.4.2: Permission Manager (FR-05)
let permissionManager;
try {
  permissionManager = require('../lib/permission-manager.js');
} catch (e) {
  // Fallback if module not available
  permissionManager = null;
}

// Read input from stdin
const input = readStdinSync();
const { filePath, content } = parseHookInput(input);

// Debug log hook execution
debugLog('PreToolUse', 'Hook started', { filePath: filePath || 'none' });

// Skip if no file path
if (!filePath) {
  debugLog('PreToolUse', 'Skipped - no file path');
  outputEmpty();
  process.exit(0);
}

// Collect context messages
const contextParts = [];

// ============================================================
// 0. Permission Check (v1.4.2 - FR-05)
// ============================================================
if (permissionManager) {
  const toolName = input.tool_name || 'Write';  // Write or Edit
  const permission = permissionManager.checkPermission(toolName, filePath);

  if (permission === 'deny') {
    debugLog('PreToolUse', 'Permission denied', { filePath, tool: toolName });
    outputBlock(`${toolName} to ${filePath} is denied by permission policy.`);
    process.exit(2);
  }

  if (permission === 'ask') {
    contextParts.push(`${toolName} to ${filePath} requires confirmation.`);
    debugLog('PreToolUse', 'Permission requires confirmation', { filePath, tool: toolName });
  }
}

// ============================================================
// 1. Task Classification (v1.3.0 - Line-based, Automation First)
// ============================================================
let classification = 'quick_fix';
let pdcaLevel = 'none';
let lineCount = 0;

if (content) {
  lineCount = content.split('\n').length;
  classification = classifyTaskByLines(content);
  pdcaLevel = getPdcaLevel(classification);
}

// ============================================================
// 2. PDCA Document Check (for source files)
// ============================================================
let feature = '';
let designDoc = '';
let planDoc = '';

if (isSourceFile(filePath)) {
  feature = extractFeature(filePath);

  if (feature) {
    designDoc = findDesignDoc(feature);
    planDoc = findPlanDoc(feature);

    // Update PDCA status to "do" phase when source file is being written
    updatePdcaStatus(feature, 'do', {
      lastFile: filePath
    });

    debugLog('PreToolUse', 'PDCA status updated', {
      feature,
      phase: 'do',
      hasDesignDoc: !!designDoc
    });
  }
}

// ============================================================
// 3. Generate PDCA Guidance (v1.3.0 - No blocking, guide only)
// ============================================================
switch (pdcaLevel) {
  case 'none':
    // Quick Fix - no guidance needed
    break;
  case 'light':
    // Minor Change - light mention
    contextParts.push(`Minor change (${lineCount} lines). PDCA optional.`);
    break;
  case 'recommended':
    // Feature - recommend design doc
    if (designDoc) {
      contextParts.push(`Feature (${lineCount} lines). Design doc exists: ${designDoc}`);
    } else if (feature) {
      contextParts.push(`Feature (${lineCount} lines). Design doc recommended for '${feature}'. Consider /pdca-design ${feature}`);
    } else {
      contextParts.push(`Feature-level change (${lineCount} lines). Design doc recommended.`);
    }
    break;
  case 'required':
    // Major Feature - strongly recommend (but don't block)
    if (designDoc) {
      contextParts.push(`Major feature (${lineCount} lines). Design doc exists: ${designDoc}. Refer during implementation.`);
    } else if (feature) {
      contextParts.push(`Major feature (${lineCount} lines) without design doc. Strongly recommend /pdca-design ${feature} first.`);
    } else {
      contextParts.push(`Major feature (${lineCount} lines). Design doc strongly recommended before implementation.`);
    }
    break;
}

// Add reference to existing PDCA docs if not already mentioned
if (planDoc && !designDoc && pdcaLevel !== 'none' && pdcaLevel !== 'light') {
  contextParts.push(`Plan exists at ${planDoc}. Design doc not yet created.`);
}

// ============================================================
// 4. Convention Hints (for code files)
// ============================================================
if (isCodeFile(filePath)) {
  // Only add convention hints for larger changes
  if (pdcaLevel === 'recommended' || pdcaLevel === 'required') {
    contextParts.push('Conventions: Components=PascalCase, Functions=camelCase, Constants=UPPER_SNAKE_CASE');
  }
} else if (isEnvFile(filePath)) {
  contextParts.push('Env naming: NEXT_PUBLIC_* (client), DB_* (database), API_* (external), AUTH_* (auth)');
}

// ============================================================
// 5. Task System Guidance (v1.3.1 - FR-02)
// ============================================================
if (feature && (pdcaLevel === 'recommended' || pdcaLevel === 'required')) {
  const taskHint = generateTaskGuidance('do', feature, 'design');
  contextParts.push(taskHint);
}

// ============================================================
// Output combined context
// ============================================================
debugLog('PreToolUse', 'Hook completed', {
  classification,
  pdcaLevel,
  feature: feature || 'none',
  contextCount: contextParts.length
});

if (contextParts.length > 0) {
  // v1.4.0: PreToolUse hook에 맞는 스키마 사용
  outputAllow(contextParts.join(' | '), 'PreToolUse');
} else {
  outputEmpty();
}
