#!/usr/bin/env node
/**
 * select-template.js - Select appropriate template based on project level
 *
 * Purpose: Determine correct template file based on project level detection
 * Usage: node select-template.js <template-type> [feature-name]
 *
 * Converted from: scripts/select-template.sh
 */

const fs = require('fs');
const path = require('path');
const { detectLevel, PROJECT_DIR, PLUGIN_ROOT } = require('../lib/common.js');

// Parse arguments
const args = process.argv.slice(2);
const templateType = args[0]; // plan, design, analysis, report
const featureName = args[1] || '';

if (!templateType) {
  console.error('Usage: select-template.js <template-type> [feature-name]');
  console.error('Template types: plan, design, analysis, report');
  process.exit(1);
}

// Detect project level
const level = detectLevel();

// Template directory (prefer plugin templates)
const pluginTemplateDir = path.join(PLUGIN_ROOT, 'templates');
const localTemplateDir = path.join(PROJECT_DIR, 'templates');

const templateDir = fs.existsSync(pluginTemplateDir) ? pluginTemplateDir : localTemplateDir;

// Determine template file based on level
let templateFile = '';

switch (level.toLowerCase()) {
  case 'starter':
    templateFile = path.join(templateDir, `${templateType}-starter.template.md`);
    break;
  case 'enterprise':
    templateFile = path.join(templateDir, `${templateType}-enterprise.template.md`);
    break;
  default:
    templateFile = path.join(templateDir, `${templateType}.template.md`);
}

// Fallback to default template if level-specific doesn't exist
if (!fs.existsSync(templateFile)) {
  templateFile = path.join(templateDir, `${templateType}.template.md`);
}

// Final check
if (!fs.existsSync(templateFile)) {
  console.error(`ERROR: Template not found: ${templateType}.template.md`);
  process.exit(1);
}

// Output the selected template path (simple mode)
if (!featureName) {
  console.log(templateFile);
  process.exit(0);
}

// If feature name is provided, output JSON with variables
const date = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
let projectName = '';
let version = '';

// Try to get project name from package.json
const packageJsonPath = path.join(PROJECT_DIR, 'package.json');
if (fs.existsSync(packageJsonPath)) {
  try {
    const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    projectName = pkg.name || '';
    version = pkg.version || '';
  } catch (e) { /* ignore */ }
}

// Try to get from CLAUDE.md if not found
if (!projectName) {
  const claudeMdPath = path.join(PROJECT_DIR, 'CLAUDE.md');
  if (fs.existsSync(claudeMdPath)) {
    try {
      const content = fs.readFileSync(claudeMdPath, 'utf8');
      const match = content.match(/^#\s+(.+)$/m);
      if (match) projectName = match[1];
    } catch (e) { /* ignore */ }
  }
}

// Output as JSON
const output = {
  template: templateFile,
  level: level,
  feature: featureName,
  date: date,
  project: projectName,
  version: version
};

console.log(JSON.stringify(output, null, 2));
