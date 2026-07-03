# giip FDE Agent — エコシステム & 高度な機能 (Advanced Capabilities)

> この文書は [README](../readme_jp.md) から分離した詳細説明です。
> READMEには要約のみを置き、各機能の詳しい仕組み・コマンド・リンクはここで管理します。

giip FDE Agentは、単なるプロンプトの集まりではなく、実証済みの複数フレームワークの精髄を一つのエージェントに統合したものです。以下は、エージェントに内蔵された中核機能です。

---

## 1. Bkit Vibecoding Kit (PDCA)
- **Plan-Design-Do-Check-Act**: 実装前に設計 (Design) と分析 (Analyze) の段階を経ることで、「作りながら考える」ミスを防ぎます。
- **`/pdca` コマンド**: 体系的なレポーティングとギャップ分析を自動化します。

## 2. Superpowers Engineering
- **Subagent-Driven**: 一つのタスクを `設計` → `実装` → `検証` のパイプラインに分断。
- **Strong Skills**: TDD (Test Driven Development)、Systematic Debugging、Brainstormingスキルが内蔵されています。

## 3. Gstack (Safety & Security)
- **Founder Mode**: `/office-hours` や `/ceo-review` を通じて、製品の本質とUXを再定義します。
- **Guardrails**: 破壊的なコマンドの前の警告 (`/careful`) や作業範囲の制限 (`/freeze`) により、安全な開発環境を提供します。
- **Security Audit**: `/cso` コマンドで STRIDE/OWASP ベースのセキュリティ検査を実行します。

## 4. Native Optimization & Tracing
- **`/native-trace`**: AIの推論過程とツール呼び出し履歴のすべてを自動で記録します。
- **`/aioptimize`**: 収集されたデータを基に、エージェントが自らプロンプトを修正し、より賢くなります。

## 5. K-Layer Knowledge System (Karpathy Diagram)
- **Source-linked Knowledge**: エージェントの作業履歴から再利用可能なパターンと教訓を `Claim` 単位で自動抽出し、蓄積します。
- **自己強化ループ**: すべての知識は元の証拠（Trace/Source）と紐付けられており、次の作業時にエージェントがこれを参照することで、より賢く行動します。
- [K-Layerの仕組み](../.agent/skills/k-layer/SKILL.md) | [ナレッジベース](../.agent/knowledge/README.md)

## 5-1. Andrej Karpathy 行動ガイドライン
- **Think Before Coding**: 実装前に仮定を明示し、不確かな場合は質問し、複数の解釈がある場合は提示します。
- **Simplicity First**: 問題を解決する最小限のコードのみを書きます。未要求の機能・抽象化・柔軟性は追加しません。
- **Surgical Changes**: 必要なものだけを修正します。無関係なコード・コメント・フォーマットには触れません。
- **Goal-Driven Execution**: 検証可能な成功基準を最初に定義し、達成されるまで反復します。
- [Karpathy ガイドライン](../.agent/rules/10_karpathy_guidelines.md) | [原典リポジトリ](https://github.com/forrestchang/andrej-karpathy-skills)

## 6. マルチソース・デザイン探索 (design-md)
- **統合デザイン探索**: `designmd.ai`、`designmd.app`、`getdesign.md`、`designmd.me` の4つの主要プラットフォームを統合し、最適なデザインシステムを発掘します。
- **ブランドの複製と自動生成**: StripeやVercelなどの有名ブランドのスタイルを即座に移植したり、特定のURLからデザイン・マークダウンを自動生成したりできます。
- [デザイン探索および統合ガイド](DESIGN_DISCOVERY_GUIDE.md)

## 7. メッセンジャー制御 (OpenClaw)
- **メッセンジャーベースの遠隔制御**: Slack、Discord、Telegramを通じて、いつでもどこでもレポジトリの情報を照会し、作業を指示できます。
- **ポケットの中のエージェント**: モバイルデバイスからプロジェクトのナレッジベース (K-Layer) にアクセスし、リアルタイムでの質疑応答が可能です。
- [OpenClaw メッセンジャー連動ガイド](50-technical/openclaw-slack-integration_ja.md)

## 8. 投資/トレーディング統合 (Vibe Investing)
- **安全な機能移植**: 外部の投資レポジトリを5軸（活性度・成熟度・学習曲線・市場適合性・ライセンス）で評価し、GIIP の role/rule/skill/workflow へ最小変更で統合します。
- **リスク優先チェックリスト**: バックテストのバイアス、実行現実性（スリッページ/流動性/手数料）、規制/コストのガードレールを標準で適用します。
- [投資スキル](../.agent/skills/vibe-investing/SKILL.md) | [投資ワークフロー](../.agent/workflows/investment-evaluation.md)

## 9. AI Agency 専門家チーム統合 (Agency-Agents)
- **高度なロールシステム**: `Workflow Architect` (システムパス設計)、`Korean Business Navigator` (韓国ビジネス特化) など、検証済みの専門家ペルソナを内蔵。
- **プレミアム UI/UX**: `premium-ui-craft` スキルを通じて、単なる機能を超えた高度な美的な完成度 (Glassmorphism、60fpsアニメーションなど) を追求。
- **徹底した例外パス設計**: `workflow-mapping` を通じて「コードはあるが仕様がないワークフロー」を防止し、すべての失敗回復パスを事前に定義。

## 10. Codexパフォーマンス維持 (keep-codex-fast)
- **Codex速度低下防止**: 古いチャット・ワークツリー・ログ・プロジェクト参照が蓄積してCodexが重くなったとき、ローカル状態を安全に点検・整理します。
- **ハンドオフ優先原則**: アーカイブ前に必ずハンドオフ文書を作成し、作業コンテキストを保存します。
- **定期メンテナンス**: 週次/隔週の自動点検リマインダー — 適用はユーザー承認後に手動で行います。
- [keep-codex-fastスキル](../.agent/skills/keep-codex-fast/SKILL.md) | [メンテナンスワークフロー](../.agent/workflows/codex-maintenance.md) | [Codexツールガイド](04-tools/codex.md)

---

## 📂 システムアーキテクチャ (System Architecture)
FDE Agent を構成する4つの主要要素に関する詳細ガイドです。

- [**構成要素の概要**](02-design/agent-components/overview.md)
- [**ロール (Roles)**](02-design/agent-components/role.md): エージェントのペルソナと責任の定義
- [**ルール (Rules)**](02-design/agent-components/rule.md): 強制指針および品質管理の原則
- [**スキル (Skills)**](02-design/agent-components/skill.md): ツール使用法および専門知識パッケージ
- [**ワークフロー (Workflows)**](02-design/agent-components/workflow.md): 複雑な作業手順とカスタムコマンドの作成

---

## 🧭 AI-Native 運用スターターパック
- [90分オンボーディング経路](00-onboarding/README.md) (Beginner / Team Lead / Ops)
- [運用KPI標準](60-operations/ai-native-kpi.md) + [週次KPIテンプレート](../.agent/templates/weekly-kpi-report.template.md)
- [承認ゲートワークフロー](../.agent/workflows/human-approval-gate.md)
- [Incident + Rollback プレイブック](60-operations/incident-rollback-playbook.md)
- [Skill/Role 運用責任メタデータスキーマ](../.agent/templates/shared/operational-metadata-schema.md)
