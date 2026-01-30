#!/usr/bin/env node
/**
 * code-analyzer-pre.js - Block write operations for code-analyzer agent
 *
 * Purpose: Code analyzer is a read-only agent that cannot modify files
 * Hook: PreToolUse (Write|Edit) for code-analyzer agent
 *
 * Created for: v1.4.2 PreToolUse hooks improvement (Design Doc Section 5)
 */

const { outputBlock } = require('../lib/common.js');

// Code analyzer agent is read-only - block all write/edit operations
outputBlock('Code analyzer agent is read-only and cannot modify files');
