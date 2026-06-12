"use client";

import React, { useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";
import { uploadImageFile } from "@/lib/upload";
import { MessageKey, getLocale, useT } from "@/lib/i18n";

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

const SPACE_LABEL_KEYS: Record<string, MessageKey> = {
  left: "spaceLeft",
  right: "spaceRight",
  top: "spaceTop",
  bottom: "spaceBottom",
  center: "spaceCenter",
};

export function GenerateDialog({ onClose }: { onClose: () => void }) {
  const t = useT();
  const setDeck = useEditor((s) => s.setDeck);
  const [step, setStep] = useState<"input" | "review">("input");
  const [topic, setTopic] = useState("");
  const [pages, setPages] = useState(6);
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
      setError(e instanceof Error ? e.message : t("uploadFailed"));
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
          pages,
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
      if (!res.ok) throw new Error(data.error ?? `${t("planFailed")} (${res.status})`);
      setPlan(data.plan);
      setPlanModel(data.model ?? "");
      setSources(data.sources?.length ? data.sources : withFeedback ? sources : []);
      setResearchNotes(data.researchNotes ?? (withFeedback ? researchNotes : ""));
      setFeedback("");
      setStep("review");
    } catch (e) {
      setError(e instanceof Error ? e.message : t("planFailed"));
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
          pages,
          engine: "image2",
          lang: getLocale(),
          references: refs.length > 0 ? refs : undefined,
          plan: approvedPlan ?? undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `${t("generateFailed")} (${res.status})`);
      setDeck(normalizeDeck(data.deck));
      if (data.mode === "demo") {
        setNotice(data.warning ?? t("demoNotice"));
        setTimeout(onClose, 2500);
      } else {
        onClose();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : t("generateFailed"));
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
            <h2 className="mb-1 text-lg font-bold">{t("gdTitle")}</h2>
            <p className="mb-4 text-xs text-neutral-500">
              {t("gdIntro")}
            </p>

            <textarea
              autoFocus
              value={topic}
              onChange={(e) => setTopic(e.target.value)}
              rows={5}
              placeholder={t("gdPlaceholder")}
              className="mb-3 w-full rounded-xl border border-neutral-300 px-3 py-2.5 text-sm leading-relaxed"
            />

            <div className="mb-5 flex items-center justify-between">
              <div className="flex items-center gap-4">
              <label className="flex items-center gap-2 text-xs text-neutral-600">
                {t("pagesLabel")}
                <input
                  type="number"
                  min={3}
                  max={12}
                  value={pages}
                  onChange={(e) => setPages(parseInt(e.target.value) || 6)}
                  className="w-16 rounded-lg border border-neutral-300 px-2 py-1.5 text-sm"
                />
              </label>
              <label
                className="flex items-center gap-1.5 text-xs text-neutral-600"
                title={t("researchToggleTitle")}
              >
                <input
                  type="checkbox"
                  checked={research}
                  onChange={(e) => setResearch(e.target.checked)}
                />
                {t("researchToggle")}
              </label>
              </div>

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
                    title={t("refTitle")}
                    className="rounded-lg border border-dashed border-neutral-300 px-2.5 py-1.5 text-xs text-neutral-500 hover:border-neutral-400 hover:text-neutral-700 disabled:opacity-40"
                  >
                    {refUploading ? t("refUploading") : t("addRef")}
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
                {t("cancel")}
              </button>
              <button
                onClick={() => makePlan(false)}
                disabled={busy || !topic.trim()}
                className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
              >
                {planning ? (research && !researchNotes ? t("researching") : t("planning")) : loading ? t("generatingShort") : t("makePlan")}
              </button>
            </div>
          </>
        ) : (
          <>
            <h2 className="mb-0.5 text-lg font-bold">{plan?.title || t("planFallbackTitle")}</h2>
            <div className="mb-3 flex items-center gap-2 text-xs text-neutral-500">
              <span>{t("reviewCount", { n: plan?.pages?.length ?? 0 })}</span>
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
              {planModel && <span className="text-neutral-300">{t("planBy")} {planModel}</span>}
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
                      {p.space && SPACE_LABEL_KEYS[p.space] ? t(SPACE_LABEL_KEYS[p.space]) : ""}
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
                  {t("sourcesLabel")}
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
              placeholder={t("feedbackPlaceholder")}
              className="mb-3 w-full rounded-lg border border-neutral-300 px-3 py-2 text-xs"
            />

            {error && <p className="mb-3 text-xs text-red-500">{error}</p>}

            <div className="flex items-center justify-between">
              <button
                onClick={() => setStep("input")}
                disabled={busy}
                className="rounded-lg px-3 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
              >
                {t("backToInput")}
              </button>
              <div className="flex gap-2">
                <button
                  onClick={() => makePlan(true)}
                  disabled={busy}
                  className="rounded-lg border border-neutral-300 px-4 py-2 text-sm text-neutral-700 hover:bg-neutral-100 disabled:opacity-40"
                >
                  {planning ? t("remaking") : t("remake")}
                </button>
                <button
                  onClick={() => generate(plan)}
                  disabled={busy}
                  className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
                >
                  {loading ? t("generatingLong") : t("approveGenerate")}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
