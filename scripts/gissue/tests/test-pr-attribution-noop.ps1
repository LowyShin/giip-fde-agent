# test-pr-attribution-noop.ps1 — pr-attribution-lib.ps1 의 실질 no-op 판정 양방향 회귀 테스트
#                                 (giip #2459)
#
# 왜 필요한가: no-op 판정은 "고아 PR 을 자동으로 close 한다" 는 파괴적 동작의 유일한 안전장치다.
#   - 너무 관대하면(=진짜 코드 차이를 no-op 으로 보면) 남의 미반영 작업을 조용히 닫아버린다.
#   - 너무 엄격하면(=주석/공백 차이도 실질 변경으로 보면) 고아 PR 이 영원히 남아 이번 사고가 반복된다.
#   그래서 양방향(no-op 으로 봐야 하는 것 / 절대 no-op 으로 보면 안 되는 것)을 함께 고정한다.
#
# 네트워크/SK/gh 불필요 — 순수 함수 Test-DiffTextNoOp 에 합성 diff 를 직접 먹인다.
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-pr-attribution-noop.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

# pr-attribution-lib.ps1 은 gissue-audit-lib.ps1 을 dot-source 하지만 둘 다 최상위 실행부가 없어
# 그대로 dot-source 해도 부작용이 없다(gh/네트워크 호출은 함수 안에서만 일어난다).
. (Join-Path $PSScriptRoot '..\pr-attribution-lib.ps1')

$cases = @(
    @{
        Name   = 'A. 빈 diff(브랜치 내용이 base 에 완전히 반영됨) → no-op'
        Expect = $true
        Diff   = ''
    },
    @{
        Name   = 'B. .ps1 주석만 바뀜 → no-op'
        Expect = $true
        Diff   = @'
diff --git a/scripts/gissue/review-done-audit.ps1 b/scripts/gissue/review-done-audit.ps1
index 1111111..2222222 100644
--- a/scripts/gissue/review-done-audit.ps1
+++ b/scripts/gissue/review-done-audit.ps1
@@ -10,7 +10,7 @@
-# 사람 확인 신호 판정(구 주석)
+# 사람 확인 신호 판정(giip #2424 로 문구만 갱신)
 function Get-HumanConfirmSignal($comments) {
     return $null
 }
'@
    },
    @{
        Name   = 'C. .ps1 빈 줄만 추가됨 → no-op'
        Expect = $true
        Diff   = @'
diff --git a/scripts/gissue/pr-gate-sweep.ps1 b/scripts/gissue/pr-gate-sweep.ps1
--- a/scripts/gissue/pr-gate-sweep.ps1
+++ b/scripts/gissue/pr-gate-sweep.ps1
@@ -1,3 +1,5 @@
 $RevertMarker = '[PR-GATE-REVERT]'
+
+
 $RevertAuthor = 'gissue-pr-gate'
'@
    },
    @{
        Name   = 'D. .ps1 실제 코드 한 줄 변경 → no-op 아님(닫으면 안 됨)'
        Expect = $false
        Diff   = @'
diff --git a/scripts/gissue/review-done-audit.ps1 b/scripts/gissue/review-done-audit.ps1
--- a/scripts/gissue/review-done-audit.ps1
+++ b/scripts/gissue/review-done-audit.ps1
@@ -20,7 +20,7 @@
 function Get-HumanConfirmSignal($comments) {
-    continue
+    return $c
 }
'@
    },
    @{
        Name   = 'E. 주석 + 실제 코드가 섞임 → no-op 아님'
        Expect = $false
        Diff   = @'
diff --git a/scripts/gissue/review-done-audit.ps1 b/scripts/gissue/review-done-audit.ps1
--- a/scripts/gissue/review-done-audit.ps1
+++ b/scripts/gissue/review-done-audit.ps1
@@ -20,8 +20,9 @@
-# 옛 주석
+# 새 주석
+$MaxAttempts = 5
 function Get-HumanConfirmSignal($comments) {
 }
'@
    },
    @{
        Name   = 'F. .md 의 # 로 시작하는 줄은 주석이 아니라 제목 → no-op 아님(문서 PR 오폐기 방지)'
        Expect = $false
        Diff   = @'
diff --git a/scripts/gissue/SPEC.md b/scripts/gissue/SPEC.md
--- a/scripts/gissue/SPEC.md
+++ b/scripts/gissue/SPEC.md
@@ -1,2 +1,3 @@
 # SPEC
+## 11. 새 절 — 이 내용은 아직 main 에 없다
'@
    },
    @{
        Name   = 'G. .js 의 // 주석만 바뀜 → no-op'
        Expect = $true
        Diff   = @'
diff --git a/scripts/gissue/lib/post-comment.js b/scripts/gissue/lib/post-comment.js
--- a/scripts/gissue/lib/post-comment.js
+++ b/scripts/gissue/lib/post-comment.js
@@ -1,3 +1,3 @@
-// 등록 후 재조회해 비교한다(구 문구)
+// 등록 후 재조회해 비교한다(giip #1073)
 const x = 1;
'@
    },
    @{
        Name   = 'H. 신규 파일 추가 → no-op 아님'
        Expect = $false
        Diff   = @'
diff --git a/scripts/gissue/newthing.ps1 b/scripts/gissue/newthing.ps1
new file mode 100644
--- /dev/null
+++ b/scripts/gissue/newthing.ps1
@@ -0,0 +1,2 @@
+# 새 스크립트
+Write-Output "hello"
'@
    }
)

$fail = 0
foreach ($c in $cases) {
    $r = Test-DiffTextNoOp $c.Diff
    $ok = ($r.noop -eq $c.Expect)
    if (-not $ok) { $fail++ }
    $tag = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Output ("[{0}] {1}" -f $tag, $c.Name)
    Write-Output ("       기대 noop={0} / 실제 noop={1} / 실질변경줄 {2}건" -f $c.Expect, $r.noop, @($r.substantive).Count)
    foreach ($s in @($r.substantive)) { Write-Output "         · $s" }
}

Write-Output ""
if ($fail -eq 0) { Write-Output "전건 PASS ($($cases.Count)건)"; exit 0 }
Write-Output "FAIL $fail 건 / 전체 $($cases.Count)건"; exit 1
