"use client";

import React, { useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";
import { GenerateDialog } from "./GenerateDialog";
import { GenerateImageDialog } from "./GenerateImageDialog";
import { DeckLibraryDialog } from "./DeckLibraryDialog";
import { ShapeEl, TextEl, uid } from "@/lib/types";
import { imageElementFor, uploadImageFile } from "@/lib/upload";

export function TopBar() {
  const deck = useEditor((s) => s.deck);
  const commit = useEditor((s) => s.commit);
  const undo = useEditor((s) => s.undo);
  const redo = useEditor((s) => s.redo);
  const canUndo = useEditor((s) => s.past.length > 0);
  const canRedo = useEditor((s) => s.future.length > 0);
  const setDeck = useEditor((s) => s.setDeck);
  const addElement = useEditor((s) => s.addElement);
  const [showGenerate, setShowGenerate] = useState(false);
  const [showGenImage, setShowGenImage] = useState(false);
  const [showLibrary, setShowLibrary] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
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
      alert(e instanceof Error ? e.message : "アップロードに失敗しました");
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
      if (!res.ok) throw new Error("server export unavailable");
      const blob = await res.blob();
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `${deck.title || "deck"}.pdf`;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch {
      window.open("/print", "_blank");
    } finally {
      setExporting(false);
    }
  };

  const exportJson = () => {
    const blob = new Blob([JSON.stringify(deck, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${deck.title || "deck"}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const importJson = (file: File) => {
    const reader = new FileReader();
    reader.onload = () => {
      try {
        setDeck(normalizeDeck(JSON.parse(String(reader.result))));
      } catch {
        alert("JSONの読み込みに失敗しました");
      }
    };
    reader.readAsText(file);
  };

  // 画像だけのPDF資料を、編集可能なデッキ(背景画像+テキスト要素)へ分解して取り込む
  const importPdf = async (file: File) => {
    setImporting(true);
    try {
      const res = await fetch("/api/import", {
        method: "POST",
        headers: { "Content-Type": "application/pdf" },
        body: file,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `取り込みに失敗しました (${res.status})`);
      setDeck(normalizeDeck(data.deck));
    } catch (e) {
      alert(e instanceof Error ? e.message : "PDFの取り込みに失敗しました");
    } finally {
      setImporting(false);
    }
  };

  const importFile = (file: File) => {
    if (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")) importPdf(file);
    else importJson(file);
  };

  return (
    <div className="flex h-12 shrink-0 items-center gap-2 border-b border-neutral-200 bg-white px-3">
      <span className="mr-1 rounded bg-neutral-900 px-2 py-0.5 text-xs font-black tracking-wide text-white">
        SLIDE STUDIO
      </span>
      <input
        value={deck.title}
        onChange={(e) => commit((d) => (d.title = e.target.value))}
        className="w-56 rounded px-2 py-1 text-sm font-medium hover:bg-neutral-100 focus:bg-neutral-100 focus:outline-none"
      />

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton onClick={() => addText("heading")} label="見出し" />
      <ToolButton onClick={() => addText("body")} label="テキスト" />
      <ToolButton onClick={() => addShape("rect")} label="□" title="四角形" />
      <ToolButton onClick={() => addShape("ellipse")} label="○" title="円" />
      <ToolButton onClick={() => addShape("line")} label="—" title="線" />
      <ToolButton
        onClick={() => imageRef.current?.click()}
        label={uploading ? "アップロード中…" : "画像"}
        title="画像をアップロードして配置(キャンバスへのドラッグ&ドロップも可)"
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
      <ToolButton onClick={() => setShowGenImage(true)} label="✦画像" title="AIで画像パーツを生成して配置" />

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton onClick={undo} label="↩︎" title="元に戻す (Ctrl+Z)" disabled={!canUndo} />
      <ToolButton onClick={redo} label="↪︎" title="やり直す (Ctrl+Shift+Z)" disabled={!canRedo} />

      <div className="flex-1" />

      <button
        onClick={() => setShowGenerate(true)}
        title="作りたい内容を書くと、AIが構成案→デザイン込みのデッキを自動作成します"
        className="rounded-lg bg-gradient-to-r from-violet-600 to-blue-600 px-4 py-1.5 text-sm font-bold text-white shadow hover:opacity-90"
      >
        ✦ 資料を作る
      </button>

      <div className="mx-1 h-6 w-px bg-neutral-200" />

      <ToolButton
        onClick={() => setShowLibrary(true)}
        label="デッキ"
        title="保存済みデッキを開く / 現在のデッキを保存して共有リンクを作る"
      />
      <ToolButton onClick={exportJson} label="JSON保存" />
      <ToolButton
        onClick={() => fileRef.current?.click()}
        label={importing ? "分解中…" : "読込"}
        title="JSONデッキ、またはスライドPDF(画像のみ可)を編集可能な状態に分解して取り込みます"
        disabled={importing}
      />
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

      <button
        onClick={exportPdf}
        disabled={exporting}
        title="Chromeを自動検出してワンクリックでPDF化。使えない環境では印刷ビューが開きます"
        className="rounded-lg bg-neutral-900 px-4 py-1.5 text-sm font-bold text-white hover:bg-neutral-700 disabled:opacity-50"
      >
        {exporting ? "書き出し中…" : "PDF書き出し"}
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
