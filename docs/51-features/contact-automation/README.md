# 명함 및 연락처 자동화 모듈 (Business Card & Contact Automation) 📇

이 모듈은 스마트폰이나 카메라로 촬영한 명함 이미지를 분석하여 이름, 회사, 직책, 이메일, 전화번호, 사무실 주소를 자동으로 추출하고, 사내 주소록 데이터베이스 및 구글 연락처(Google Contacts)에 자동으로 동기화합니다.

---

## 🛠️ 주요 기능

1. **멀티모달 이미지 분석**: Gemini API의 이미지 인식 기능을 활용해 OCR 스캔 품질 이상의 정확도로 명함 항목을 정밀 추출합니다.
2. **사내 주소록 동기화**: 추출 결과를 사내 CRM용 로컬 데이터베이스(`docs/51-features/_data/contacts.json`)에 저장합니다. (중복 방지 로직 포함)
3. **구글 연락처 API 연동**: 사용자 모바일 휴대폰과 실시간 동기화되는 구글 연락처에 인물 정보를 원격 등록합니다.

---

## 🚀 사용법

### 1. 테스트 실행 (가상 명함 텍스트)
```powershell
node docs/51-features/contact-automation/contact_sync.js --test
```

### 2. 명함 이미지 파일 분석 실행
```powershell
node docs/51-features/contact-automation/contact_sync.js <명함_이미지_파일_경로.png/jpg>
```

---

## ⚙️ Google Contacts API 연동 연계 설정 가이드

구글 주소록에 자동 등록하기 위해서는 구글 개발자 콘솔에서 OAuth2 자격 증명을 획득해야 합니다.

1. **Google Cloud Console 설정**:
   - [Google Cloud Console](https://console.cloud.google.com/) 접속.
   - 프로젝트를 생성하고, **People API**를 활성화합니다.
   - `OAuth 동의 화면`을 설정한 후, `사용자 인증 정보 > OAuth 클라이언트 ID`를 만듭니다 (데스크톱 앱 유형).
2. **자격 증명 파일 저장**:
   - 다운로드한 클라이언트 비밀번호 JSON을 사용하여 Access/Refresh Token을 발급받습니다.
   - 발급한 토큰을 프로젝트의 `.agent/google_oauth_token.json` 파일로 아래 구조에 맞춰 저장합니다:
     ```json
     {
       "access_token": "YA29.A0AR...",
       "refresh_token": "1//04...",
       "client_id": "YOUR_CLIENT_ID.apps.googleusercontent.com",
       "client_secret": "YOUR_CLIENT_SECRET"
     }
     ```
3. **연동 검증**:
   - 토큰이 존재하면 `contact_sync.js`는 People API 엔드포인트(`https://people.googleapis.com/v1/people:createContact`)에 자동으로 API 요청을 송신합니다.
