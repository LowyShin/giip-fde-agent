# Check-Act Iteration Loop

The iteration loop ensures high-quality results through automated or manual feedback.

## 🔄 Iteration Loop

```
gap-detector (Check) → Check Match Rate
    ├─ >= 90% → report-generator (Complete)
    ├─ 70-89% → Offer choice (manual/auto)
    └─ < 70% → Recommend pdca-iterator (Act)
                   ↓
              Re-run gap-detector after fixes
                   ↓
              Repeat (max 5 iterations)
```
