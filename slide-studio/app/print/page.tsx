"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { Deck } from "@/lib/types";
import { normalizeDeck } from "@/lib/normalize";
import { STORAGE_KEY } from "@/lib/store";
import { SlideRenderer } from "@/components/SlideRenderer";

// サーバーサイドPDF書き出し時はヘッドレスブラウザが ?deck=<id> 付きで開く
function exportDeckId(): string | null {
  return new URLSearchParams(window.location.search).get("deck");
}

// localStorageのデッキをuseSyncExternalStoreで読む(effect内setStateを避ける)。
// スナップショットは同一性が要求されるため、raw文字列単位でキャッシュする
const subscribeStorage = (onChange: () => void) => {
  window.addEventListener("storage", onChange);
  return () => window.removeEventListener("storage", onChange);
};
let deckCache: { raw: string | null; deck: Deck | null } | null = null;
function readDeckSnapshot(): Deck | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (deckCache && deckCache.raw === raw) return deckCache.deck;
  let deck: Deck | null = null;
  if (raw) {
    try {
      deck = normalizeDeck(JSON.parse(raw)?.state?.deck);
    } catch {
      deck = null;
    }
  }
  deckCache = { raw, deck };
  return deck;
}

// 印刷ビュー: 全スライドを1280x720の実寸ページとして縦に並べる。
// ブラウザの「印刷 → PDFに保存」でリンク付き・ベクターテキストのPDFになる。
export default function PrintPage() {
  const storedDeck = useSyncExternalStore(subscribeStorage, readDeckSnapshot, () => null);
  const hydrated = useSyncExternalStore(subscribeStorage, () => true, () => false);
  const exportMode = useSyncExternalStore(
    subscribeStorage,
    () => !!exportDeckId(),
    () => false,
  );
  const [fetchedDeck, setFetchedDeck] = useState<Deck | null>(null);

  // サーバーサイド書き出し時はlocalStorageではなく一時APIからデッキを取得する
  useEffect(() => {
    const id = exportDeckId();
    if (!id) return;
    fetch(`/api/export/deck/${id}`)
      .then((r) => r.json())
      .then((d) => setFetchedDeck(normalizeDeck(d)))
      .catch(() => {});
  }, []);

  const deck = fetchedDeck ?? (exportMode ? null : storedDeck);
  const error = hydrated && !exportMode && !deck;

  useEffect(() => {
    if (!deck || exportDeckId()) return; // 書き出しモードではダイアログを開かない
    // Webフォント読み込み完了後に印刷ダイアログを開く
    const t = setTimeout(() => {
      if (document.fonts?.ready) {
        document.fonts.ready.then(() => setTimeout(() => window.print(), 300));
      } else {
        window.print();
      }
    }, 400);
    return () => clearTimeout(t);
  }, [deck]);

  if (error) {
    return (
      <div className="flex h-screen items-center justify-center text-sm text-neutral-500">
        デッキが見つかりません。エディタで作成してから再度開いてください。
      </div>
    );
  }
  if (!deck) return null;

  return (
    <div style={{ background: "#fff" }}>
      <div className="no-print fixed right-4 top-4 z-50 flex gap-2">
        <button
          onClick={() => window.print()}
          className="rounded-lg bg-neutral-900 px-4 py-2 text-sm font-bold text-white shadow-lg"
        >
          印刷 / PDFに保存
        </button>
        <button
          onClick={() => window.close()}
          className="rounded-lg bg-white px-4 py-2 text-sm text-neutral-600 shadow-lg"
        >
          閉じる
        </button>
      </div>
      <div className="no-print bg-amber-50 px-6 py-3 text-xs text-amber-700">
        印刷ダイアログで「送信先: PDFに保存」「余白: なし」「背景のグラフィック: ON」を選択してください。ハイパーリンク(外部・ページ内)はPDFに保持されます。
      </div>
      {deck.slides.map((slide) => (
        <div key={slide.id} id={slide.id} className="print-slide" style={{ width: 1280, height: 720 }}>
          <SlideRenderer slide={slide} theme={deck.theme} withLinks />
        </div>
      ))}
    </div>
  );
}
