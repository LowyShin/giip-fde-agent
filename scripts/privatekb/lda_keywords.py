#!/usr/bin/env python3
"""lda_keywords.py — CSN 단위 tPrivateKB 본문 LDA 키워드 추출 배치. giip #5347.

목적
----
한 CSN 의 tPrivateKB 본문 전체에 LDA(토픽 모델)를 돌려 문서별 상위 키워드를 뽑고,
`tPrivateKB.keywords` 에 저장할 수 있게 한다. Graphify 재빌드가 이 keywords 를
KEYWORD 노드로 연결한다.

선행 조건 (중요)
----------------
`keywords` 컬럼과 KbUpdate SP 의 keywords 인자는 **giipdb PR #614** 에서 추가된다.
그 SP 확장이 배포되기 전에는 `--apply` 가 동작하지 않는다(dry-run/CSV 는 무관).

동작
----
- 기본은 **dry-run**: DB 에 아무것도 쓰지 않고 변경 대조표 CSV(kbSn,title,keywords)만 쓴다.
- `--apply` 일 때만 문서마다 KbUpdate 로 keywords 를 쓴다.
- 전송·SK 로더는 privatekb.py 의 call / resolve_sk 를 import 해 그대로 쓴다.
  SK 는 env GIIP_SK 또는 giipAgent.cfg 에서 자동 발견하며 어떤 출력에도 남기지 않는다.

사용법
-----
    lda_keywords.py --csn <csn> [--topics 20] [--per-doc 5] [--limit 50]
                    [--out lda_keywords_<csn>.csv] [--apply]

의존성: scikit-learn  (pip install scikit-learn)
"""
import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import privatekb  # noqa: E402

MIN_CONTENT_CHARS = 50
RANDOM_STATE = 42

KO_STOP_WORDS = frozenset("""
그리고 그러나 그러면 그래서 하지만 또는 또한 따라서 즉 및 등 등의 위해 위한 통해 대한 대해
있다 있는 있음 없다 없는 없음 하다 한다 하는 하고 하며 해서 된다 되는 되어 됩니다 입니다
이다 이며 이고 것이다 것은 것을 수가 수는 때문 경우 대한 현재 이후 이전 아래 위의 다음 같은
이것 그것 저것 여기 거기 우리 사용 가능 필요 확인 관련 내용 해당 각각 모든 무엇 어떤 이런 그런
""".split())


def load_sklearn():
    try:
        from sklearn.decomposition import LatentDirichletAllocation
        from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS, CountVectorizer
    except ImportError:
        print("scikit-learn 이 필요합니다. 설치: pip install scikit-learn", file=sys.stderr)
        sys.exit(6)
    return CountVectorizer, LatentDirichletAllocation, ENGLISH_STOP_WORDS


_TOKEN_RE = re.compile(r"[0-9a-zㄱ-ㆎ가-힣]{2,}")


def tokenize(text, stop_words):
    """소문자화 → 영숫자·한글 토큰(길이 2+) → 불용어 제거."""
    return [t for t in _TOKEN_RE.findall((text or "").lower()) if t not in stop_words]


def doc_keywords(doc_topic, topic_words, per_doc):
    """문서-토픽 분포에서 가중이 큰 토픽 순으로 그 토픽의 상위 단어를 모아 중복 없이 per_doc 개.

    doc_topic: 토픽별 가중 리스트. topic_words: 토픽별 가중 내림차순 단어 리스트.
    """
    order = sorted(range(len(doc_topic)), key=lambda i: -doc_topic[i])
    out, seen = [], set()
    for t in order:
        for word in topic_words[t]:
            if word not in seen:
                seen.add(word)
                out.append(word)
                if len(out) >= per_doc:
                    return out
    return out


def fetch_docs(csn, limit, sk):
    """(kbSn, title, content, tags) 목록과 건너뛴 수를 돌려준다."""
    rows = privatekb.call("KbList", {"csn": csn}, sk)
    rows = [r for r in rows if isinstance(r, dict) and r.get("kbSn")]
    total = len(rows)
    if limit:
        rows = rows[:limit]
    docs, skipped = [], 0
    for i, r in enumerate(rows, 1):
        got = privatekb.call("KbGet", {"kbSn": r["kbSn"]}, sk)
        row = next((g for g in got if isinstance(g, dict)), {})
        content = row.get("content") or ""
        if len(content.strip()) < MIN_CONTENT_CHARS:
            skipped += 1
        else:
            docs.append((r["kbSn"], r.get("title") or "", content, row.get("tags") or ""))
        if i % 20 == 0 or i == len(rows):
            print("수집 %d/%d" % (i, len(rows)), flush=True)
    return docs, skipped, total


def main():
    p = argparse.ArgumentParser(
        description="CSN 의 tPrivateKB 본문에 LDA 를 돌려 문서별 키워드를 뽑는다. "
                    "기본 dry-run(CSV 만 기록). --apply 는 giipdb PR #614 의 KbUpdate keywords "
                    "확장이 배포된 뒤에만 동작한다.")
    p.add_argument("--csn", type=int, required=True)
    p.add_argument("--topics", type=int, default=20, help="LDA 토픽 수 (기본 20)")
    p.add_argument("--per-doc", type=int, default=5, help="문서별 키워드 수 (기본 5)")
    p.add_argument("--limit", type=int, help="앞 N건만 (파일럿용)")
    p.add_argument("--out", help="CSV 경로 (기본 lda_keywords_<csn>.csv)")
    p.add_argument("--apply", action="store_true",
                   help="KbUpdate 로 keywords 를 실제 기록 (giipdb PR #614 배포 후에만 동작)")
    a = p.parse_args()
    out_path = a.out or "lda_keywords_%d.csv" % a.csn

    CountVectorizer, LDA, EN_STOP = load_sklearn()
    stop = set(EN_STOP) | KO_STOP_WORDS

    sk = privatekb.resolve_sk()
    docs, skipped, total = fetch_docs(a.csn, a.limit, sk)
    print("대상 %d건 (전체 %d건), 건너뜀(본문 없음/짧음) %d건" % (len(docs) + skipped, total, skipped))
    if not docs:
        print("분석할 문서가 없습니다.")
        return

    vec = CountVectorizer(tokenizer=lambda t: tokenize(t, stop), lowercase=False,
                          token_pattern=None, min_df=1)
    try:
        X = vec.fit_transform(d[2] for d in docs)
    except ValueError as e:
        print("어휘가 비었습니다: %s" % e, file=sys.stderr)
        sys.exit(7)
    topics = max(1, min(a.topics, len(docs)))
    lda = LDA(n_components=topics, random_state=RANDOM_STATE, learning_method="batch")
    dt = lda.fit_transform(X)
    vocab = vec.get_feature_names_out()
    topic_words = [[vocab[j] for j in comp.argsort()[::-1][:max(a.per_doc, 10)]]
                   for comp in lda.components_]

    results = [(d, doc_keywords(list(dt[i]), topic_words, a.per_doc)) for i, d in enumerate(docs)]

    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kbSn", "title", "keywords"])
        for d, kws in results:
            w.writerow([d[0], d[1], ",".join(kws)])
    print("CSV 기록: %s" % out_path)

    tagged = sum(1 for _, k in results if k)
    applied = 0
    if a.apply:
        for d, kws in results:
            if not kws:
                continue
            privatekb.call("KbUpdate", {"kbSn": d[0], "title": d[1], "content": d[2],
                                        "tags": d[3], "keywords": ",".join(kws)}, sk)
            applied += 1
            if applied % 20 == 0:
                print("기록 %d/%d" % (applied, tagged), flush=True)
    print("요약: 대상 %d, 건너뜀 %d, 키워드 부착 %d, DB 기록 %d (%s)"
          % (len(docs) + skipped, skipped, tagged, applied, "apply" if a.apply else "dry-run"))


if __name__ == "__main__":
    main()
