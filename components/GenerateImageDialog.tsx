"use client";

import React, { useState } from "react";
import { useEditor } from "@/lib/store";
import { imageElementFor } from "@/lib/upload";

// AIで画像パーツ(挿絵・アイコン・写真風素材)を1枚生成してスライドに配置する
export function GenerateImageDialog({ onClose }: { onClose: () => void }) {
  const addElement = useEditor((s) => s.addElement);
  const [prompt, setPrompt] = useState("");
  const [transparent, setTransparent] = useState(true);
  const [size, setSize] = useState<"1024x1024" | "1536x1024" | "1024x1536">("1024x1024");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const generate = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/generate/image", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt, transparent, size }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `生成に失敗しました (${res.status})`);
      const { deck, selectedSlideId } = useEditor.getState();
      const avoid = deck.slides.find((s) => s.id === selectedSlideId)?.elements ?? [];
      addElement(imageElementFor(data.url, data.width, data.height, 0, avoid));
      onClose();
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
        className="w-[460px] rounded-2xl bg-white p-5 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h3 className="mb-1 text-base font-bold">AIで画像パーツを生成</h3>
        <p className="mb-3 text-xs text-neutral-500">
          挿絵・アイコン・写真風素材を1枚生成して、選択中のスライドに配置します。
        </p>
        <textarea
          autoFocus
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          rows={3}
          placeholder="例: 聴診器と母子手帳のフラットイラスト、淡いグリーン基調、線は少なめ"
          className="mb-3 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
        />
        <div className="mb-3 flex items-center justify-between text-xs text-neutral-600">
          <label className="flex items-center gap-1.5">
            <input
              type="checkbox"
              checked={transparent}
              onChange={(e) => setTransparent(e.target.checked)}
            />
            透過背景(パーツとして重ねやすい)
          </label>
          <select
            value={size}
            onChange={(e) => setSize(e.target.value as typeof size)}
            className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
          >
            <option value="1024x1024">正方形</option>
            <option value="1536x1024">横長</option>
            <option value="1024x1536">縦長</option>
          </select>
        </div>
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
            onClick={generate}
            disabled={loading || !prompt.trim()}
            className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {loading ? "生成中…(30〜90秒)" : "生成して配置"}
          </button>
        </div>
      </div>
    </div>
  );
}
