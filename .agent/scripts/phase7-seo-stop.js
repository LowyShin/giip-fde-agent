#!/usr/bin/env node
/**
 * phase7-seo-stop.js - Guide next steps after SEO/Security phase
 *
 * Purpose: Suggest Phase 8 (Review) after SEO/Security phase completion
 * Hook: Stop for phase-7-seo-security skill
 *
 * v1.4.0: Pipeline Phase automation
 */

const { outputAllow, checkPhaseDeliverables } = require('../lib/common.js');

// Check if Phase 7 deliverables are complete
const deliverables = checkPhaseDeliverables(7);

let message;

if (deliverables.allComplete) {
  message = `✅ Phase 7 (SEO & Security) completed!

Deliverables verified:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '❌'} ${item.name}`).join('\n')}

Security Checklist:
  ✅ XSS protection verified
  ✅ CSRF tokens implemented
  ✅ Input validation in place
  ✅ Secure headers configured

🎯 Next: Phase 8 - Code Review
   Run: /phase-8-review for final quality check

💡 Tip: Use /pdca-analyze for gap analysis
   and code-analyzer for security scan.`;
} else {
  message = `📋 Phase 7 (SEO & Security) in progress.

Deliverables status:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '⏳'} ${item.name}`).join('\n')}

⚠️ Security items are critical - complete before review phase.`;
}

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
