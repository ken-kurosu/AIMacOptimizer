"use client";

import React from "react";
import { useEditor } from "@/lib/store";
import { ScaledSlide } from "./SlideRenderer";

export function SlideList() {
  const deck = useEditor((s) => s.deck);
  const selectedSlideId = useEditor((s) => s.selectedSlideId);
  const select = useEditor((s) => s.select);
  const addSlide = useEditor((s) => s.addSlide);
  const duplicateSlide = useEditor((s) => s.duplicateSlide);
  const deleteSlide = useEditor((s) => s.deleteSlide);
  const moveSlide = useEditor((s) => s.moveSlide);

  return (
    <div className="flex h-full w-56 shrink-0 flex-col border-r border-neutral-200 bg-white">
      <div className="flex items-center justify-between border-b border-neutral-200 px-3 py-2">
        <span className="text-xs font-bold text-neutral-500">ページ</span>
        <button
          onClick={() => addSlide(undefined, selectedSlideId)}
          className="rounded bg-neutral-900 px-2 py-1 text-xs font-medium text-white hover:bg-neutral-700"
        >
          + 追加
        </button>
      </div>
      <div className="flex-1 space-y-3 overflow-y-auto p-3">
        {deck.slides.map((slide, i) => (
          <div key={slide.id} className="group">
            <div
              onClick={() => select(slide.id)}
              className={`cursor-pointer overflow-hidden rounded-lg border-2 transition ${
                slide.id === selectedSlideId
                  ? "border-blue-500 shadow-md"
                  : "border-neutral-200 hover:border-neutral-400"
              }`}
            >
              <ScaledSlide slide={slide} theme={deck.theme} width={192} />
            </div>
            <div className="mt-1 flex items-center justify-between px-0.5">
              <span className="max-w-[100px] truncate text-[11px] text-neutral-500">
                {i + 1}. {slide.name}
              </span>
              <div className="flex gap-0.5 opacity-0 transition group-hover:opacity-100">
                <MiniBtn title="上へ" onClick={() => moveSlide(slide.id, -1)}>↑</MiniBtn>
                <MiniBtn title="下へ" onClick={() => moveSlide(slide.id, 1)}>↓</MiniBtn>
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
