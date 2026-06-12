"use client";

import React, { useState } from "react";
import { useEditor } from "@/lib/store";
import { imageElementFor } from "@/lib/upload";
import { useT } from "@/lib/i18n";

// AIで画像パーツ(挿絵・アイコン・写真風素材)を1枚生成してスライドに配置する
export function GenerateImageDialog({ onClose }: { onClose: () => void }) {
  const t = useT();
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
      if (!res.ok) throw new Error(data.error ?? `${t("generateFailed")} (${res.status})`);
      const { deck, selectedSlideId } = useEditor.getState();
      const avoid = deck.slides.find((s) => s.id === selectedSlideId)?.elements ?? [];
      addElement(imageElementFor(data.url, data.width, data.height, 0, avoid));
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : t("generateFailed"));
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
        <h3 className="mb-1 text-base font-bold">{t("giTitle")}</h3>
        <p className="mb-3 text-xs text-neutral-500">
          {t("giIntro")}
        </p>
        <textarea
          autoFocus
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          rows={3}
          placeholder={t("giPlaceholder")}
          className="mb-3 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
        />
        <div className="mb-3 flex items-center justify-between text-xs text-neutral-600">
          <label className="flex items-center gap-1.5">
            <input
              type="checkbox"
              checked={transparent}
              onChange={(e) => setTransparent(e.target.checked)}
            />
            {t("giTransparent")}
          </label>
          <select
            value={size}
            onChange={(e) => setSize(e.target.value as typeof size)}
            className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
          >
            <option value="1024x1024">{t("giSquare")}</option>
            <option value="1536x1024">{t("giLandscape")}</option>
            <option value="1024x1536">{t("giPortrait")}</option>
          </select>
        </div>
        {error && <p className="mb-3 text-xs text-red-500">{error}</p>}
        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            disabled={loading}
            className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100 disabled:opacity-40"
          >
            {t("cancel")}
          </button>
          <button
            onClick={generate}
            disabled={loading || !prompt.trim()}
            className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {loading ? t("giCreating") : t("giCreate")}
          </button>
        </div>
      </div>
    </div>
  );
}
