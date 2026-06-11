"use client";

import React, { useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";

export function GenerateDialog({ onClose }: { onClose: () => void }) {
  const setDeck = useEditor((s) => s.setDeck);
  const [topic, setTopic] = useState("");
  const [pages, setPages] = useState(8);
  const [audience, setAudience] = useState("");
  const [tone, setTone] = useState("信頼感のあるビジネス");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const generate = async () => {
    setLoading(true);
    setError(null);
    setNotice(null);
    try {
      const res = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ topic, pages, audience, tone }),
      });
      if (!res.ok) throw new Error(`生成に失敗しました (${res.status})`);
      const data = await res.json();
      const deck = normalizeDeck(data.deck);
      setDeck(deck);
      if (data.mode === "demo") {
        setNotice(
          "ANTHROPIC_API_KEY が未設定のため、テンプレートベースのデモ生成で作成しました。キーを設定するとClaudeによるフル生成になります。",
        );
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

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
    >
      <div
        className="w-[480px] rounded-2xl bg-white p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-1 text-lg font-bold">AIでスライドを生成</h2>
        <p className="mb-4 text-xs text-neutral-500">
          テーマを入力すると、アートディレクション(配色・フォント)込みでデッキを一括生成します。生成後は全パーツを自由に編集できます。
        </p>

        <label className="mb-3 block text-xs font-medium text-neutral-600">
          資料のテーマ・伝えたいこと *
          <textarea
            autoFocus
            value={topic}
            onChange={(e) => setTopic(e.target.value)}
            rows={3}
            placeholder="例: SaaSプロダクト「○○」の新機能を既存顧客に紹介し、アップセルにつなげる提案資料"
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
          />
        </label>

        <div className="mb-3 grid grid-cols-2 gap-3">
          <label className="block text-xs font-medium text-neutral-600">
            ページ数
            <input
              type="number"
              min={3}
              max={20}
              value={pages}
              onChange={(e) => setPages(parseInt(e.target.value) || 8)}
              className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-xs font-medium text-neutral-600">
            トーン
            <select
              value={tone}
              onChange={(e) => setTone(e.target.value)}
              className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
            >
              <option>信頼感のあるビジネス</option>
              <option>先進的でテック</option>
              <option>親しみやすくカジュアル</option>
              <option>上品でエディトリアル</option>
            </select>
          </label>
        </div>

        <label className="mb-4 block text-xs font-medium text-neutral-600">
          想定読者(任意)
          <input
            type="text"
            value={audience}
            onChange={(e) => setAudience(e.target.value)}
            placeholder="例: 製造業の経営層"
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
          />
        </label>

        {error && <p className="mb-3 text-xs text-red-500">{error}</p>}
        {notice && <p className="mb-3 text-xs text-amber-600">{notice}</p>}

        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100"
          >
            キャンセル
          </button>
          <button
            onClick={generate}
            disabled={loading || !topic.trim()}
            className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {loading ? "生成中…(最大1分ほど)" : "生成する"}
          </button>
        </div>
      </div>
    </div>
  );
}
