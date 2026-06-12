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
  audience?: string;
  tone?: string;
  notes?: string; // 必ず反映したい補足(任意)
  references?: string[]; // 参考画像のアセットURL(任意・配色/トーンの参考)
}

// ANTHROPIC_API_KEY が無い環境でもツールを一通り試せるデモ用ジェネレーター。
// 本番パイプライン(アウトライン→アートディレクション→ページ生成)の出力形式と互換。
export function generateMockDeck(brief: GenerateBrief): Deck {
  const t = brief.topic.trim() || "新規事業のご提案";
  const themeIndex = Math.abs(hash(t)) % THEME_PRESETS.length;
  const theme = THEME_PRESETS[themeIndex].theme;

  // セクション扉を先に作り、アジェンダから内部リンクを張る(リンク機能のデモ)
  const section1 = sectionSlide("01", "背景と課題");
  const section2 = sectionSlide("02", "提案内容");

  const all = [
    titleSlide(
      t,
      brief.audience ? `${brief.audience}向けのご提案資料` : "提案資料",
      new Date().toLocaleDateString("ja-JP", {
        year: "numeric",
        month: "long",
        day: "numeric",
      }),
    ),
    agendaSlide("本日お伝えしたいこと", [
      {
        head: "背景と課題",
        body: `${t}を取り巻く現状と、解決すべき本質的な課題を整理します。`,
        link: `#${section1.id}`,
      },
      {
        head: "提案内容",
        body: "課題に対するアプローチと提供価値をご説明します。",
        link: `#${section2.id}`,
      },
      {
        head: "実行計画",
        body: "スケジュール・体制・次のアクションをご提示します。",
      },
    ]),
    section1,
    statsSlide(
      "市場環境の変化",
      [
        { value: "3.2倍", label: "関連市場の5年成長率(デモ数値)" },
        { value: "67%", label: "課題を実感している担当者の割合" },
        { value: "12週", label: "従来手法での平均リードタイム" },
      ],
      "MARKET",
    ),
    twoColSlide(
      "現状とあるべき姿",
      {
        head: "現状 (As-Is)",
        body: "属人的なプロセスに依存しており、品質とスピードの両立が難しい。意思決定に必要な情報が分散している。",
      },
      {
        head: "あるべき姿 (To-Be)",
        body: `${t}を起点に業務を再設計し、データに基づく意思決定とスピーディな実行を両立する。`,
      },
      "AS-IS",
    ),
    section2,
    bulletsSlide(
      "提案する3つの柱",
      [
        { head: "現状診断", body: "ヒアリングとデータ分析で課題を定量化し、優先順位を確定します。" },
        { head: "パイロット導入", body: "小さく始めて2週間で効果を可視化。リスクを抑えながら検証します。" },
        { head: "全体展開", body: "検証結果をもとに全社展開のロードマップを策定・実行します。" },
      ],
      "APPROACH",
    ),
    quoteSlide("小さく検証し、速く学び、大きく展開する。", `${t} プロジェクトの基本方針`),
    statsSlide(
      "期待される効果",
      [
        { value: "−40%", label: "工数削減の見込み(デモ数値)" },
        { value: "+25%", label: "顧客満足度の改善目標" },
        { value: "6ヶ月", label: "投資回収までの想定期間" },
      ],
      "IMPACT",
    ),
    closingSlide("まずは小さく、始めましょう。", "ご質問・ご相談はお気軽にお寄せください。", "次回MTGを設定"),
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
