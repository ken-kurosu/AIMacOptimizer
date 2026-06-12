"use client";

import React, { useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";
import { uploadImageFile } from "@/lib/upload";

// 生成ダイアログ。迷わないことを最優先に、入力は
// 「内容(自由記述)・ページ数・参考画像(任意)」の3つだけに絞る。
// エンジンはimage2(カンプ生成)一択。APIキーが無い環境はサーバー側で
// 自動的にデモ生成へフォールバックする。
export function GenerateDialog({ onClose }: { onClose: () => void }) {
  const setDeck = useEditor((s) => s.setDeck);
  const [topic, setTopic] = useState("");
  const [pages, setPages] = useState(6);
  const [refs, setRefs] = useState<string[]>([]);
  const [refUploading, setRefUploading] = useState(false);
  const refInput = useRef<HTMLInputElement>(null);
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

  const generate = async () => {
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
          references: refs.length > 0 ? refs : undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `生成に失敗しました (${res.status})`);
      setDeck(normalizeDeck(data.deck));
      if (data.mode === "demo") {
        setNotice(
          data.warning ?? "APIキーが未設定のため、デモ生成で作成しました。",
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
      onClick={loading ? undefined : onClose}
    >
      <div
        className="w-[520px] rounded-2xl bg-white p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-1 text-lg font-bold">AIでスライドを生成</h2>
        <p className="mb-4 text-xs text-neutral-500">
          内容を書くだけで、デザイン込みのデッキを作ります。生成後はすべて編集できます。
        </p>

        <textarea
          autoFocus
          value={topic}
          onChange={(e) => setTopic(e.target.value)}
          rows={5}
          placeholder={
            "どんな資料を作りたいか、自由に書いてください。\n" +
            "誰向けか・トーン・必ず入れたい数字や構成があれば一緒に。\n\n" +
            "例: 自家焙煎コーヒー定期便の紹介資料。在宅ワーカー向けに上品なトーンで。月額980円(税込)は必ず載せる"
          }
          className="mb-3 w-full rounded-xl border border-neutral-300 px-3 py-2.5 text-sm leading-relaxed"
        />

        <div className="mb-5 flex items-center justify-between">
          <label className="flex items-center gap-2 text-xs text-neutral-600">
            ページ数
            <input
              type="number"
              min={3}
              max={12}
              value={pages}
              onChange={(e) => setPages(parseInt(e.target.value) || 6)}
              className="w-16 rounded-lg border border-neutral-300 px-2 py-1.5 text-sm"
            />
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

        <div className="flex items-center justify-between">
          <span className="text-[11px] text-neutral-400">
            {loading ? "" : "目安: 1ページあたり約1分"}
          </span>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              disabled={loading}
              className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
            >
              キャンセル
            </button>
            <button
              onClick={generate}
              disabled={loading || !topic.trim()}
              className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
            >
              {loading ? "生成中…そのままお待ちください" : "生成する"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
