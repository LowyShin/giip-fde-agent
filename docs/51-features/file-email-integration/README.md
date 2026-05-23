# 파일 및 이메일 통합 모듈 (File & Email Integration) 📁📧

이 모듈은 구글 드라이브(Google Drive) API를 연동하여 보안 이슈와 스토리지 비용 없이 사내 문서를 원격 관리하며, 직원들의 업무용 이메일 계정(Gmail, IMAP/POP3)을 통합하여 한곳에서 검색하고 소통할 수 있게 합니다.

---

## 🛠️ 주요 기능

1. **구글 드라이브 문서 자동 백업**: 중요 사내 파일을 구글 드라이브 스토리지에 업로드하고 공유 ID를 발급합니다.
2. **사내 이메일 계정 통합**: 여러 직원의 이메일을 단일 검색 인덱스(`giipdb/emails.json`)에 동기화 수집합니다.
3. **통합 검색 및 관리**: 커맨드라인 또는 슬랙을 통해 사내 통합 메일 보관소를 일괄 검색할 수 있는 기능을 제공합니다.

---

## 🚀 사용법

### 1. 테스트 실행 (이메일 동기화, 검색 및 업로드 통합 테스트)
```powershell
node docs/51-features/file-email-integration/file_email_sync.js --test
```

### 2. 특정 검색어로 이메일 검색
```powershell
node docs/51-features/file-email-integration/file_email_sync.js --search "견적"
```

### 3. 수동 이메일 수신 동기화 실행
```powershell
node docs/51-features/file-email-integration/file_email_sync.js --sync-emails
```

### 4. 사내 문서를 구글 드라이브로 동기화 업로드
```powershell
node docs/51-features/file-email-integration/file_email_sync.js --upload <업로드_대상_파일_경로>
```

---

## ⚙️ Google Workspace API 연동 가이드

구글 드라이브와 이메일(Gmail API)을 통합하기 위해서는 OAuth2 서비스 계정(Service Account) 또는 OAuth 클라이언트 앱 설정이 필요합니다.

### A. Google Drive API
1. Google Cloud Console에서 **Google Drive API**를 활성화합니다.
2. 서비스 계정(Service Account)을 생성하여 JSON 키를 내려받고 `.agent/google_drive_key.json`으로 저장합니다.
3. Node.js `googleapis` 모듈을 활용하여 권한 및 드라이브 접근 코드를 활성화합니다:
   ```javascript
   const { google } = require('googleapis');
   const auth = new google.auth.GoogleAuth({
       keyFile: path.join(__dirname, '../../../.agent/google_drive_key.json'),
       scopes: ['https://www.googleapis.com/auth/drive.file']
   });
   const drive = google.drive({ version: 'v3', auth });
   ```

### B. Gmail/IMAP Email 통합
1. **Gmail API 활용 시**: OAuth2 인증을 거쳐 수신 메일을 조회합니다.
2. **IMAP 프로토콜 활용 시**: 회사 도메인 메일 서버(예: `imap.workmail.com`)의 IMAP 포트와 SSL 연동 설정을 진행합니다 (`node-imap` 또는 `mailparser` 패키지 활용).
3. 연동 시 `.agent/settings.json`에 메일 접속 자격 증명을 추가하여 정기 스케줄러가 백그라운드에서 동기화하도록 연동합니다.
