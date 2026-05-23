# 매출 관리 및 청구서/세금계산서 자동 발행 모듈 (Sales Management & Invoicing) 💳

이 모듈은 웹사이트 결제 시스템(토스페이먼츠, 포트원 등)의 결제 완료 Webhook 및 은행 입금 푸시 알림 데이터를 획득하여 매출 DB에 자동 등록하고, 청구서 마크다운 문서 및 전자 세금계산서 발행을 처리합니다.

---

## 🛠️ 주요 기능

1. **결제 및 입금 자동 연동**: 수신된 결제 데이터를 가공해 사내 매출 기록(`giipdb/sales.json`)에 실시간 추가합니다.
2. **청구서/영수증 자동 생성**: 각 입금 건별로 공식 청구서(`output/invoice_{transaction_id}.md`)를 마크다운 파일로 생성합니다.
3. **전자 세금계산서 발행**: 세금계산서 대행사 API(팝빌, 바로빌 등)에 거래 처리를 연동하여 홈택스 발행을 완료합니다.

---

## 🚀 사용법

### 1. 테스트 실행 (가상 웹훅 데이터 처리)
```powershell
node docs/51-features/sales-invoicing/sales_tracker.js --test
```

### 2. 실제 결제 페이로드 분석 실행
JSON 형식의 결제 완료 상세 페이로드를 인자로 넘겨 호출합니다.
```powershell
node docs/51-features/sales-invoicing/sales_tracker.js '{"id":"TX_999","amount":150000,"sender":"홍길동","paymentMethod":"Card","status":"COMPLETED","date":"2026-05-23T10:00:00Z"}'
```

---

## ⚙️ 외부 연동 가이드

### A. 웹사이트 결제 (PG Webhook) 연동
토스페이먼츠(Toss Payments)를 연동하는 예시입니다:
1. 토스페이먼츠 상점 관리자에서 **웹훅 주소**를 사내 API 엔드포인트(`https://your-domain.com/webhook/toss`)로 등록합니다.
2. Express.js 기반 웹훅 핸들러에서 수신받은 페이로드를 `sales_tracker.js`로 전달합니다:
   ```javascript
   app.post('/webhook/toss', (req, res) => {
       const tossData = req.body;
       const normalized = {
           id: tossData.paymentKey,
           amount: tossData.totalAmount,
           sender: tossData.orderName,
           paymentMethod: tossData.method,
           status: tossData.status === 'DONE' ? 'COMPLETED' : 'PENDING',
           date: tossData.approvedAt
       };
       
       execSync(`node docs/51-features/sales-invoicing/sales_tracker.js '${JSON.stringify(normalized)}'`);
       res.status(200).send('OK');
   });
   ```

### B. 은행 입금 푸시 알림 (SMS/App Push) 연동
무통장 입금 알림을 자동화하려면:
1. 스마트폰의 입금 SMS 또는 뱅킹앱 푸시 알림을 수신해 주는 안드로이드 앱(예: SMS to Webhook, Tasker)을 설치합니다.
2. 입금자명, 은행명, 입금액 정규식 필터링을 설정해 사내 API 엔드포인트로 JSON 전송합니다.
3. 수신 시 `sales_tracker.js`를 통해 매출에 반영합니다.
