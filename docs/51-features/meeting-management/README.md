# 미팅 및 프로젝트 자동 관리 모듈 (Meeting & Project Auto-management) 📅

이 모듈은 회의 음성 녹음 장치(Plaud, 모바일 녹음 앱 등)로부터 생성된 텍스트 녹취록을 자동으로 파싱하여, 계약 견적서 초안을 발행하고 프로젝트 할 일(Todo) 목록을 생성해 시스템 데이터베이스에 등록합니다.

---

## 🛠️ 주요 기능

1. **녹취록 의미 분석**: 회의 참석자 간의 대화 내용 중 계약 금액, 기간, 담당 업무, 개발 사양 등을 파악합니다.
2. **견적서(Estimate) 자동 생성**: 마크다운 형식의 상세 견적서를 생성해 `output/` 폴더에 파일로 보관합니다.
3. **할 일 자동 등록**: 도출된 업무와 담당자, 일정을 사내 태스크 관리 시스템(`giipdb/schedule.json`)에 자동 추가합니다.

---

## 🚀 사용법

### 1. 테스트 실행
자체 내장된 가상 회의록 데이터를 활용해 정상 작동 여부를 빠르게 검증합니다.
```powershell
node docs/51-features/meeting-management/meeting_manager.js --test
```

### 2. 실제 회의록 분석 실행
텍스트 파일 형태의 회의 녹취록을 인자로 전달하여 분석을 수행합니다.
```powershell
node docs/51-features/meeting-management/meeting_manager.js <녹취록_텍스트_파일_경로>
```

---

## ⚙️ 외부 연동 가이드 (Zapier / Webhook)

본 스크립트를 클라우드 환경(예: AWS Lambda, Vercel Serverless Function, Express 서버)에 엔드포인트로 연동해 자동화 파이프라인을 구축할 수 있습니다.

```
[Plaud AI 녹음] ➔ [녹음 완료 및 자동 이메일/앱 전송] ➔ [Zapier Webhook Catch] ➔ [사내 서버 API 호출] ➔ [meeting_manager.js 백그라운드 호출]
```

1. **Zapier 설정**:
   - Trigger: Plaud AI 또는 스마트폰 녹음 파일이 Dropbox/Google Drive에 새로 생성됨
   - Action: **Webhooks by Zapier (POST)** 선택
   - URL: `https://your-internal-domain.net/api/webhook/meeting`
   - Payload: 파일 내용(텍스트)을 `transcript` 필드로 전달.
2. **API 수신부(Express.js 예시)**:
   ```javascript
   app.post('/api/webhook/meeting', async (req, res) => {
       const transcript = req.body.transcript;
       fs.writeFileSync('temp_meeting.txt', transcript, 'utf8');
       
       // meeting_manager.js 실행
       execSync('node docs/51-features/meeting-management/meeting_manager.js temp_meeting.txt');
       
       res.status(200).send({ success: true });
   });
   ```
