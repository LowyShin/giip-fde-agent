#!/usr/bin/env node
/**
 * phase8-review-stop.js - Generate quality review summary after review phase
 *
 * Purpose: Guide next steps after code review
 * Hook: Stop for phase-8-review skill
 *
 * Converted from: scripts/phase8-review-stop.sh
 */

const { outputAllow } = require('../lib/common.js');

// Output guidance for next steps after review phase
const message = `📋 Code Review Phase completed.

Review Summary:
1. Check docs/03-analysis/ for review reports
2. Ensure all refactoring items are addressed
3. Run /pdca-analyze for final gap analysis

Next: Phase 9 (Deployment) when review passes`;

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
