"use client";

import React, { useEffect, useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";

// デッキ管理ダイアログ = ファイル機能のハブ。
//  - このデッキ: 共有リンク作成(サーバー保存) / JSONファイルへ書き出し
//  - 開く: JSON/PDFファイルから(PDFは編集可能なデッキに分解) / 保存済み一覧から
// 共有リンクはAIka連携と同じ /api/decks を使うので、渡せば誰でも同じデッキを開ける。

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
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

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

  // 共有リンク作成(サーバー保存)
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

  // JSONファイルへ書き出し(バックアップ用)
  const exportJson = () => {
    const blob = new Blob([JSON.stringify(deck, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${deck.title || "deck"}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  // JSON/PDFファイルから開く(PDFは編集可能なデッキへ分解)
  const importFile = (file: File) => {
    setError(null);
    if (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")) {
      setImporting(true);
      fetch("/api/import", {
        method: "POST",
        headers: { "Content-Type": "application/pdf" },
        body: file,
      })
        .then(async (res) => {
          const data = await res.json();
          if (!res.ok) throw new Error(data.error ?? `取り込みに失敗しました (${res.status})`);
          setDeck(normalizeDeck(data.deck));
          onClose();
        })
        .catch((e) => setError(e instanceof Error ? e.message : "PDFの取り込みに失敗しました"))
        .finally(() => setImporting(false));
    } else {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          setDeck(normalizeDeck(JSON.parse(String(reader.result))));
          onClose();
        } catch {
          setError("JSONの読み込みに失敗しました");
        }
      };
      reader.readAsText(file);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={importing ? undefined : onClose}
    >
      <div
        className="w-[500px] rounded-2xl bg-white p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 className="mb-3 text-base font-bold">デッキ</h3>

        <div className="mb-1 text-[11px] font-bold tracking-wider text-neutral-400">
          このデッキ「{deck.title}」
        </div>
        <div className="mb-4 flex gap-2">
          <button
            onClick={saveCurrent}
            disabled={saving}
            title="サーバーに保存して、誰でも開ける共有リンクをコピーします"
            className="rounded-lg bg-neutral-900 px-3 py-2 text-xs font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {saving ? "保存中…" : "共有リンクを作る"}
          </button>
          <button
            onClick={exportJson}
            title="バックアップ用にJSONファイルとしてダウンロードします"
            className="rounded-lg border border-neutral-300 px-3 py-2 text-xs text-neutral-700 hover:bg-neutral-100"
          >
            ファイルに保存 (JSON)
          </button>
        </div>

        {savedUrl && (
          <p className="mb-3 break-all rounded-lg bg-emerald-50 px-3 py-2 text-[11px] text-emerald-700">
            共有リンクをコピーしました: {savedUrl}
          </p>
        )}

        <div className="mb-1 text-[11px] font-bold tracking-wider text-neutral-400">開く</div>
        <div className="mb-2">
          <button
            onClick={() => fileRef.current?.click()}
            disabled={importing}
            title="JSONはそのまま、PDFは編集可能なデッキに分解。テキストPDFは文字を元の位置・サイズ・フォントのまま打ち直せます(画像のみPDFはAIで文字を読み取り)"
            className="rounded-lg border border-neutral-300 px-3 py-2 text-xs text-neutral-700 hover:bg-neutral-100 disabled:opacity-40"
          >
            {importing ? "PDFを分解中…(ページ数×最大1分)" : "ファイルから開く (JSON / PDF)"}
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="application/json,.json,application/pdf,.pdf"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) importFile(f);
              e.target.value = "";
            }}
          />
        </div>

        {error && <p className="mb-2 text-xs text-red-500">{error}</p>}

        <div className="max-h-[260px] space-y-1 overflow-y-auto">
          {decks === null ? (
            <p className="py-4 text-center text-xs text-neutral-400">読み込み中…</p>
          ) : decks.length === 0 ? (
            <p className="py-4 text-center text-xs text-neutral-400">
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
