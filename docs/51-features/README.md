# GIIP 업무 자동화 및 행정 에이전트 기능 통합 마스터 가이드 🚀💼

본 프로젝트(`giip-dev-agent`)에 추가된 7가지 사내 행정 및 업무 자동화 모듈들의 사용법과 설정에 관한 통합 가이드라인입니다. 모든 기능은 독자적으로 실행이 가능한 CLI 도구 및 스크립트로 구축되었으며, 외부 연동(Webhook, Google API, OpenClaw 등)을 연계하여 강력한 자동화 환경을 구축할 수 있습니다.

---

## 📂 폴더 구조 및 모듈 일람

모든 자동화 모듈은 `docs/51-features/` 아래에 설계 및 코드 파일과 개별 가이드 문서가 함께 위치해 있습니다:

| 분류 | 폴더명 & 링크 | 핵심 실행 파일 | 상세 역할 |
| :--- | :--- | :--- | :--- |
| **01** | [회의/프로젝트 관리](../../docs/51-features/meeting-management/README.md) | `meeting_manager.js` | 녹음 텍스트 분석, 견적서 및 할 일 자동 생성 |
| **02** | [명함/연락처 자동화](../../docs/51-features/contact-automation/README.md) | `contact_sync.js` | 명함 이미지 정보 추출, 구글 주소록 및 사내 CRM 연동 |
| **03** | [매출/세금계산서](../../docs/51-features/sales-invoicing/README.md) | `sales_tracker.js` | 결제/입금 내역 자동 연동, 청구서 발행, 홈택스 연계 |
| **04** | [파일/이메일 통합](../../docs/51-features/file-email-integration/README.md) | `file_email_sync.js` | 구글 드라이브 업로드, 임직원 업무 메일 통합 검색 |
| **05** | [사내 행정 자동화](../../docs/51-features/admin-automation/README.md) | `admin_cert_generator.js` | 인사 DB 연동 재직증명서 원클릭 자동 생성 |
| **06** | [AI 기획 & 컨설팅](../../docs/51-features/ai-consultant/README.md) | `ai_consultant.js` | 수신 이메일 자동 분류/답장, 계약 불발 회의록 원인 분석 |
| **07** | [슬랙봇 & 브리핑](../../docs/51-features/slackbot-briefing/README.md) | `slackbot_briefing.js` | 아침 스케줄 브리핑 및 저녁 6시 개발 현황 보고 요약 발송 |

---

## ⚡ 빠른 실행 가이드 (Quick Start)

### 1. 테스트 실행 모드 (Dry-run / Mock)
모든 모듈은 자체 테스트 파라미터(`--test`)를 지원하여 API Key 및 자격 증명 설정 없이 즉각적인 가상 실행 흐름을 검증할 수 있습니다. 

#### PowerShell에서 원클릭 테스트 실행:
```powershell
# 1. 회의록 분석 및 프로젝트 할 일 등록 테스트
node docs/51-features/meeting-management/meeting_manager.js --test

# 2. 명함 정보 추출 및 구글/사내 주소록 연동 테스트
node docs/51-features/contact-automation/contact_sync.js --test

# 3. 결제 알림 수신 및 세금계산서/청구서 발행 테스트
node docs/51-features/sales-invoicing/sales_tracker.js --test

# 4. 이메일 동기화 수집 및 통합 검색 테스트
node docs/51-features/file-email-integration/file_email_sync.js --test

# 5. 인사 DB 연동 및 이지원 연구원 재직증명서 발급 테스트
node docs/51-features/admin-automation/admin_cert_generator.js --test

# 6. AI 이메일 자동 분류/답장 & 계약 불발 심층 분석 테스트
node docs/51-features/ai-consultant/ai_consultant.js --test

# 7. 슬랙봇 연동 아침 브리핑 & 저녁 개발 보고서 발송 테스트
node docs/51-features/slackbot-briefing/slackbot_briefing.js --test
```

---

## ⚙️ 외부 API 연계 설정 요약

각 모듈이 실무에서 온전히 연동되어 작동하기 위해 필요한 설정 파일들을 소개합니다. 본 자격 증명 파일들은 프로젝트 루트의 `.agent/` 폴더에 생성 및 보관합니다.

1. **Gemini API Key 설정**:
   - 위치: `.agent/settings.json`
   - 목적: 녹취록 분석, 명함 OCR 분석, AI 이메일 답장 분류, 회의록 전략 수립을 위한 핵심 LLM 사용
   - 포맷:
     ```json
     {
       "api_key": "실제_Gemini_API_Key"
     }
     ```
2. **Google OAuth2 자격 증명**:
   - 위치: `.agent/google_oauth_token.json`
   - 목적: 구글 연락처 API(People API)를 통한 개인 휴대폰 및 사내 주소록 실시간 연동
3. **Google Drive 서비스 계정 자격 증명**:
   - 위치: `.agent/google_drive_key.json`
   - 목적: 구글 드라이브 API를 통한 문서 영구 백업 관리
4. **OpenClaw 슬랙 연동**:
   - 위치: `~/.openclaw/config.json` 또는 프로젝트 루트 `openclaw.json`
   - 목적: 슬랙 메신저 Socket Mode 연결을 통해 에이전트 소환 및 대화형 일정/할 일 추가 기능 구현 (가이드: [OpenClaw Slack 연동 가이드](../../docs/50-technical/openclaw-slack-integration.md))

---

## ⏰ 정기 스케줄러 등록 권장 사항 (Windows Task Scheduler)

슬랙 브리핑 및 메일 통합 등을 매일 또는 정기적으로 실행하려면 Windows의 작업 스케줄러(Task Scheduler)를 활용하십시오.

- **아침 9시 (일정 브리핑)**: 
  `node docs/51-features/slackbot-briefing/slackbot_briefing.js --morning`
- **저녁 6시 (개발 일일 요약 보고)**: 
  `node docs/51-features/slackbot-briefing/slackbot_briefing.js --evening`
- **매 시간 (업무 메일 동기화 및 분류)**: 
  `node docs/51-features/file-email-integration/file_email_sync.js --sync-emails`
