# Available Skills & Commands

This document summarizes the available skills and commands in the GIIP Agent system.

## 🛠️ Skills & Commands

### PDCA Skill (Unified)
| Command | Description |
|---------|-------------|
| `/pdca status` | Check current PDCA status |
| `/pdca plan {feature}` | Generate Plan document |
| `/pdca design {feature}` | Generate Design document |
| `/pdca do {feature}` | Implementation guide |
| `/pdca analyze {feature}` | Run Gap analysis |
| `/pdca iterate {feature}` | Auto-fix iteration loop |
| `/pdca report {feature}` | Generate completion report |
| `/pdca next` | Guide to next PDCA step |

### Level Skills
| Command | Description |
|---------|-------------|
| `/starter` | Initialize/guide Starter project |
| `/dynamic` | Initialize/guide Dynamic project |
| `/enterprise` | Initialize/guide Enterprise project |

### Pipeline Skills
| Command | Description |
|---------|-------------|
| `/development-pipeline start` | Start development pipeline guide |
| `/development-pipeline status` | Check pipeline progress |
| `/development-pipeline next` | Guide to next pipeline phase |
| `/code-review` | Code review and quality analysis |

### 🛡️ Gstack Skills (v1.5.0)
| Skill | Description |
|-------|-------------|
| `/office-hours` | Product reframing and design doc generation |
| `/ceo-review` | Founder mode thinking and taste review |
| `/careful` | Safety guardrails for destructive commands |
| `/freeze` | Edit lock for specific directories |
| `/guard` | Combo of /careful and /freeze |
| `/cso` | Chief Security Officer audit (OWASP/STRIDE) |

### K-Layer Knowledge System
| Skill | Description |
|-------|-------------|
| `k-layer` | 작업 이력에서 근거가 연결된 클레임을 추출하고 축적하여 지능적인 답변을 제공 |

**K-Layer 명령어**:
- `/k-layer search {검색어}` – 기존 지식 베이스 검색
- `/k-layer add {topic}` – 새로운 작업 이력의 claim 추가
- `/k-layer summary` – 전체 knowledge base 요약
- `/k-layer invalidate {topic} {CLAIM-NNN}` – 특정 claim 폐기
