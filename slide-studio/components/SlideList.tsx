"use client";

import React, { useState } from "react";
import { useEditor } from "@/lib/store";
import { Slide } from "@/lib/types";
import { ScaledSlide } from "./SlideRenderer";

export function SlideList() {
  const deck = useEditor((s) => s.deck);
  const selectedSlideId = useEditor((s) => s.selectedSlideId);
  const select = useEditor((s) => s.select);
  const addSlide = useEditor((s) => s.addSlide);
  const replaceSlide = useEditor((s) => s.replaceSlide);
  const duplicateSlide = useEditor((s) => s.duplicateSlide);
  const deleteSlide = useEditor((s) => s.deleteSlide);
  const moveSlide = useEditor((s) => s.moveSlide);
  const [regenId, setRegenId] = useState<string | null>(null);
  const [regenError, setRegenError] = useState<string | null>(null);
  const [aiAddOpen, setAiAddOpen] = useState(false);

  // このページだけimage2エンジンで再デザイン(テキストとテーマは維持)
  const regenerate = async (slide: Slide) => {
    if (regenId) return;
    setRegenId(slide.id);
    setRegenError(null);
    try {
      const texts = slide.elements
        .filter((e) => e.type === "text")
        .map((e) => ({
          role: e.name ?? (e.fontSize >= 40 ? "title" : e.fontSize <= 16 ? "kicker" : "body"),
          text: e.text,
        }));
      const res = await fetch("/api/generate/slide", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topic: deck.title,
          theme: deck.theme,
          page: { name: slide.name, texts },
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `再生成に失敗しました (${res.status})`);
      replaceSlide(slide.id, data.slide as Slide);
    } catch (e) {
      setRegenError(e instanceof Error ? e.message : "再生成に失敗しました");
    } finally {
      setRegenId(null);
    }
  };

  return (
    <div className="flex h-full w-56 shrink-0 flex-col border-r border-neutral-200 bg-white">
      <div className="flex items-center justify-between border-b border-neutral-200 px-3 py-2">
        <span className="text-xs font-bold text-neutral-500">ページ</span>
        <div className="flex gap-1">
          <button
            onClick={() => setAiAddOpen(true)}
            title="内容を書くと、デッキのテーマに合わせてAIがページを1枚生成します"
            className="rounded bg-blue-600 px-2 py-1 text-xs font-medium text-white hover:bg-blue-500"
          >
            ✦ AI
          </button>
          <button
            onClick={() => addSlide(undefined, selectedSlideId)}
            className="rounded bg-neutral-900 px-2 py-1 text-xs font-medium text-white hover:bg-neutral-700"
          >
            + 追加
          </button>
        </div>
      </div>
      {aiAddOpen && (
        <AiAddDialog
          topic={deck.title}
          theme={deck.theme}
          onClose={() => setAiAddOpen(false)}
          onCreated={(slide) => {
            addSlide(slide, selectedSlideId);
            setAiAddOpen(false);
          }}
        />
      )}
      {regenError && (
        <div className="border-b border-red-100 bg-red-50 px-3 py-2 text-[11px] text-red-600">
          {regenError}
        </div>
      )}
      <div className="flex-1 space-y-3 overflow-y-auto p-3">
        {deck.slides.map((slide, i) => (
          <div key={slide.id} className="group">
            <div
              onClick={() => select(slide.id)}
              className={`relative cursor-pointer overflow-hidden rounded-lg border-2 transition ${
                slide.id === selectedSlideId
                  ? "border-blue-500 shadow-md"
                  : "border-neutral-200 hover:border-neutral-400"
              }`}
            >
              <ScaledSlide slide={slide} theme={deck.theme} width={192} />
              {regenId === slide.id && (
                <div className="absolute inset-0 flex items-center justify-center bg-white/70 text-[11px] font-medium text-neutral-600">
                  <span className="animate-pulse">再デザイン中…</span>
                </div>
              )}
            </div>
            <div className="mt-1 flex items-center justify-between px-0.5">
              <span className="max-w-[100px] truncate text-[11px] text-neutral-500">
                {i + 1}. {slide.name}
              </span>
              <div className="flex gap-0.5 opacity-0 transition group-hover:opacity-100">
                <MiniBtn title="上へ" onClick={() => moveSlide(slide.id, -1)}>↑</MiniBtn>
                <MiniBtn title="下へ" onClick={() => moveSlide(slide.id, 1)}>↓</MiniBtn>
                <MiniBtn
                  title="このページをAIで再デザイン(テキストは維持)"
                  onClick={() => regenerate(slide)}
                >
                  ✦
                </MiniBtn>
                <MiniBtn title="複製" onClick={() => duplicateSlide(slide.id)}>⧉</MiniBtn>
                <MiniBtn title="削除" onClick={() => deleteSlide(slide.id)}>✕</MiniBtn>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// AIページ追加: 内容の説明だけ受け取り、テーマに合わせた1ページを生成して挿入する
function AiAddDialog({
  topic,
  theme,
  onClose,
  onCreated,
}: {
  topic: string;
  theme: unknown;
  onClose: () => void;
  onCreated: (slide: Slide) => void;
}) {
  const [description, setDescription] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/generate/slide", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ topic, theme, page: { description } }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `生成に失敗しました (${res.status})`);
      onCreated(data.slide as Slide);
    } catch (e) {
      setError(e instanceof Error ? e.message : "生成に失敗しました");
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={loading ? undefined : onClose}
    >
      <div
        className="w-[420px] rounded-2xl bg-white p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 className="mb-1 text-base font-bold">AIでページを追加</h3>
        <p className="mb-3 text-xs text-neutral-500">
          デッキのテーマ(配色・トーン)に合わせて、背景デザイン込みの1ページを生成します。
        </p>
        <textarea
          autoFocus
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={3}
          placeholder="例: 導入スケジュールを3フェーズで説明するページ。各フェーズの期間と到達目標を載せる"
          className="mb-3 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
        />
        {error && <p className="mb-3 text-xs text-red-500">{error}</p>}
        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            disabled={loading}
            className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
          >
            キャンセル
          </button>
          <button
            onClick={create}
            disabled={loading || !description.trim()}
            className="rounded-lg bg-blue-600 px-5 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-40"
          >
            {loading ? "生成中…(2〜3分)" : "生成して追加"}
          </button>
        </div>
      </div>
    </div>
  );
}

function MiniBtn({
  children,
  onClick,
  title,
}: {
  children: React.ReactNode;
  onClick: () => void;
  title: string;
}) {
  return (
    <button
      title={title}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      className="rounded px-1 text-[11px] text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700"
    >
      {children}
    </button>
  );
}
