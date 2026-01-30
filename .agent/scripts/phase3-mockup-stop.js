#!/usr/bin/env node
/**
 * phase3-mockup-stop.js - Guide next steps after Mockup phase
 *
 * Purpose: Suggest Phase 4 (API) after Mockup phase completion
 * Hook: Stop for phase-3-mockup skill
 *
 * v1.4.0: Pipeline Phase automation
 */

const { outputAllow, checkPhaseDeliverables, loadPdcaStatus } = require('../lib/common.js');

// Check if Phase 3 deliverables are complete
const deliverables = checkPhaseDeliverables(3);
const status = loadPdcaStatus();
const level = status?.pipeline?.level || 'Dynamic';

let message;

if (deliverables.allComplete) {
  message = `✅ Phase 3 (Mockup/Wireframe) completed!

Deliverables verified:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '❌'} ${item.name}`).join('\n')}

🎯 Next: Phase 4 - API Design & Implementation
   Run: /phase-4-api to define backend APIs`;

  // Starter level might skip API phase
  if (level === 'Starter') {
    message += `

💡 Starter Level: If your site is static (no backend),
   you can skip directly to Phase 5: /phase-5-design-system`;
  } else {
    message += `

💡 Tip: Define API contracts before implementation.
   Use Zero Script QA (/zero-script-qa) to validate APIs.`;
  }
} else {
  message = `📋 Phase 3 (Mockup/Wireframe) in progress.

Deliverables status:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '⏳'} ${item.name}`).join('\n')}

Complete remaining items before proceeding to Phase 4.`;
}

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
