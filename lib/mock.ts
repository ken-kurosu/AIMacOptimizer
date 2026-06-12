import { Deck, uid } from "./types";
import { THEME_PRESETS } from "./theme";
import {
  agendaSlide,
  bulletsSlide,
  closingSlide,
  quoteSlide,
  sectionSlide,
  statsSlide,
  titleSlide,
  twoColSlide,
} from "./templates";

export interface GenerateBrief {
  topic: string;
  pages?: number; // 未指定なら構成提案時にAIが内容量から決める
  lang?: "ja" | "en"; // デモ生成の言語(既定: ja)
  audience?: string;
  tone?: string;
  notes?: string; // 必ず反映したい補足(任意)
  references?: string[]; // 参考画像のアセットURL(任意・配色/トーンの参考)
}

// ANTHROPIC_API_KEY が無い環境でもツールを一通り試せるデモ用ジェネレーター。
// 本番パイプライン(アウトライン→アートディレクション→ページ生成)の出力形式と互換。
export function generateMockDeck(brief: GenerateBrief): Deck {
  const en = brief.lang === "en";
  const t = brief.topic.trim() || (en ? "New Business Proposal" : "新規事業のご提案");
  const themeIndex = Math.abs(hash(t)) % THEME_PRESETS.length;
  const theme = THEME_PRESETS[themeIndex].theme;

  // セクション扉を先に作り、アジェンダから内部リンクを張る(リンク機能のデモ)
  const section1 = sectionSlide("01", en ? "Background & Problem" : "背景と課題");
  const section2 = sectionSlide("02", en ? "Our Proposal" : "提案内容");

  const all = [
    titleSlide(
      t,
      en
        ? brief.audience
          ? `A proposal for ${brief.audience}`
          : "Proposal"
        : brief.audience
          ? `${brief.audience}向けのご提案資料`
          : "提案資料",
      new Date().toLocaleDateString(en ? "en-US" : "ja-JP", {
        year: "numeric",
        month: "long",
        day: "numeric",
      }),
    ),
    agendaSlide(en ? "What we will cover" : "本日お伝えしたいこと", [
      {
        head: en ? "Background & Problem" : "背景と課題",
        body: en
          ? `The current landscape around ${t}, and the core problem worth solving.`
          : `${t}を取り巻く現状と、解決すべき本質的な課題を整理します。`,
        link: `#${section1.id}`,
      },
      {
        head: en ? "Our Proposal" : "提案内容",
        body: en
          ? "Our approach to the problem and the value we deliver."
          : "課題に対するアプローチと提供価値をご説明します。",
        link: `#${section2.id}`,
      },
      {
        head: en ? "Execution Plan" : "実行計画",
        body: en
          ? "Timeline, team structure and the next actions."
          : "スケジュール・体制・次のアクションをご提示します。",
      },
    ]),
    section1,
    statsSlide(
      en ? "A shifting market" : "市場環境の変化",
      en
        ? [
            { value: "3.2x", label: "5-year growth of the related market (demo figure)" },
            { value: "67%", label: "of practitioners report feeling this problem" },
            { value: "12wk", label: "average lead time with the legacy approach" },
          ]
        : [
            { value: "3.2倍", label: "関連市場の5年成長率(デモ数値)" },
            { value: "67%", label: "課題を実感している担当者の割合" },
            { value: "12週", label: "従来手法での平均リードタイム" },
          ],
      "MARKET",
    ),
    twoColSlide(
      en ? "As-is and to-be" : "現状とあるべき姿",
      en
        ? {
            head: "As-Is",
            body: "Processes depend on individuals; quality and speed trade off against each other, and the data needed for decisions is scattered.",
          }
        : {
            head: "現状 (As-Is)",
            body: "属人的なプロセスに依存しており、品質とスピードの両立が難しい。意思決定に必要な情報が分散している。",
          },
      en
        ? {
            head: "To-Be",
            body: `Redesign the workflow around ${t}: data-driven decisions and fast execution, at the same time.`,
          }
        : {
            head: "あるべき姿 (To-Be)",
            body: `${t}を起点に業務を再設計し、データに基づく意思決定とスピーディな実行を両立する。`,
          },
      "AS-IS",
    ),
    section2,
    bulletsSlide(
      en ? "Three pillars of the proposal" : "提案する3つの柱",
      en
        ? [
            { head: "Diagnose", body: "Interviews and data analysis quantify the problem and fix priorities." },
            { head: "Pilot", body: "Start small and make the impact visible within two weeks, keeping risk low." },
            { head: "Roll out", body: "Turn validated learnings into a company-wide rollout roadmap." },
          ]
        : [
            { head: "現状診断", body: "ヒアリングとデータ分析で課題を定量化し、優先順位を確定します。" },
            { head: "パイロット導入", body: "小さく始めて2週間で効果を可視化。リスクを抑えながら検証します。" },
            { head: "全体展開", body: "検証結果をもとに全社展開のロードマップを策定・実行します。" },
          ],
      "APPROACH",
    ),
    quoteSlide(
      en ? "Validate small, learn fast, scale big." : "小さく検証し、速く学び、大きく展開する。",
      en ? `Guiding principle of the ${t} project` : `${t} プロジェクトの基本方針`,
    ),
    statsSlide(
      en ? "Expected impact" : "期待される効果",
      en
        ? [
            { value: "−40%", label: "expected reduction in workload (demo figure)" },
            { value: "+25%", label: "target improvement in customer satisfaction" },
            { value: "6mo", label: "estimated payback period" },
          ]
        : [
            { value: "−40%", label: "工数削減の見込み(デモ数値)" },
            { value: "+25%", label: "顧客満足度の改善目標" },
            { value: "6ヶ月", label: "投資回収までの想定期間" },
          ],
      "IMPACT",
    ),
    closingSlide(
      en ? "Start small. Start now." : "まずは小さく、始めましょう。",
      en ? "Questions and ideas are always welcome." : "ご質問・ご相談はお気軽にお寄せください。",
      en ? "Book the next meeting" : "次回MTGを設定",
    ),
  ];

  const pages = Math.max(3, Math.min(brief.pages || 10, all.length));
  // タイトルとクロージングは必ず残し、中間を間引く
  const middle = all.slice(1, -1);
  const keep = pages - 2;
  const step = middle.length / keep;
  const slides = [
    all[0],
    ...Array.from({ length: keep }, (_, i) => middle[Math.floor(i * step)]),
    all[all.length - 1],
  ];

  // テンプレート由来のスライド名を英語化
  if (en) {
    for (const sl of slides) {
      sl.name = sl.name
        .replace(/^タイトル$/, "Title")
        .replace(/^クロージング$/, "Closing")
        .replace(/^メッセージ$/, "Message")
        .replace(/^セクション /, "Section ");
    }
  }

  // 外部リンクのデモ: クロージングのCTAピル
  const closing = slides[slides.length - 1];
  const cta = closing.elements.find((e) => e.type === "shape" && e.fill === "token:accent" && e.name === "CTAボタン");
  if (cta) cta.link = "https://example.com";

  return { id: uid(), title: t, theme, slides };
}

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}
