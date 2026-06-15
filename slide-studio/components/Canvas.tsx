"use client";

import React, { useCallback, useEffect, useRef, useState } from "react";
import { SLIDE_H, SLIDE_W, SlideElement, clamp } from "@/lib/types";
import { useEditor, useSelectedSlide } from "@/lib/store";
import { ElementContent, elementStyle } from "./SlideRenderer";
import { PresetBackground } from "./PresetBackground";
import { imageElementFor, uploadImageFile } from "@/lib/upload";

type Handle = "nw" | "n" | "ne" | "e" | "se" | "s" | "sw" | "w";
const HANDLES: Handle[] = ["nw", "n", "ne", "e", "se", "s", "sw", "w"];

interface DragState {
  mode: "move" | Handle;
  elId: string; // つかんだ要素(スナップ・リサイズの基準)
  startX: number; // pointer (slide coords)
  startY: number;
  orig: { x: number; y: number; w: number; h: number };
  // 複数選択時のグループ移動用: 選択中の全要素の開始位置
  group: { id: string; x: number; y: number }[];
  moved: boolean;
}

// 背景ドラッグでの範囲選択(ラバーバンド)
interface MarqueeState {
  startX: number;
  startY: number;
  additive: boolean; // Shift/Cmd併用で既存選択に追加
  moved: boolean;
}

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Guides {
  v: number | null;
  h: number | null;
}

function rectsIntersect(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

const SNAP = 8;
const V_TARGETS = [0, 80, SLIDE_W / 2, SLIDE_W - 80, SLIDE_W];
const H_TARGETS = [0, 60, SLIDE_H / 2, SLIDE_H - 60, SLIDE_H];

export function Canvas() {
  const slide = useSelectedSlide();
  const theme = useEditor((s) => s.deck.theme);
  const selectedElementId = useEditor((s) => s.selectedElementId);
  const selectedElementIds = useEditor((s) => s.selectedElementIds);
  const editingElementId = useEditor((s) => s.editingElementId);
  const select = useEditor((s) => s.select);
  const toggleSelect = useEditor((s) => s.toggleSelect);
  const selectMany = useEditor((s) => s.selectMany);
  const setEditing = useEditor((s) => s.setEditing);
  const beginTransient = useEditor((s) => s.beginTransient);
  const transient = useEditor((s) => s.transient);
  const commit = useEditor((s) => s.commit);
  const addElement = useEditor((s) => s.addElement);
  const fxScanning = useEditor((s) => s.fxScanning);
  const fxPopIds = useEditor((s) => s.fxPopIds);
  const selectedSlideId = useEditor((s) => s.selectedSlideId);

  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.5);
  const dragRef = useRef<DragState | null>(null);
  const marqueeRef = useRef<MarqueeState | null>(null);
  const [marquee, setMarquee] = useState<Rect | null>(null);
  const [guides, setGuides] = useState<Guides>({ v: null, h: null });

  useEffect(() => {
    const node = containerRef.current;
    if (!node) return;
    const update = () => {
      const rect = node.getBoundingClientRect();
      const s = Math.min((rect.width - 48) / SLIDE_W, (rect.height - 48) / SLIDE_H);
      setScale(Math.max(0.1, s));
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(node);
    return () => ro.disconnect();
  }, []);

  const toSlideCoords = useCallback(
    (e: React.PointerEvent | PointerEvent) => {
      const stage = document.getElementById("slide-stage");
      if (!stage) return { x: 0, y: 0 };
      const rect = stage.getBoundingClientRect();
      return {
        x: (e.clientX - rect.left) / scale,
        y: (e.clientY - rect.top) / scale,
      };
    },
    [scale],
  );

  // 選択中の全要素の開始位置を集めてグループ移動の素にする
  const groupOrigFor = (ids: string[]) =>
    (slide?.elements ?? [])
      .filter((e) => ids.includes(e.id))
      .map((e) => ({ id: e.id, x: e.x, y: e.y }));

  const onElementPointerDown = (e: React.PointerEvent, el: SlideElement) => {
    if (editingElementId === el.id) return; // テキスト編集中はドラッグしない
    e.stopPropagation();

    // Cmd/Ctrl/Shift + クリックは選択集合への追加/解除のみ(ドラッグしない)
    if (e.metaKey || e.ctrlKey || e.shiftKey) {
      toggleSelect(selectedSlideId, el.id);
      return;
    }

    // すでに複数選択に含まれている要素をつかんだらグループごと動かす。
    // そうでなければその要素だけを選択して動かす
    const alreadyInGroup = selectedElementIds.length > 1 && selectedElementIds.includes(el.id);
    const ids = alreadyInGroup ? selectedElementIds : [el.id];
    if (!alreadyInGroup) select(selectedSlideId, el.id);

    const p = toSlideCoords(e);
    dragRef.current = {
      mode: "move",
      elId: el.id,
      startX: p.x,
      startY: p.y,
      orig: { x: el.x, y: el.y, w: el.w, h: el.h },
      group: groupOrigFor(ids),
      moved: false,
    };
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  };

  const onHandlePointerDown = (e: React.PointerEvent, el: SlideElement, handle: Handle) => {
    e.stopPropagation();
    const p = toSlideCoords(e);
    dragRef.current = {
      mode: handle,
      elId: el.id,
      startX: p.x,
      startY: p.y,
      orig: { x: el.x, y: el.y, w: el.w, h: el.h },
      group: [],
      moved: false,
    };
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  };

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      // 範囲選択(背景ドラッグ)中
      const mq = marqueeRef.current;
      if (mq && !dragRef.current) {
        const p = toSlideCoords(e);
        if (!mq.moved && Math.abs(p.x - mq.startX) < 3 && Math.abs(p.y - mq.startY) < 3) return;
        mq.moved = true;
        setMarquee({
          x: Math.min(mq.startX, p.x),
          y: Math.min(mq.startY, p.y),
          w: Math.abs(p.x - mq.startX),
          h: Math.abs(p.y - mq.startY),
        });
        return;
      }

      const drag = dragRef.current;
      if (!drag) return;
      const p = toSlideCoords(e);
      let dx = p.x - drag.startX;
      let dy = p.y - drag.startY;
      if (!drag.moved && Math.abs(dx) < 2 && Math.abs(dy) < 2) return;
      if (!drag.moved) {
        beginTransient();
        drag.moved = true;
      }
      const { orig } = drag;
      const g: Guides = { v: null, h: null };

      if (drag.mode === "move") {
        let nx = orig.x + dx;
        let ny = orig.y + dy;
        // スナップ: つかんだ要素の 左端/中央/右端 を候補ラインに合わせる
        for (const t of V_TARGETS) {
          if (Math.abs(nx - t) < SNAP) { nx = t; g.v = t; break; }
          if (Math.abs(nx + orig.w / 2 - t) < SNAP) { nx = t - orig.w / 2; g.v = t; break; }
          if (Math.abs(nx + orig.w - t) < SNAP) { nx = t - orig.w; g.v = t; break; }
        }
        for (const t of H_TARGETS) {
          if (Math.abs(ny - t) < SNAP) { ny = t; g.h = t; break; }
          if (Math.abs(ny + orig.h / 2 - t) < SNAP) { ny = t - orig.h / 2; g.h = t; break; }
          if (Math.abs(ny + orig.h - t) < SNAP) { ny = t - orig.h; g.h = t; break; }
        }
        setGuides(g);
        // スナップ後の実移動量を全選択要素へ適用(グループ移動)
        const mdx = Math.round(nx - orig.x);
        const mdy = Math.round(ny - orig.y);
        transient((deck) => {
          const els = deck.slides.find((s) => s.id === selectedSlideId)?.elements;
          if (!els) return;
          const group = drag.group.length ? drag.group : [{ id: drag.elId, x: orig.x, y: orig.y }];
          for (const go of group) {
            const el = els.find((x) => x.id === go.id);
            if (el) {
              el.x = go.x + mdx;
              el.y = go.y + mdy;
            }
          }
        });
      } else {
        const m = drag.mode;
        let { x, y, w, h } = orig;
        if (m.includes("e")) w = Math.max(16, orig.w + dx);
        if (m.includes("s")) h = Math.max(12, orig.h + dy);
        if (m.includes("w")) {
          dx = clamp(dx, -10000, orig.w - 16);
          x = orig.x + dx;
          w = orig.w - dx;
        }
        if (m.includes("n")) {
          dy = clamp(dy, -10000, orig.h - 12);
          y = orig.y + dy;
          h = orig.h - dy;
        }
        setGuides({ v: null, h: null });
        transient((deck) => {
          const el = deck.slides
            .find((s) => s.id === selectedSlideId)
            ?.elements.find((el2) => el2.id === drag.elId);
          if (el) {
            el.x = Math.round(x);
            el.y = Math.round(y);
            el.w = Math.round(w);
            el.h = Math.round(h);
          }
        });
      }
    };
    const onUp = () => {
      dragRef.current = null;
      setGuides({ v: null, h: null });
      // 範囲選択の確定
      const mq = marqueeRef.current;
      marqueeRef.current = null;
      if (mq?.moved && marquee) {
        const hit = (slide?.elements ?? [])
          .filter((el) => rectsIntersect(marquee, { x: el.x, y: el.y, w: el.w, h: el.h }))
          .map((el) => el.id);
        if (mq.additive) {
          const merged = Array.from(new Set([...selectedElementIds, ...hit]));
          selectMany(selectedSlideId, merged);
        } else {
          selectMany(selectedSlideId, hit);
        }
      } else if (mq && !mq.moved && !mq.additive) {
        // 背景の素のクリックは選択解除
        select(selectedSlideId, null);
      }
      setMarquee(null);
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };
  }, [
    toSlideCoords,
    transient,
    beginTransient,
    selectedSlideId,
    selectedElementIds,
    selectMany,
    select,
    slide,
    marquee,
  ]);

  const finishTextEdit = (el: SlideElement, node: HTMLElement) => {
    const value = node.innerText.replace(/\n$/, "");
    // contentEditableはスケール済みコンテナ内にあるためscrollHeightはスライド座標系
    const contentH = Math.ceil(node.scrollHeight);
    setEditing(null);
    if (el.type === "text" && (value !== el.text || contentH > el.h)) {
      commit((deck) => {
        const target = deck.slides
          .find((s) => s.id === selectedSlideId)
          ?.elements.find((x) => x.id === el.id);
        if (target && target.type === "text") {
          target.text = value;
          // 文字が増えて箱からあふれたら高さを内容に合わせて伸ばす
          if (contentH > target.h) target.h = contentH;
        }
      });
    }
  };

  // 画像ファイルのドラッグ&ドロップ配置
  const onDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    const files = Array.from(e.dataTransfer.files).filter((f) => f.type.startsWith("image/"));
    if (files.length === 0) return;
    try {
      const avoid = slide?.elements ?? [];
      for (let i = 0; i < files.length; i++) {
        const { url, width, height } = await uploadImageFile(files[i]);
        addElement(imageElementFor(url, width, height, i, avoid));
      }
    } catch (err) {
      alert(err instanceof Error ? err.message : "アップロードに失敗しました");
    }
  };

  if (!slide) return null;

  const selected = slide.elements.find((e) => e.id === selectedElementId);

  return (
    <div
      ref={containerRef}
      className="relative flex h-full w-full items-center justify-center overflow-hidden bg-neutral-200"
      onPointerDown={(e) => {
        // 背景でのpointerdownは範囲選択の開始(クリックなら離した時に選択解除)
        const p = toSlideCoords(e);
        marqueeRef.current = {
          startX: p.x,
          startY: p.y,
          additive: e.shiftKey || e.metaKey || e.ctrlKey,
          moved: false,
        };
      }}
      onDragOver={(e) => e.preventDefault()}
      onDrop={onDrop}
    >
      <div
        id="slide-stage"
        className="relative shadow-2xl"
        style={{ width: SLIDE_W * scale, height: SLIDE_H * scale }}
      >
        <div
          style={{
            transform: `scale(${scale})`,
            transformOrigin: "top left",
            width: SLIDE_W,
            height: SLIDE_H,
            position: "relative",
            overflow: "hidden",
            fontFamily: theme.bodyFont,
          }}
        >
          <PresetBackground background={slide.background} theme={theme} />

          {slide.elements.map((el) => {
            const isEditing = editingElementId === el.id;
            return (
              <div
                key={el.id}
                className={fxPopIds.includes(el.id) ? "cd-pop" : undefined}
                style={{
                  ...elementStyle(el),
                  animationDelay: fxPopIds.includes(el.id)
                    ? `${fxPopIds.indexOf(el.id) * 90}ms`
                    : undefined,
                  cursor: isEditing ? "text" : "move",
                  outline: selectedElementIds.includes(el.id)
                    ? selectedElementId === el.id
                      ? "1.5px solid #2b7fff"
                      : "1.5px solid #7db1ff" // 副選択は淡い青
                    : undefined,
                  outlineOffset: 0,
                }}
                onPointerDown={(e) => onElementPointerDown(e, el)}
                onDoubleClick={(e) => {
                  e.stopPropagation();
                  if (el.type === "text") setEditing(el.id);
                }}
              >
                {isEditing && el.type === "text" ? (
                  <div
                    contentEditable
                    suppressContentEditableWarning
                    ref={(node) => {
                      if (node) {
                        node.focus();
                        // キャレットを末尾へ
                        const range = document.createRange();
                        range.selectNodeContents(node);
                        range.collapse(false);
                        const sel = window.getSelection();
                        sel?.removeAllRanges();
                        sel?.addRange(range);
                      }
                    }}
                    onBlur={(e) => finishTextEdit(el, e.currentTarget)}
                    onKeyDown={(e) => {
                      if (e.key === "Escape") (e.currentTarget as HTMLElement).blur();
                      e.stopPropagation();
                    }}
                    style={{
                      width: "100%",
                      minHeight: "100%",
                      fontSize: el.fontSize,
                      fontWeight: el.fontWeight,
                      color: undefined,
                      textAlign: el.align,
                      lineHeight: el.lineHeight,
                      letterSpacing: el.letterSpacing,
                      fontFamily:
                        el.font === "heading" ? theme.headingFont : theme.bodyFont,
                      whiteSpace: "pre-wrap",
                      overflowWrap: "break-word",
                      outline: "1.5px dashed #2b7fff",
                      background: "rgba(43,127,255,0.04)",
                    }}
                  >
                    <EditableText text={el.text} />
                  </div>
                ) : (
                  <ElementContent el={el} theme={theme} />
                )}
              </div>
            );
          })}

          {/* 分解中のスキャン演出 */}
          {fxScanning && (
            <div className="pointer-events-none absolute inset-0 overflow-hidden">
              <div className="cd-scan-beam" />
            </div>
          )}

          {/* スナップガイド */}
          {guides.v !== null && (
            <div
              className="pointer-events-none absolute"
              style={{ left: guides.v, top: 0, width: 1, height: SLIDE_H, background: "#ff4d8d" }}
            />
          )}
          {guides.h !== null && (
            <div
              className="pointer-events-none absolute"
              style={{ top: guides.h, left: 0, height: 1, width: SLIDE_W, background: "#ff4d8d" }}
            />
          )}

          {/* 範囲選択の矩形 */}
          {marquee && (
            <div
              className="pointer-events-none absolute"
              style={{
                left: marquee.x,
                top: marquee.y,
                width: marquee.w,
                height: marquee.h,
                border: "1px solid #2b7fff",
                background: "rgba(43,127,255,0.08)",
              }}
            />
          )}
        </div>

        {/* リサイズハンドル(単一選択時のみ。スケール外に置いて常に同サイズ) */}
        {selected && selectedElementIds.length === 1 && editingElementId !== selected.id && (
          <>
            {HANDLES.map((h) => {
              const cx =
                h.includes("w") ? selected.x : h.includes("e") ? selected.x + selected.w : selected.x + selected.w / 2;
              const cy =
                h.includes("n") ? selected.y : h.includes("s") ? selected.y + selected.h : selected.y + selected.h / 2;
              const cursor: Record<Handle, string> = {
                nw: "nwse-resize", se: "nwse-resize",
                ne: "nesw-resize", sw: "nesw-resize",
                n: "ns-resize", s: "ns-resize",
                e: "ew-resize", w: "ew-resize",
              };
              return (
                <div
                  key={h}
                  onPointerDown={(e) => onHandlePointerDown(e, selected, h)}
                  className="absolute z-10 rounded-full border border-blue-500 bg-white shadow"
                  style={{
                    width: 10,
                    height: 10,
                    left: cx * scale - 5,
                    top: cy * scale - 5,
                    cursor: cursor[h],
                  }}
                />
              );
            })}
          </>
        )}
      </div>
    </div>
  );
}

// contentEditable の初期値を一度だけ描画する(再レンダーでキャレットが飛ばないように)
const EditableText = React.memo(
  function EditableText({ text }: { text: string }) {
    return <>{text}</>;
  },
  () => true,
);
