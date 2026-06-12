"use client";

import React, { useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { GenerateDialog } from "./GenerateDialog";
import { GenerateImageDialog } from "./GenerateImageDialog";
import { DeckLibraryDialog } from "./DeckLibraryDialog";
import { ShapeEl, TextEl, uid } from "@/lib/types";
import { imageElementFor, uploadImageFile } from "@/lib/upload";
import { useT, useLocale, setLocale } from "@/lib/i18n";

export function TopBar() {
  const t = useT();
  const locale = useLocale();
  const deck = useEditor((s) => s.deck);
  const commit = useEditor((s) => s.commit);
  const undo = useEditor((s) => s.undo);
  const redo = useEditor((s) => s.redo);
  const canUndo = useEditor((s) => s.past.length > 0);
  const canRedo = useEditor((s) => s.future.length > 0);
  const addElement = useEditor((s) => s.addElement);
  const [showGenerate, setShowGenerate] = useState(false);
  const [showGenImage, setShowGenImage] = useState(false);
  const [showLibrary, setShowLibrary] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [exporting, setExporting] = useState(false);
  const imageRef = useRef<HTMLInputElement>(null);

  const addText = (variant: "heading" | "body") => {
    const el: TextEl = {
      id: uid(),
      type: "text",
      text: variant === "heading" ? "見出しテキスト" : "本文テキストを入力",
      x: 80,
      y: variant === "heading" ? 80 : 200,
      w: 600,
      h: variant === "heading" ? 70 : 120,
      fontSize: variant === "heading" ? 40 : 18,
      fontWeight: variant === "heading" ? 800 : 400,
      color: "token:ink",
      align: "left",
      lineHeight: variant === "heading" ? 1.3 : 1.7,
      font: variant === "heading" ? "heading" : "body",
    };
    addElement(el);
  };

  const addShape = (shape: ShapeEl["shape"]) => {
    const el: ShapeEl = {
      id: uid(),
      type: "shape",
      shape,
      x: 480,
      y: 260,
      w: shape === "line" ? 320 : 200,
      h: shape === "line" ? 8 : 200,
      fill: "token:brand",
      radius: shape === "rect" ? 12 : undefined,
      strokeWidth: shape === "line" ? 3 : undefined,
    };
    addElement(el);
  };

  // 画像ファイルをアップロードしてスライドに配置(URL指定はInspectorのsrc欄で可能)
  const uploadImages = async (files: FileList | File[]) => {
    const images = Array.from(files).filter((f) => f.type.startsWith("image/"));
    if (images.length === 0) return;
    setUploading(true);
    try {
      const { deck: d, selectedSlideId } = useEditor.getState();
      const avoid = d.slides.find((s) => s.id === selectedSlideId)?.elements ?? [];
      for (let i = 0; i < images.length; i++) {
        const { url, width, height } = await uploadImageFile(images[i]);
        addElement(imageElementFor(url, width, height, i, avoid));
      }
    } catch (e) {
      alert(e instanceof Error ? e.message : t("uploadFailed"));
    } finally {
      setUploading(false);
    }
  };

  // サーバーサイドでPDF化(Chrome自動検出)。使えない環境では印刷ビューへフォールバック
  const exportPdf = async () => {
    if (exporting) return;
    setExporting(true);
    try {
      const res = await fetch("/api/export", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ deck }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `server export failed (${res.status})`);
      }
      const blob = await res.blob();
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `${deck.title || "deck"}.pdf`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      // フォールバック: 印刷ビュー。非同期後のwindow.openはポップアップ
      // ブロックされることがあるため、ブロック時は理由を表示する
      const w = window.open("/print", "_blank");
      if (!w) {
        alert(`${t("exportFailedAlert")}\n${e instanceof Error ? e.message : e}`);
      }
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="flex h-12 shrink-0 items-center gap-2 border-b border-neutral-200 bg-white px-3">
      <span className="mr-1 rounded bg-neutral-900 px-2 py-0.5 text-xs font-black tracking-wide text-white">
        COMPDECK
      </span>
      <input
        value={deck.title}
        onChange={(e) => commit((d) => (d.title = e.target.value))}
        className="w-56 rounded px-2 py-1 text-sm font-medium hover:bg-neutral-100 focus:bg-neutral-100 focus:outline-none"
      />

      <button
        onClick={() => setLocale(locale === "ja" ? "en" : "ja")}
        title={locale === "ja" ? "Switch to English" : "日本語に切り替え"}
        className="rounded px-1.5 py-1 text-[10px] font-bold tracking-wider text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700"
      >
        {locale === "ja" ? "EN" : "JA"}
      </button>

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton onClick={() => addText("heading")} label={t("heading")} />
      <ToolButton onClick={() => addText("body")} label={t("text")} />
      <ToolButton onClick={() => addShape("rect")} label="□" title={t("rectTitle")} />
      <ToolButton onClick={() => addShape("ellipse")} label="○" title={t("ellipseTitle")} />
      <ToolButton onClick={() => addShape("line")} label="—" title={t("lineTitle")} />
      <ToolButton
        onClick={() => imageRef.current?.click()}
        label={uploading ? t("imageUploading") : t("image")}
        title={t("imageTitle")}
        disabled={uploading}
      />
      <input
        ref={imageRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          if (e.target.files) uploadImages(e.target.files);
          e.target.value = "";
        }}
      />
      <ToolButton onClick={() => setShowGenImage(true)} label={t("aiImage")} title={t("aiImageTitle")} />

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton onClick={undo} label="↩︎" title={t("undoTitle")} disabled={!canUndo} />
      <ToolButton onClick={redo} label="↪︎" title={t("redoTitle")} disabled={!canRedo} />

      <div className="flex-1" />

      <button
        onClick={() => setShowGenerate(true)}
        title={t("createDeckTitle")}
        className="rounded-lg bg-gradient-to-r from-violet-600 to-blue-600 px-4 py-1.5 text-sm font-bold text-white shadow hover:opacity-90"
      >
        {t("createDeck")}
      </button>

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton
        onClick={() => setShowLibrary(true)}
        label={t("deckBtn")}
        title={t("deckBtnTitle")}
      />

      <button
        onClick={exportPdf}
        disabled={exporting}
        title={t("exportPdfTitle")}
        className="rounded-lg bg-neutral-900 px-4 py-1.5 text-sm font-bold text-white hover:bg-neutral-700 disabled:opacity-50"
      >
        {exporting ? t("exportPdfBusy") : t("exportPdf")}
      </button>

      {showGenerate && <GenerateDialog onClose={() => setShowGenerate(false)} />}
      {showGenImage && <GenerateImageDialog onClose={() => setShowGenImage(false)} />}
      {showLibrary && <DeckLibraryDialog onClose={() => setShowLibrary(false)} />}
    </div>
  );
}

function ToolButton({
  onClick,
  label,
  title,
  disabled,
}: {
  onClick: () => void;
  label: string;
  title?: string;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={title ?? label}
      disabled={disabled}
      className="rounded px-2.5 py-1 text-sm text-neutral-600 hover:bg-neutral-100 disabled:opacity-30"
    >
      {label}
    </button>
  );
}
