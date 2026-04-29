# PDCA Workflow

The development process follows the Plan-Do-Check-Act (PDCA) cycle for continuous improvement.

## 🔄 Workflow Phases

### Phase 1: Plan
- Use `/pdca plan {feature}` to create plan document
- Stored in `docs/01-plan/features/{feature}.plan.md`

### Phase 2: Design
- Use `/pdca design {feature}` to create design document
- Stored in `docs/02-design/features/{feature}.design.md`

### Phase 3: Do (Implementation)
- Implement based on design document
- Apply coding/naming conventions defined in `bkit.config.json`

### Phase 4: Check
- Use `/pdca analyze {feature}` for gap analysis
- Stored in `docs/03-analysis/{feature}.analysis.md`

### Phase 5: Act
- Use `/pdca iterate {feature}` for auto-fix if < 90%
- Use `/pdca report {feature}` for completion report
- Stored in `docs/90-reports/{feature}.report.md`
