#!/usr/bin/env node
/**
 * sync-folders.js - Synchronize .claude/ (source of truth) to root folders
 *
 * Purpose: Keep root-level skills/, agents/, commands/, templates/ in sync with .claude/ versions
 * Usage: node sync-folders.js [--dry-run] [--force] [--reverse]
 *
 * Converted from: scripts/sync-folders.sh
 */

const fs = require('fs');
const path = require('path');

const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');

// ============================================================
// Configuration
// ============================================================
const SYNC_FOLDERS = ['skills', 'agents', 'commands', 'templates'];

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const FORCE = args.includes('--force');
const REVERSE = args.includes('--reverse');

// Source and target based on direction
const SOURCE_BASE = REVERSE ? PLUGIN_ROOT : path.join(PLUGIN_ROOT, '.claude');
const TARGET_BASE = REVERSE ? path.join(PLUGIN_ROOT, '.claude') : PLUGIN_ROOT;

// ============================================================
// Statistics
// ============================================================
let stats = {
  new: 0,
  updated: 0,
  skipped: 0,
  errors: 0
};

// ============================================================
// Helper Functions
// ============================================================

/**
 * Get all files recursively from a directory
 * @param {string} dir - Directory path
 * @param {string} base - Base path for relative paths
 * @returns {string[]} Array of relative file paths
 */
function getAllFiles(dir, base = dir) {
  const results = [];

  if (!fs.existsSync(dir)) return results;

  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const relativePath = path.relative(base, fullPath);

    if (entry.isDirectory()) {
      results.push(...getAllFiles(fullPath, base));
    } else if (entry.isFile()) {
      results.push(relativePath);
    }
  }

  return results;
}

/**
 * Ensure directory exists
 * @param {string} filePath - File path (will create parent directories)
 */
function ensureDir(filePath) {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Compare two files
 * @param {string} file1 - First file path
 * @param {string} file2 - Second file path
 * @returns {boolean} True if files are identical
 */
function filesMatch(file1, file2) {
  if (!fs.existsSync(file1) || !fs.existsSync(file2)) {
    return false;
  }

  try {
    const content1 = fs.readFileSync(file1);
    const content2 = fs.readFileSync(file2);
    return content1.equals(content2);
  } catch (e) {
    return false;
  }
}

/**
 * Sync a single file
 * @param {string} relativePath - Relative path within the folder
 * @param {string} sourceDir - Source directory
 * @param {string} targetDir - Target directory
 */
function syncFile(relativePath, sourceDir, targetDir) {
  const sourcePath = path.join(sourceDir, relativePath);
  const targetPath = path.join(targetDir, relativePath);

  if (!fs.existsSync(sourcePath)) {
    return;
  }

  const targetExists = fs.existsSync(targetPath);

  if (targetExists && filesMatch(sourcePath, targetPath)) {
    stats.skipped++;
    return;
  }

  if (targetExists && !FORCE) {
    // Check if target is newer (simple mtime comparison)
    const sourceStat = fs.statSync(sourcePath);
    const targetStat = fs.statSync(targetPath);

    if (targetStat.mtime > sourceStat.mtime) {
      console.log(`SKIP (target newer): ${relativePath}`);
      stats.skipped++;
      return;
    }
  }

  const action = targetExists ? 'UPDATE' : 'NEW';

  if (DRY_RUN) {
    console.log(`[DRY-RUN] ${action}: ${relativePath}`);
  } else {
    try {
      ensureDir(targetPath);
      fs.copyFileSync(sourcePath, targetPath);
      console.log(`${action}: ${relativePath}`);

      if (targetExists) {
        stats.updated++;
      } else {
        stats.new++;
      }
    } catch (e) {
      console.error(`ERROR: Failed to copy ${relativePath}: ${e.message}`);
      stats.errors++;
    }
  }
}

/**
 * Sync a folder
 * @param {string} folderName - Folder name (e.g., 'skills')
 */
function syncFolder(folderName) {
  const sourceDir = path.join(SOURCE_BASE, folderName);
  const targetDir = path.join(TARGET_BASE, folderName);

  if (!fs.existsSync(sourceDir)) {
    console.log(`Source folder does not exist: ${sourceDir}`);
    return;
  }

  console.log(`\nSyncing ${folderName}/...`);
  console.log(`  Source: ${sourceDir}`);
  console.log(`  Target: ${targetDir}`);

  const files = getAllFiles(sourceDir);
  console.log(`  Files found: ${files.length}`);

  for (const file of files) {
    syncFile(file, sourceDir, targetDir);
  }
}

// ============================================================
// Main
// ============================================================

function main() {
  console.log('='.repeat(60));
  console.log('bkit Folder Synchronization');
  console.log('='.repeat(60));

  if (DRY_RUN) {
    console.log('Mode: DRY-RUN (no changes will be made)');
  }

  if (REVERSE) {
    console.log('Direction: REVERSE (root → .claude/)');
  } else {
    console.log('Direction: NORMAL (.claude/ → root)');
  }

  if (FORCE) {
    console.log('Option: FORCE (overwrite without checking)');
  }

  // Check if .claude folder exists (for normal mode)
  if (!REVERSE && !fs.existsSync(path.join(PLUGIN_ROOT, '.claude'))) {
    console.log('\n.claude/ folder not found. Nothing to sync.');
    console.log('This plugin uses root-level folders as source of truth.');
    process.exit(0);
  }

  // Sync each folder
  for (const folder of SYNC_FOLDERS) {
    syncFolder(folder);
  }

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('Sync Summary');
  console.log('='.repeat(60));
  console.log(`New files:     ${stats.new}`);
  console.log(`Updated files: ${stats.updated}`);
  console.log(`Skipped:       ${stats.skipped}`);
  console.log(`Errors:        ${stats.errors}`);

  if (DRY_RUN) {
    console.log('\n(Dry-run mode - no files were actually changed)');
  }

  process.exit(stats.errors > 0 ? 1 : 0);
}

main();
