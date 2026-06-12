"use client";

import React, { useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";
import { uploadImageFile } from "@/lib/upload";

// 生成ダイアログ(2ステップ)。
//  1. 入力: 「内容(自由記述)・ページ数・参考画像(任意)」の3つだけ
//  2. レビュー: gpt-5系が立てた構成案(配色・ページ毎の内容とデザイン)を確認し、
//     OKなら生成へ。修正指示を書いて作り直しもできる
// APIキーが無い環境はレビューを挟まずデモ生成に直行する。

interface PlanText {
  role?: string;
  text?: string;
}
interface PlanPage {
  name?: string;
  motif?: string;
  space?: string;
  texts?: PlanText[];
}
interface DeckPlan {
  title?: string;
  theme?: { colors?: Record<string, string>; headingFont?: string; bodyFont?: string };
  pages?: PlanPage[];
}

const SPACE_LABELS: Record<string, string> = {
  left: "テキストは左",
  right: "テキストは右",
  top: "テキストは上",
  bottom: "テキストは下",
  center: "テキストは中央",
};

export function GenerateDialog({ onClose }: { onClose: () => void }) {
  const setDeck = useEditor((s) => s.setDeck);
  const [step, setStep] = useState<"input" | "review">("input");
  const [topic, setTopic] = useState("");
  const [refs, setRefs] = useState<string[]>([]);
  const [refUploading, setRefUploading] = useState(false);
  const refInput = useRef<HTMLInputElement>(null);
  const [plan, setPlan] = useState<DeckPlan | null>(null);
  const [research, setResearch] = useState(false);
  const [sources, setSources] = useState<{ url: string; title?: string }[]>([]);
  const [researchNotes, setResearchNotes] = useState("");
  const [planModel, setPlanModel] = useState("");
  const [feedback, setFeedback] = useState("");
  const [planning, setPlanning] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const addRefs = async (files: FileList) => {
    const images = Array.from(files)
      .filter((f) => f.type.startsWith("image/"))
      .slice(0, 3 - refs.length);
    if (images.length === 0) return;
    setRefUploading(true);
    try {
      const urls: string[] = [];
      for (const f of images) urls.push((await uploadImageFile(f)).url);
      setRefs((prev) => [...prev, ...urls].slice(0, 3));
    } catch (e) {
      setError(e instanceof Error ? e.message : "画像のアップロードに失敗しました");
    } finally {
      setRefUploading(false);
    }
  };

  // 構成案を作る(修正指示があれば前回案と一緒に渡して作り直す)
  const makePlan = async (withFeedback = false) => {
    setPlanning(true);
    setError(null);
    try {
      const res = await fetch("/api/generate/plan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topic,
          references: refs.length > 0 ? refs : undefined,
          research: research || undefined,
          researchNotes: withFeedback ? researchNotes || undefined : undefined,
          feedback: withFeedback ? feedback.trim() || undefined : undefined,
          previousPlan: withFeedback ? plan : undefined,
        }),
      });
      const data = await res.json();
      if (res.status === 400 && !withFeedback) {
        // キー未設定など → レビューなしでデモ生成に直行
        await generate(null);
        return;
      }
      if (!res.ok) throw new Error(data.error ?? `構成案の作成に失敗しました (${res.status})`);
      setPlan(data.plan);
      setPlanModel(data.model ?? "");
      setSources(data.sources?.length ? data.sources : withFeedback ? sources : []);
      setResearchNotes(data.researchNotes ?? (withFeedback ? researchNotes : ""));
      setFeedback("");
      setStep("review");
    } catch (e) {
      setError(e instanceof Error ? e.message : "構成案の作成に失敗しました");
    } finally {
      setPlanning(false);
    }
  };

  // 承認された構成案(またはデモ)で生成する
  const generate = async (approvedPlan: DeckPlan | null) => {
    setLoading(true);
    setError(null);
    setNotice(null);
    try {
      const res = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topic,
          engine: "image2",
          references: refs.length > 0 ? refs : undefined,
          plan: approvedPlan ?? undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `生成に失敗しました (${res.status})`);
      setDeck(normalizeDeck(data.deck));
      if (data.mode === "demo") {
        setNotice(data.warning ?? "APIキーが未設定のため、デモ生成で作成しました。");
        setTimeout(onClose, 2500);
      } else {
        onClose();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "生成に失敗しました");
    } finally {
      setLoading(false);
    }
  };

  const busy = planning || loading;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={busy ? undefined : onClose}
    >
      <div
        className="w-[560px] rounded-2xl bg-white p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {step === "input" ? (
          <>
            <h2 className="mb-1 text-lg font-bold">新しい資料を作る</h2>
            <p className="mb-4 text-xs text-neutral-500">
              内容を書くと、まず構成案が出ます。確認してOKなら生成に進みます。
            </p>

            <textarea
              autoFocus
              value={topic}
              onChange={(e) => setTopic(e.target.value)}
              rows={5}
              placeholder={
                "どんな資料を作りたいか、自由に書いてください。\n" +
                "誰向けか・トーン・枚数の希望・必ず入れたい数字があれば一緒に。\n\n" +
                "例: 自家焙煎コーヒー定期便の紹介資料。在宅ワーカー向けに上品なトーンで。月額980円(税込)は必ず載せる"
              }
              className="mb-3 w-full rounded-xl border border-neutral-300 px-3 py-2.5 text-sm leading-relaxed"
            />

            <div className="mb-5 flex items-center justify-between">
              <label
                className="flex items-center gap-1.5 text-xs text-neutral-600"
                title="構成案を作る前にWebで事実(料金・実績・正式名称など)を調べて反映します(+30秒〜1分)"
              >
                <input
                  type="checkbox"
                  checked={research}
                  onChange={(e) => setResearch(e.target.checked)}
                />
                Web検索で最新情報を反映
              </label>

              <div className="flex items-center gap-2">
                {refs.map((url) => (
                  <div key={url} className="relative">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={url}
                      alt=""
                      className="h-9 w-12 rounded border border-neutral-200 object-cover"
                    />
                    <button
                      onClick={() => setRefs((prev) => prev.filter((x) => x !== url))}
                      className="absolute -right-1.5 -top-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-neutral-800 text-[9px] text-white"
                      title="削除"
                    >
                      ✕
                    </button>
                  </div>
                ))}
                {refs.length < 3 && (
                  <button
                    onClick={() => refInput.current?.click()}
                    disabled={refUploading}
                    title="ブランド資料やトンマナの近い画像を渡すと、配色・雰囲気の参考にします"
                    className="rounded-lg border border-dashed border-neutral-300 px-2.5 py-1.5 text-xs text-neutral-500 hover:border-neutral-400 hover:text-neutral-700 disabled:opacity-40"
                  >
                    {refUploading ? "追加中…" : "+ 参考画像"}
                  </button>
                )}
                <input
                  ref={refInput}
                  type="file"
                  accept="image/*"
                  multiple
                  className="hidden"
                  onChange={(e) => {
                    if (e.target.files) addRefs(e.target.files);
                    e.target.value = "";
                  }}
                />
              </div>
            </div>

            {error && <p className="mb-3 text-xs text-red-500">{error}</p>}
            {notice && <p className="mb-3 text-xs text-amber-600">{notice}</p>}

            <div className="flex justify-end gap-2">
              <button
                onClick={onClose}
                disabled={busy}
                className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
              >
                キャンセル
              </button>
              <button
                onClick={() => makePlan(false)}
                disabled={busy || !topic.trim()}
                className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
              >
                {planning ? (research && !researchNotes ? "Webで調べています…(1〜2分)" : "構成を考えています…(30秒〜1分)") : loading ? "生成中…" : "構成案を見る"}
              </button>
            </div>
          </>
        ) : (
          <>
            <h2 className="mb-0.5 text-lg font-bold">{plan?.title || "構成案"}</h2>
            <div className="mb-3 flex items-center gap-2 text-xs text-neutral-500">
              <span>この内容で{plan?.pages?.length ?? 0}ページ生成します</span>
              {plan?.theme?.colors && (
                <span className="flex items-center gap-1">
                  {["brand", "accent", "bg", "ink"].map((k) => (
                    <span
                      key={k}
                      className="inline-block h-3.5 w-3.5 rounded-full border border-neutral-200"
                      style={{ background: plan.theme!.colors![k] }}
                    />
                  ))}
                </span>
              )}
              {planModel && <span className="text-neutral-300">構成: {planModel}</span>}
            </div>

            <div className="mb-3 max-h-[340px] space-y-2 overflow-y-auto pr-1">
              {(plan?.pages ?? []).map((p, i) => (
                <div key={i} className="rounded-xl border border-neutral-200 px-3 py-2.5">
                  <div className="mb-1 flex items-baseline gap-2">
                    <span className="shrink-0 text-[11px] font-bold text-neutral-400">{i + 1}</span>
                    <span className="shrink-0 text-sm font-bold">{p.name || `ページ ${i + 1}`}</span>
                    <span
                      className="ml-auto min-w-0 truncate text-[10px] text-neutral-400"
                      title={p.motif}
                    >
                      {SPACE_LABELS[p.space ?? ""] ?? ""}
                      {p.motif ? `・${p.motif}` : ""}
                    </span>
                  </div>
                  <ul className="space-y-0.5 text-xs leading-relaxed text-neutral-600">
                    {(p.texts ?? []).map((t, j) => (
                      <li key={j} className="truncate">
                        {t.text}
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>

            {sources.length > 0 && (
              <div className="mb-3">
                <div className="mb-1 text-[10px] font-bold tracking-wider text-neutral-400">
                  参照した情報源
                </div>
                <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                  {sources.slice(0, 6).map((s) => (
                    <a
                      key={s.url}
                      href={s.url}
                      target="_blank"
                      rel="noreferrer"
                      className="max-w-[230px] truncate text-[10px] text-blue-500 hover:underline"
                      title={s.url}
                    >
                      {s.title || s.url.replace(/^https?:\/\//, "")}
                    </a>
                  ))}
                </div>
              </div>
            )}

            <input
              type="text"
              value={feedback}
              onChange={(e) => setFeedback(e.target.value)}
              placeholder="修正したい点があれば書いて「作り直す」(例: 5ページに収めて / 3ページ目は事例に)"
              className="mb-3 w-full rounded-lg border border-neutral-300 px-3 py-2 text-xs"
            />

            {error && <p className="mb-3 text-xs text-red-500">{error}</p>}

            <div className="flex items-center justify-between">
              <button
                onClick={() => setStep("input")}
                disabled={busy}
                className="rounded-lg px-3 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
              >
                ← 入力に戻る
              </button>
              <div className="flex gap-2">
                <button
                  onClick={() => makePlan(true)}
                  disabled={busy}
                  className="rounded-lg border border-neutral-300 px-4 py-2 text-sm text-neutral-700 hover:bg-neutral-100 disabled:opacity-40"
                >
                  {planning ? "作り直し中…" : "作り直す"}
                </button>
                <button
                  onClick={() => generate(plan)}
                  disabled={busy}
                  className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
                >
                  {loading ? "生成中…(1ページ約1分)" : "この構成で生成する"}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
