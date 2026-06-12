"use client";

import React, { useEffect, useState, useSyncExternalStore } from "react";
import { useEditor } from "@/lib/store";
import { TopBar } from "./TopBar";
import { SlideList } from "./SlideList";
import { Canvas } from "./Canvas";
import { Inspector } from "./Inspector";
import { ThemePanel } from "./ThemePanel";

const emptySubscribe = () => () => {};

export function Editor() {
  // localStorageからの復元とSSRの不一致を避けるため、マウント後に描画
  // (effect内setStateを避けるため、ハイドレーション判定はuseSyncExternalStoreで行う)
  const mounted = useSyncExternalStore(emptySubscribe, () => true, () => false);
  useEffect(() => {
    // persistは状態変更時にしか書き込まないため、初期デッキも印刷ビューから
    // 参照できるようマウント時に一度保存をトリガーする
    useEditor.setState((s) => ({ deck: s.deck }));

    // 外部連携(/?deck=<id>)で開かれたら、保存済みデッキを取り込んでURLを掃除する
    const deckId = new URLSearchParams(window.location.search).get("deck");
    if (deckId && /^[a-z0-9]+$/.test(deckId)) {
      fetch(`/api/decks/${deckId}`)
        .then((r) => (r.ok ? r.json() : Promise.reject()))
        .then(async (d) => {
          const { normalizeDeck } = await import("@/lib/normalize");
          useEditor.getState().setDeck(normalizeDeck(d));
          window.history.replaceState(null, "", "/");
        })
        .catch(() => {});
    }
  }, []);

  const undo = useEditor((s) => s.undo);
  const redo = useEditor((s) => s.redo);
  const deleteElement = useEditor((s) => s.deleteElement);
  const duplicateElement = useEditor((s) => s.duplicateElement);
  const selectedElementId = useEditor((s) => s.selectedElementId);
  const editingElementId = useEditor((s) => s.editingElementId);
  const beginTransient = useEditor((s) => s.beginTransient);
  const transient = useEditor((s) => s.transient);
  const selectedSlideId = useEditor((s) => s.selectedSlideId);
  const [tab, setTab] = useState<"slides" | "theme">("slides");

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const tag = target.tagName;
      if (
        editingElementId ||
        tag === "INPUT" ||
        tag === "TEXTAREA" ||
        tag === "SELECT" ||
        target.isContentEditable
      )
        return;

      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
        return;
      }
      if (mod && e.key.toLowerCase() === "d" && selectedElementId) {
        e.preventDefault();
        duplicateElement(selectedElementId);
        return;
      }
      if ((e.key === "Delete" || e.key === "Backspace") && selectedElementId) {
        e.preventDefault();
        deleteElement(selectedElementId);
        return;
      }
      if (selectedElementId && e.key.startsWith("Arrow")) {
        e.preventDefault();
        const d = e.shiftKey ? 10 : 1;
        const dx = e.key === "ArrowLeft" ? -d : e.key === "ArrowRight" ? d : 0;
        const dy = e.key === "ArrowUp" ? -d : e.key === "ArrowDown" ? d : 0;
        beginTransient();
        transient((deck) => {
          const el = deck.slides
            .find((s) => s.id === selectedSlideId)
            ?.elements.find((x) => x.id === selectedElementId);
          if (el) {
            el.x += dx;
            el.y += dy;
          }
        });
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [
    undo,
    redo,
    deleteElement,
    duplicateElement,
    selectedElementId,
    editingElementId,
    beginTransient,
    transient,
    selectedSlideId,
  ]);

  if (!mounted) {
    return (
      <div className="flex h-screen items-center justify-center text-sm text-neutral-400">
        読み込み中…
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col bg-neutral-100">
      <TopBar />
      <div className="flex min-h-0 flex-1">
        <div className="flex shrink-0">
          <div className="flex w-10 flex-col items-center gap-1 border-r border-neutral-200 bg-white py-2">
            <SideTab active={tab === "slides"} onClick={() => setTab("slides")} label="頁" />
            <SideTab active={tab === "theme"} onClick={() => setTab("theme")} label="色" />
          </div>
          {tab === "slides" ? <SlideList /> : <ThemePanel />}
        </div>
        <div className="min-w-0 flex-1">
          <Canvas />
        </div>
        <Inspector />
      </div>
    </div>
  );
}

function SideTab({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex h-8 w-8 items-center justify-center rounded text-xs font-bold ${
        active ? "bg-neutral-900 text-white" : "text-neutral-400 hover:bg-neutral-100"
      }`}
    >
      {label}
    </button>
  );
}
