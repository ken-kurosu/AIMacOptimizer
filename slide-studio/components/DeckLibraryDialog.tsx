"use client";

import React, { useEffect, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";

// デッキ管理: サーバーに保存されたデッキの一覧と、現在のデッキの保存(共有リンク作成)。
// 保存はAIka連携と同じ /api/decks を使うので、リンクを渡せば誰でも同じデッキを開ける。

interface DeckMeta {
  id: string;
  title: string;
  pages: number;
  updatedAt: number;
}

export function DeckLibraryDialog({ onClose }: { onClose: () => void }) {
  const deck = useEditor((s) => s.deck);
  const setDeck = useEditor((s) => s.setDeck);
  const [decks, setDecks] = useState<DeckMeta[] | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedUrl, setSavedUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    fetch("/api/decks")
      .then((r) => r.json())
      .then((d) => setDecks(d.decks ?? []))
      .catch(() => setDecks([]));
  };
  useEffect(load, []);

  const open = async (id: string) => {
    try {
      const res = await fetch(`/api/decks/${id}`);
      if (!res.ok) throw new Error("デッキを開けませんでした");
      setDeck(normalizeDeck(await res.json()));
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : "デッキを開けませんでした");
    }
  };

  const remove = async (id: string) => {
    await fetch(`/api/decks/${id}`, { method: "DELETE" }).catch(() => {});
    load();
  };

  const saveCurrent = async () => {
    setSaving(true);
    setError(null);
    setSavedUrl(null);
    try {
      const res = await fetch("/api/decks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ deck }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `保存に失敗しました (${res.status})`);
      setSavedUrl(data.editUrl);
      await navigator.clipboard?.writeText(data.editUrl).catch(() => {});
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "保存に失敗しました");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
    >
      <div
        className="w-[480px] rounded-2xl bg-white p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-3 flex items-center justify-between">
          <h3 className="text-base font-bold">デッキ</h3>
          <button
            onClick={saveCurrent}
            disabled={saving}
            title="現在のデッキをサーバーに保存し、共有リンクをコピーします"
            className="rounded-lg bg-neutral-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {saving ? "保存中…" : "現在のデッキを保存して共有"}
          </button>
        </div>

        {savedUrl && (
          <p className="mb-2 break-all rounded-lg bg-emerald-50 px-3 py-2 text-[11px] text-emerald-700">
            共有リンクをコピーしました: {savedUrl}
          </p>
        )}
        {error && <p className="mb-2 text-xs text-red-500">{error}</p>}

        <div className="max-h-[320px] space-y-1 overflow-y-auto">
          {decks === null ? (
            <p className="py-6 text-center text-xs text-neutral-400">読み込み中…</p>
          ) : decks.length === 0 ? (
            <p className="py-6 text-center text-xs text-neutral-400">
              保存されたデッキはまだありません
            </p>
          ) : (
            decks.map((d) => (
              <div
                key={d.id}
                className="group flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-neutral-50"
              >
                <button
                  onClick={() => open(d.id)}
                  className="min-w-0 flex-1 truncate text-left text-sm text-neutral-800 hover:underline"
                  title="開く"
                >
                  {d.title}
                </button>
                <span className="shrink-0 text-[10px] text-neutral-400">
                  {d.pages}p ・ {new Date(d.updatedAt).toLocaleDateString("ja-JP")}
                </span>
                <button
                  onClick={() => remove(d.id)}
                  title="削除"
                  className="shrink-0 rounded px-1 text-xs text-neutral-300 opacity-0 transition hover:text-red-500 group-hover:opacity-100"
                >
                  ✕
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
