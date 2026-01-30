#!/usr/bin/env node
/**
 * archive-feature.js - Archive completed PDCA documents (v1.3.1)
 *
 * Purpose: Move completed PDCA documents to archive folder
 * Usage: node archive-feature.js <feature-name>
 * Creates: docs/archive/YYYY-MM/{feature}/
 *
 * Converted from: scripts/archive-feature.sh
 */

const fs = require('fs');
const path = require('path');
const { PROJECT_DIR } = require('../lib/common.js');

// Get feature name from argument
const feature = process.argv[2];

if (!feature) {
  console.log('Usage: archive-feature.js <feature-name>');
  console.log('Example: archive-feature.js login');
  process.exit(1);
}

// Set up paths
const now = new Date();
const archiveDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
const archiveDir = path.join(PROJECT_DIR, 'docs', 'archive', archiveDate, feature);

// Document paths to check
const docPaths = {
  plan: path.join(PROJECT_DIR, `docs/01-plan/features/${feature}.plan.md`),
  design: path.join(PROJECT_DIR, `docs/02-design/features/${feature}.design.md`),
  analysis: path.join(PROJECT_DIR, `docs/03-analysis/${feature}.analysis.md`),
  analysisAlt: path.join(PROJECT_DIR, `docs/03-analysis/${feature}.gap-analysis.md`),
  report: path.join(PROJECT_DIR, `docs/04-report/${feature}.report.md`),
  reportAlt: path.join(PROJECT_DIR, `docs/04-report/${feature}.completion-report.md`)
};

// Count existing documents
const existingDocs = [];
if (fs.existsSync(docPaths.plan)) existingDocs.push({ type: 'plan', path: docPaths.plan });
if (fs.existsSync(docPaths.design)) existingDocs.push({ type: 'design', path: docPaths.design });
if (fs.existsSync(docPaths.analysis)) existingDocs.push({ type: 'analysis', path: docPaths.analysis });
else if (fs.existsSync(docPaths.analysisAlt)) existingDocs.push({ type: 'gap-analysis', path: docPaths.analysisAlt });
if (fs.existsSync(docPaths.report)) existingDocs.push({ type: 'report', path: docPaths.report });
else if (fs.existsSync(docPaths.reportAlt)) existingDocs.push({ type: 'completion-report', path: docPaths.reportAlt });

if (existingDocs.length === 0) {
  console.log(`Error: No PDCA documents found for feature '${feature}'`);
  console.log('');
  console.log('Checked paths:');
  console.log(`  - ${docPaths.plan}`);
  console.log(`  - ${docPaths.design}`);
  console.log(`  - ${docPaths.analysis}`);
  console.log(`  - ${docPaths.report}`);
  process.exit(1);
}

// Create archive directory
fs.mkdirSync(archiveDir, { recursive: true });

// Move documents
const movedDocs = [];
for (const doc of existingDocs) {
  const destPath = path.join(archiveDir, path.basename(doc.path));
  fs.renameSync(doc.path, destPath);
  movedDocs.push(`${doc.type}.md`);
}

// Update archive index
const indexDir = path.join(PROJECT_DIR, 'docs', 'archive', archiveDate);
const indexFile = path.join(indexDir, '_INDEX.md');

if (!fs.existsSync(indexFile)) {
  fs.mkdirSync(indexDir, { recursive: true });
  const header = `# Archive - ${archiveDate}

완료된 PDCA 문서 아카이브입니다.

| Feature | Archived Date | Status | Documents |
|---------|---------------|--------|-----------|
`;
  fs.writeFileSync(indexFile, header);
}

// Add entry to index
const today = now.toISOString().split('T')[0];
const docList = movedDocs.join(', ');
const entry = `| ${feature} | ${today} | Completed | ${docList} |\n`;
fs.appendFileSync(indexFile, entry);

// Output result
console.log(`✅ Archived: ${feature}`);
console.log('');
console.log(`📁 Location: ${archiveDir}`);
console.log(`📄 Documents moved: ${movedDocs.length}`);
for (const doc of movedDocs) {
  console.log(`   - ${doc}`);
}
console.log('');
console.log(`📋 Index updated: ${indexFile}`);
