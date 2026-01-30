#!/usr/bin/env node
/**
 * phase4-api-stop.js - Guide Zero Script QA after API implementation
 *
 * Purpose: Suggest running Zero Script QA after API phase
 * Hook: Stop for phase-4-api skill
 *
 * Converted from: scripts/phase4-api-stop.sh
 */

const { outputAllow } = require('../lib/common.js');

// Output guidance for next steps after API phase
const message = `🎯 API Phase completed.

Next steps:
1. Run Zero Script QA to validate APIs: /zero-script-qa
2. Ensure all endpoints return proper JSON logs
3. Proceed to Phase 5 (Design System) after QA passes`;

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
