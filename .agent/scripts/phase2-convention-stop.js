#!/usr/bin/env node
/**
 * phase2-convention-stop.js - Guide next steps after Conventions phase
 *
 * Purpose: Suggest Phase 3 (Mockup) after Conventions phase completion
 * Hook: Stop for phase-2-convention skill
 *
 * v1.4.0: Pipeline Phase automation
 */

const { outputAllow, checkPhaseDeliverables } = require('../lib/common.js');

// Check if Phase 2 deliverables are complete
const deliverables = checkPhaseDeliverables(2);

let message;

if (deliverables.allComplete) {
  message = `✅ Phase 2 (Coding Conventions) completed!

Deliverables verified:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '❌'} ${item.name}`).join('\n')}

🎯 Next: Phase 3 - Mockup/Wireframe
   Run: /phase-3-mockup to create UI prototypes

💡 Tip: Mockups help validate UX before coding.
   For Starter level, simple HTML/CSS mockups are sufficient.`;
} else {
  message = `📋 Phase 2 (Coding Conventions) in progress.

Deliverables status:
${deliverables.items.map(item => `  ${item.exists ? '✅' : '⏳'} ${item.name}`).join('\n')}

Complete remaining items before proceeding to Phase 3.`;
}

// v1.4.0: Stop hook에 맞는 스키마 사용
outputAllow(message, 'Stop');
