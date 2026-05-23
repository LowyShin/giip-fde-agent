# AI 전략 기획 및 컨설팅 모듈 (AI Strategy & Consulting) 🧠💼

이 모듈은 사내 데이터(이메일, 회의록 등)를 인공지능으로 심층 분석하여 비즈니스 효율을 극대화합니다. 수신된 고객 이메일을 분석해 정중한 답장 초안을 자동으로 생성하거나, 미팅 후 계약이 무산되었을 때 회의록을 분석하여 문제 원인과 다음 협상 전략을 제안하는 컨설턴트 역할을 수행합니다.

---

## 🛠️ 주요 기능

1. **이메일 자동 분류 및 답장 초안 작성**: 수신 메일 내용의 긴급성 및 유형(영업, 행정, 광고 스팸 등)을 분류하고, 담당 업무에 적절한 맞춤형 메일 답장 초안을 생성해 줍니다.
2. **계약 불발 원인 진단 (Post-Mortem)**: 회의 내용에서 가격 협상 실패, 보안 정책 충돌 등 불발의 실질적인 요인들을 요약하고, 차기 영업 전략(SaaS 분할 모델, 온프레미스 대안 구축 등)을 제안합니다.

---

## 🚀 사용법

### 1. 테스트 실행 (수신 메일 및 실패 분석 리포트 동시 테스트)
```powershell
node docs/51-features/ai-consultant/ai_consultant.js --test
```

### 2. 특정 이메일 ID 처리 및 답장 생성
```powershell
node docs/51-features/ai-consultant/ai_consultant.js --classify-email MSG_202605220001
```

### 3. 계약 불발 회의록 파일 분석 및 컨설팅 레포트 생성
```powershell
node docs/51-features/ai-consultant/ai_consultant.js --analyze-meeting <회의록_텍스트_파일_경로>
```

---

## ⚙️ 활용 및 고도화 팁

### A. 이메일 서버 수신 백그라운드 자동화
매 30분 단위로 메일 동기화(`file_email_sync.js --sync-emails`)가 수행된 직후, 새로 수신된 미답장 메일 목록에 대해 `ai_consultant.js --classify-email <ID>`를 연속적으로 백그라운드 실행하여 임시 보관함(Drafts)에 답장 초안을 미리 업로드해 둘 수 있습니다.

### B. CRM 세일즈 파이프라인 통합
영업 담당자가 CRM 시스템에서 해당 딜의 상태를 '실패(Lost)'로 변경하고 회의록을 업로드하면, 백그라운드에서 이 스크립트가 실행되어 `failed_deal_report.md`를 영업 매니저 및 임원진에게 메일이나 슬랙으로 발송해 줍니다.
