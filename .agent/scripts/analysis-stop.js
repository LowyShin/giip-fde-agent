#!/usr/bin/env node
/**
 * analysis-stop.js - Guide report generation after gap analysis
 *
 * Purpose: Provide guidance after gap analysis completion
 * Hook: Stop for phase-8-review skill (gap analysis component)
 *
 * Converted from: scripts/analysis-stop.sh
 */

const { outputAllow } = require('../lib/common.js');

// Output guidance for next steps after gap analysis
const message = `📊 Gap Analysis completed.

Next steps:
1. Save report to docs/03-analysis/
2. If match rate < 70%: Run /pdca-iterate for auto-fix
3. If match rate >= 90%: Proceed to next phase
4. Update design doc if implementation differs intentionally`;

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
