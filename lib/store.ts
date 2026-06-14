"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { Deck, Slide, SlideElement, Theme, uid } from "./types";
import { generateMockDeck } from "./mock";

export const STORAGE_KEY = "compdeck-deck";

interface EditorState {
  deck: Deck;
  selectedSlideId: string;
  selectedElementId: string | null; // 主選択(Inspectorが編集する対象)
  selectedElementIds: string[]; // 複数選択の集合(主選択を含む)
  editingElementId: string | null; // インラインテキスト編集中
  past: Deck[];
  future: Deck[];

  select: (slideId: string, elementId?: string | null) => void;
  // 修飾キー(Cmd/Shift)+クリック用: 選択集合に追加/解除する
  toggleSelect: (slideId: string, elementId: string) => void;
  // 範囲選択など、まとめて選択する
  selectMany: (slideId: string, ids: string[]) => void;
  setEditing: (id: string | null) => void;

  // 履歴に積む構造変更
  commit: (fn: (deck: Deck) => void) => void;
  // ドラッグ中など履歴に積まない更新(開始時に beginTransient を呼ぶ)
  beginTransient: () => void;
  transient: (fn: (deck: Deck) => void) => void;

  undo: () => void;
  redo: () => void;

  setDeck: (deck: Deck) => void;
  addSlide: (slide?: Slide, afterId?: string) => void;
  // AI再生成などでスライドの中身を丸ごと差し替える(idと位置は維持)
  replaceSlide: (id: string, slide: Slide) => void;
  duplicateSlide: (id: string) => void;
  deleteSlide: (id: string) => void;
  moveSlide: (id: string, dir: -1 | 1) => void;
  addElement: (el: SlideElement) => void;
  updateElement: (id: string, patch: Partial<SlideElement>) => void;
  deleteElement: (id: string) => void;
  deleteElements: (ids: string[]) => void;
  duplicateElement: (id: string) => void;
  duplicateElements: (ids: string[]) => void;
  reorderElement: (id: string, dir: -1 | 1) => void;
  updateTheme: (patch: Partial<Theme>) => void;

  // 分解(Magic Layers)エフェクト用の一時状態(永続化しない)
  fxScanning: boolean;
  fxPopIds: string[];
  setFxScanning: (v: boolean) => void;
  setFxPopIds: (ids: string[]) => void;
}

const HISTORY_LIMIT = 60;

function cloneDeck(deck: Deck): Deck {
  return structuredClone(deck);
}

const initialLang =
  typeof navigator !== "undefined" && !navigator.language?.toLowerCase().startsWith("ja")
    ? ("en" as const)
    : ("ja" as const);
const initialDeck = generateMockDeck({
  topic: initialLang === "en" ? "Welcome to CompDeck" : "CompDeck へようこそ",
  pages: 6,
  lang: initialLang,
});

export const useEditor = create<EditorState>()(
  persist(
    (set, get) => ({
      deck: initialDeck,
      selectedSlideId: initialDeck.slides[0].id,
      selectedElementId: null,
      selectedElementIds: [],
      editingElementId: null,
      past: [],
      future: [],

      // 注意: editingElementId はここでは消さない。
      // インライン編集の確定は contentEditable の blur(finishTextEdit)が担う。
      select: (slideId, elementId = null) =>
        set({
          selectedSlideId: slideId,
          selectedElementId: elementId,
          selectedElementIds: elementId ? [elementId] : [],
        }),

      toggleSelect: (slideId, elementId) => {
        const { selectedSlideId, selectedElementIds } = get();
        // 別スライドに切り替わったら選択をその要素だけにする
        if (slideId !== selectedSlideId) {
          set({ selectedSlideId: slideId, selectedElementId: elementId, selectedElementIds: [elementId] });
          return;
        }
        const has = selectedElementIds.includes(elementId);
        const ids = has
          ? selectedElementIds.filter((x) => x !== elementId)
          : [...selectedElementIds, elementId];
        set({ selectedElementIds: ids, selectedElementId: ids[ids.length - 1] ?? null });
      },

      selectMany: (slideId, ids) =>
        set({
          selectedSlideId: slideId,
          selectedElementIds: ids,
          selectedElementId: ids[ids.length - 1] ?? null,
        }),

      setEditing: (id) => set({ editingElementId: id }),

      commit: (fn) => {
        const { deck, past } = get();
        const next = cloneDeck(deck);
        fn(next);
        set({ deck: next, past: [...past.slice(-HISTORY_LIMIT), deck], future: [] });
      },

      beginTransient: () => {
        const { deck, past } = get();
        set({ past: [...past.slice(-HISTORY_LIMIT), cloneDeck(deck)], future: [] });
      },

      transient: (fn) => {
        const next = cloneDeck(get().deck);
        fn(next);
        set({ deck: next });
      },

      undo: () => {
        const { past, deck, future } = get();
        if (past.length === 0) return;
        const prev = past[past.length - 1];
        set({
          deck: prev,
          past: past.slice(0, -1),
          future: [deck, ...future].slice(0, HISTORY_LIMIT),
          selectedSlideId: prev.slides.some((s) => s.id === get().selectedSlideId)
            ? get().selectedSlideId
            : prev.slides[0].id,
          selectedElementId: null,
          selectedElementIds: [],
          editingElementId: null,
        });
      },

      redo: () => {
        const { past, deck, future } = get();
        if (future.length === 0) return;
        const next = future[0];
        set({
          deck: next,
          past: [...past, deck].slice(-HISTORY_LIMIT),
          future: future.slice(1),
          selectedSlideId: next.slides.some((s) => s.id === get().selectedSlideId)
            ? get().selectedSlideId
            : next.slides[0].id,
          selectedElementId: null,
          selectedElementIds: [],
          editingElementId: null,
        });
      },

      setDeck: (deck) => {
        const { deck: old, past } = get();
        set({
          deck,
          past: [...past.slice(-HISTORY_LIMIT), old],
          future: [],
          selectedSlideId: deck.slides[0]?.id ?? "",
          selectedElementId: null,
          selectedElementIds: [],
          editingElementId: null,
        });
      },

      addSlide: (slide, afterId) => {
        const s: Slide = slide ?? {
          id: uid(),
          name: "新しいスライド",
          background: { color: "token:bg", preset: "none" },
          elements: [],
        };
        get().commit((deck) => {
          const idx = afterId ? deck.slides.findIndex((x) => x.id === afterId) : -1;
          if (idx >= 0) deck.slides.splice(idx + 1, 0, s);
          else deck.slides.push(s);
        });
        set({ selectedSlideId: s.id, selectedElementId: null, selectedElementIds: [] });
      },

      replaceSlide: (id, slide) => {
        get().commit((deck) => {
          const i = deck.slides.findIndex((s) => s.id === id);
          if (i >= 0) deck.slides[i] = { ...slide, id };
        });
        set({ selectedElementId: null, selectedElementIds: [], editingElementId: null });
      },

      duplicateSlide: (id) => {
        const src = get().deck.slides.find((s) => s.id === id);
        if (!src) return;
        const copy = structuredClone(src);
        copy.id = uid();
        copy.name = `${src.name} のコピー`;
        copy.elements.forEach((e) => (e.id = uid()));
        get().addSlide(copy, id);
      },

      deleteSlide: (id) => {
        const { deck } = get();
        if (deck.slides.length <= 1) return;
        const idx = deck.slides.findIndex((s) => s.id === id);
        get().commit((d) => {
          d.slides = d.slides.filter((s) => s.id !== id);
        });
        const slides = get().deck.slides;
        set({
          selectedSlideId: slides[Math.min(idx, slides.length - 1)].id,
          selectedElementId: null,
          selectedElementIds: [],
        });
      },

      moveSlide: (id, dir) =>
        get().commit((deck) => {
          const i = deck.slides.findIndex((s) => s.id === id);
          const j = i + dir;
          if (i < 0 || j < 0 || j >= deck.slides.length) return;
          const [s] = deck.slides.splice(i, 1);
          deck.slides.splice(j, 0, s);
        }),

      addElement: (el) => {
        const slideId = get().selectedSlideId;
        get().commit((deck) => {
          deck.slides.find((s) => s.id === slideId)?.elements.push(el);
        });
        set({ selectedElementId: el.id, selectedElementIds: [el.id] });
      },

      updateElement: (id, patch) => {
        const slideId = get().selectedSlideId;
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          if (!slide) return;
          const i = slide.elements.findIndex((e) => e.id === id);
          if (i >= 0) slide.elements[i] = { ...slide.elements[i], ...patch } as SlideElement;
        });
      },

      deleteElement: (id) => {
        const slideId = get().selectedSlideId;
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          if (slide) slide.elements = slide.elements.filter((e) => e.id !== id);
        });
        set({ selectedElementId: null, selectedElementIds: [], editingElementId: null });
      },

      deleteElements: (ids) => {
        const slideId = get().selectedSlideId;
        const idset = new Set(ids);
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          if (slide) slide.elements = slide.elements.filter((e) => !idset.has(e.id));
        });
        set({ selectedElementId: null, selectedElementIds: [], editingElementId: null });
      },

      duplicateElement: (id) => {
        const slideId = get().selectedSlideId;
        const newId = uid();
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          const src = slide?.elements.find((e) => e.id === id);
          if (!slide || !src) return;
          const copy = structuredClone(src);
          copy.id = newId;
          copy.x += 24;
          copy.y += 24;
          slide.elements.push(copy);
        });
        set({ selectedElementId: newId, selectedElementIds: [newId] });
      },

      duplicateElements: (ids) => {
        const slideId = get().selectedSlideId;
        const idset = new Set(ids);
        const newIds: string[] = [];
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          if (!slide) return;
          // 元の重なり順を保ったまま複製する
          for (const src of slide.elements.filter((e) => idset.has(e.id))) {
            const copy = structuredClone(src);
            copy.id = uid();
            copy.x += 24;
            copy.y += 24;
            newIds.push(copy.id);
            slide.elements.push(copy);
          }
        });
        if (newIds.length) set({ selectedElementId: newIds[newIds.length - 1], selectedElementIds: newIds });
      },

      reorderElement: (id, dir) => {
        const slideId = get().selectedSlideId;
        get().commit((deck) => {
          const slide = deck.slides.find((s) => s.id === slideId);
          if (!slide) return;
          const i = slide.elements.findIndex((e) => e.id === id);
          const j = i + dir;
          if (i < 0 || j < 0 || j >= slide.elements.length) return;
          const [e] = slide.elements.splice(i, 1);
          slide.elements.splice(j, 0, e);
        });
      },

      fxScanning: false,
      fxPopIds: [],
      setFxScanning: (v) => set({ fxScanning: v }),
      setFxPopIds: (ids) => set({ fxPopIds: ids }),

      updateTheme: (patch) =>
        get().commit((deck) => {
          deck.theme = {
            ...deck.theme,
            ...patch,
            colors: { ...deck.theme.colors, ...(patch.colors ?? {}) },
          };
        }),
    }),
    {
      name: STORAGE_KEY,
      partialize: (s) => ({ deck: s.deck, selectedSlideId: s.selectedSlideId }),
    },
  ),
);

export function useSelectedSlide(): Slide | undefined {
  return useEditor((s) => s.deck.slides.find((x) => x.id === s.selectedSlideId));
}
