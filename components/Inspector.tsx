"use client";

import React from "react";
import {
  BackgroundPreset,
  ColorKey,
  ColorValue,
  ImageEl,
  ShapeEl,
  TextEl,
  resolveColor,
  uid,
} from "@/lib/types";
import { useEditor, useSelectedSlide } from "@/lib/store";
import { PRESET_LABEL_KEYS, COLOR_LABEL_KEYS, useT } from "@/lib/i18n";



function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border-b border-neutral-200 px-4 py-3">
      <div className="mb-2 text-[11px] font-bold tracking-wider text-neutral-400">{title}</div>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex items-center justify-between gap-2 text-xs text-neutral-600">
      <span className="shrink-0">{label}</span>
      {children}
    </label>
  );
}

function NumInput({
  value,
  onChange,
  step = 1,
  width = "w-16",
}: {
  value: number;
  onChange: (n: number) => void;
  step?: number;
  width?: string;
}) {
  return (
    <input
      type="number"
      value={Math.round(value * 100) / 100}
      step={step}
      onChange={(e) => {
        const n = parseFloat(e.target.value);
        if (Number.isFinite(n)) onChange(n);
      }}
      className={`${width} rounded border border-neutral-300 px-1.5 py-1 text-right text-xs`}
    />
  );
}

export function ColorPicker({
  value,
  onChange,
}: {
  value: ColorValue;
  onChange: (v: ColorValue) => void;
}) {
  const t = useT();
  const theme = useEditor((s) => s.deck.theme);
  const keys = Object.keys(theme.colors) as ColorKey[];
  return (
    <div className="flex flex-wrap items-center gap-1">
      {keys.map((k) => (
        <button
          key={k}
          title={COLOR_LABEL_KEYS[k] ? t(COLOR_LABEL_KEYS[k]) : k}
          onClick={() => onChange(`token:${k}`)}
          className={`h-5 w-5 rounded-full border ${
            value === `token:${k}` ? "ring-2 ring-blue-500 ring-offset-1" : "border-neutral-300"
          }`}
          style={{ background: theme.colors[k] }}
        />
      ))}
      <input
        type="color"
        value={value.startsWith("token:") ? resolveColor(value, theme) : value}
        onChange={(e) => onChange(e.target.value)}
        className="h-6 w-7 cursor-pointer rounded border border-neutral-300 p-0"
        title={t("customColor")}
      />
    </div>
  );
}

export function Inspector() {
  const t = useT();
  const slide = useSelectedSlide();
  const deck = useEditor((s) => s.deck);
  const selectedElementId = useEditor((s) => s.selectedElementId);
  const updateElement = useEditor((s) => s.updateElement);
  const deleteElement = useEditor((s) => s.deleteElement);
  const duplicateElement = useEditor((s) => s.duplicateElement);
  const reorderElement = useEditor((s) => s.reorderElement);
  const commit = useEditor((s) => s.commit);
  const selectedSlideId = useEditor((s) => s.selectedSlideId);
  const [decomposing, setDecomposing] = React.useState(false);

  // 背景をAIで「動かせるモチーフ画像 + 無地背景」に分解する
  const decompose = async () => {
    if (!slide?.background.image || decomposing) return;
    setDecomposing(true);
    try {
      const res = await fetch("/api/decompose", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ src: slide.background.image }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `${t("decomposeFailed")} (${res.status})`);
      commit((d) => {
        const s = d.slides.find((x) => x.id === selectedSlideId);
        if (!s) return;
        s.background.image = data.background;
        // 各モチーフをテキストの背面に置く(elementsは先頭ほど背面)
        const motifs = (data.motifs ?? []) as { url: string; x: number; y: number; w: number; h: number }[];
        for (const m of motifs) {
          s.elements.unshift({
            id: uid(),
            type: "image",
            src: m.url,
            x: m.x,
            y: m.y,
            w: m.w,
            h: m.h,
            fit: "contain",
            name: "motif",
          });
        }
      });
    } catch (e) {
      alert(e instanceof Error ? e.message : t("decomposeFailed"));
    } finally {
      setDecomposing(false);
    }
  };

  if (!slide) return null;
  const el = slide.elements.find((e) => e.id === selectedElementId);

  const patchSlide = (fn: (s: NonNullable<typeof slide>) => void) =>
    commit((d) => {
      const target = d.slides.find((x) => x.id === selectedSlideId);
      if (target) fn(target);
    });

  return (
    <div className="flex h-full w-72 shrink-0 flex-col overflow-y-auto border-l border-neutral-200 bg-white">
      {!el ? (
        <>
          <div className="border-b border-neutral-200 px-4 py-3 text-sm font-bold">
            {t("slideSettings")}
          </div>
          <Section title={t("background")}>
            <Row label={t("baseColor")}>
              <ColorPicker
                value={slide.background.color}
                onChange={(v) => patchSlide((s) => (s.background.color = v))}
              />
            </Row>
            <Row label={t("decoration")}>
              <select
                value={slide.background.preset}
                onChange={(e) =>
                  patchSlide((s) => (s.background.preset = e.target.value as BackgroundPreset))
                }
                className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
              >
                {Object.entries(PRESET_LABEL_KEYS).map(([v, key]) => (
                  <option key={v} value={v}>
                    {t(key)}
                  </option>
                ))}
              </select>
            </Row>
            <Row label={t("bgImageUrl")}>
              <input
                type="text"
                placeholder="https://..."
                value={slide.background.image ?? ""}
                onChange={(e) =>
                  patchSlide((s) => (s.background.image = e.target.value || undefined))
                }
                className="w-36 rounded border border-neutral-300 px-1.5 py-1 text-xs"
              />
            </Row>
            {slide.background.image?.startsWith("/api/assets/") && (
              <Row label={t("aiEdit")}>
                <button
                  onClick={decompose}
                  disabled={decomposing}
                  title={t("decomposeTitle")}
                  className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
                >
                  {decomposing ? t("decomposing") : t("decompose")}
                </button>
              </Row>
            )}
          </Section>
          <Section title={t("slideName")}>
            <input
              type="text"
              value={slide.name}
              onChange={(e) => patchSlide((s) => (s.name = e.target.value))}
              className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            />
          </Section>
          <div className="px-4 py-3 text-xs leading-relaxed text-neutral-400">
            {t("editorHint")}
          </div>
        </>
      ) : (
        <>
          <div className="flex items-center justify-between border-b border-neutral-200 px-4 py-3">
            <div className="text-sm font-bold">
              {el.type === "text" ? t("textEl") : el.type === "shape" ? t("shapeEl") : t("imageEl")}
            </div>
            <div className="flex gap-1">
              <IconBtn title={t("toBack")} onClick={() => reorderElement(el.id, -1)}>▼</IconBtn>
              <IconBtn title={t("toFront")} onClick={() => reorderElement(el.id, 1)}>▲</IconBtn>
              <IconBtn title={t("duplicate")} onClick={() => duplicateElement(el.id)}>⧉</IconBtn>
              <IconBtn title={t("del")} danger onClick={() => deleteElement(el.id)}>🗑</IconBtn>
            </div>
          </div>

          <Section title={t("posSize")}>
            <div className="grid grid-cols-2 gap-2">
              <Row label="X"><NumInput value={el.x} onChange={(n) => updateElement(el.id, { x: n })} /></Row>
              <Row label="Y"><NumInput value={el.y} onChange={(n) => updateElement(el.id, { y: n })} /></Row>
              <Row label="W"><NumInput value={el.w} onChange={(n) => updateElement(el.id, { w: Math.max(8, n) })} /></Row>
              <Row label="H"><NumInput value={el.h} onChange={(n) => updateElement(el.id, { h: Math.max(4, n) })} /></Row>
            </div>
            <Row label={t("rotation")}>
              <NumInput value={el.rotation ?? 0} onChange={(n) => updateElement(el.id, { rotation: n })} />
            </Row>
            <Row label={t("opacity")}>
              <input
                type="range"
                min={0}
                max={1}
                step={0.05}
                value={el.opacity ?? 1}
                onChange={(e) => updateElement(el.id, { opacity: parseFloat(e.target.value) })}
              />
            </Row>
          </Section>

          {el.type === "text" && <TextInspector el={el} />}
          {el.type === "shape" && <ShapeInspector el={el} />}
          {el.type === "image" && <ImageInspector el={el} />}

          <Section title={t("hyperlink")}>
            <input
              type="text"
              placeholder="https://example.com"
              value={el.link?.startsWith("#") ? "" : (el.link ?? "")}
              onChange={(e) => updateElement(el.id, { link: e.target.value || undefined })}
              className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            />
            <Row label={t("internalLink")}>
              <select
                value={el.link?.startsWith("#") ? el.link : ""}
                onChange={(e) => updateElement(el.id, { link: e.target.value || undefined })}
                className="w-36 rounded border border-neutral-300 px-1.5 py-1 text-xs"
              >
                <option value="">{t("linkNone")}</option>
                {deck.slides.map((s, i) => (
                  <option key={s.id} value={`#${s.id}`}>
                    {i + 1}. {s.name}
                  </option>
                ))}
              </select>
            </Row>
            <div className="text-[11px] leading-relaxed text-neutral-400">
              {t("linkNote")}
            </div>
          </Section>
        </>
      )}
    </div>
  );
}

function IconBtn({
  children,
  onClick,
  title,
  danger,
}: {
  children: React.ReactNode;
  onClick: () => void;
  title: string;
  danger?: boolean;
}) {
  return (
    <button
      title={title}
      onClick={onClick}
      className={`rounded px-1.5 py-0.5 text-xs hover:bg-neutral-100 ${
        danger ? "text-red-500" : "text-neutral-600"
      }`}
    >
      {children}
    </button>
  );
}

function TextInspector({ el }: { el: TextEl }) {
  const t = useT();
  const updateElement = useEditor((s) => s.updateElement);
  const deck = useEditor((s) => s.deck);
  const [instruction, setInstruction] = React.useState("");
  const [rewriting, setRewriting] = React.useState(false);

  // この文言だけをAIで磨く/書き換える(レイアウトは維持)
  const rewrite = async () => {
    if (rewriting) return;
    setRewriting(true);
    try {
      const res = await fetch("/api/rewrite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: el.text,
          instruction: instruction.trim() || undefined,
          context: deck.title,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `${t("rewriteFailed")} (${res.status})`);
      updateElement(el.id, { text: data.text });
      setInstruction("");
    } catch (e) {
      alert(e instanceof Error ? e.message : t("rewriteFailed"));
    } finally {
      setRewriting(false);
    }
  };

  return (
    <>
      <Section title={t("textEl")}>
        <textarea
          value={el.text}
          rows={3}
          onChange={(e) => updateElement(el.id, { text: e.target.value })}
          className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <div className="flex gap-1">
          <input
            type="text"
            value={instruction}
            onChange={(e) => setInstruction(e.target.value)}
            placeholder={t("rewritePlaceholder")}
            className="min-w-0 flex-1 rounded border border-neutral-300 px-2 py-1 text-xs"
          />
          <button
            onClick={rewrite}
            disabled={rewriting}
            title={t("rewriteTitle")}
            className="shrink-0 rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
          >
            {rewriting ? "…" : "✦"}
          </button>
        </div>
      </Section>
      <Section title={t("typography")}>
        <div className="grid grid-cols-2 gap-2">
          <Row label={t("fontSize")}><NumInput value={el.fontSize} onChange={(n) => updateElement(el.id, { fontSize: Math.max(6, n) })} /></Row>
          <Row label={t("lineHeight")}><NumInput value={el.lineHeight} step={0.1} onChange={(n) => updateElement(el.id, { lineHeight: n })} /></Row>
        </div>
        <Row label={t("fontWeight")}>
          <select
            value={el.fontWeight}
            onChange={(e) => updateElement(el.id, { fontWeight: parseInt(e.target.value) })}
            className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
          >
            {[400, 500, 700, 800, 900].map((w) => (
              <option key={w} value={w}>{w}</option>
            ))}
          </select>
        </Row>
        <Row label={t("align")}>
          <div className="flex gap-1">
            {(["left", "center", "right"] as const).map((a) => (
              <button
                key={a}
                onClick={() => updateElement(el.id, { align: a })}
                className={`rounded border px-2 py-0.5 text-xs ${
                  el.align === a ? "border-blue-500 bg-blue-50 text-blue-600" : "border-neutral-300"
                }`}
              >
                {a === "left" ? t("alignLeft") : a === "center" ? t("alignCenter") : t("alignRight")}
              </button>
            ))}
          </div>
        </Row>
        <Row label={t("fontLabel")}>
          <select
            value={el.font ?? "body"}
            onChange={(e) => updateElement(el.id, { font: e.target.value as "heading" | "body" })}
            className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
          >
            <option value="heading">{t("fontHeading")}</option>
            <option value="body">{t("fontBody")}</option>
          </select>
        </Row>
        <Row label={t("colorLabel")}>
          <ColorPicker value={el.color} onChange={(v) => updateElement(el.id, { color: v })} />
        </Row>
      </Section>
    </>
  );
}

function ShapeInspector({ el }: { el: ShapeEl }) {
  const t = useT();
  const updateElement = useEditor((s) => s.updateElement);
  return (
    <Section title={t("shapeEl")}>
      <Row label={t("shapeKind")}>
        <select
          value={el.shape}
          onChange={(e) => updateElement(el.id, { shape: e.target.value as ShapeEl["shape"] })}
          className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
        >
          <option value="rect">{t("shapeRect")}</option>
          <option value="ellipse">{t("shapeEllipse")}</option>
          <option value="line">{t("shapeLine")}</option>
        </select>
      </Row>
      <Row label={t("fill")}>
        <ColorPicker value={el.fill} onChange={(v) => updateElement(el.id, { fill: v })} />
      </Row>
      {el.shape === "rect" && (
        <Row label={t("cornerRadius")}>
          <NumInput value={el.radius ?? 0} onChange={(n) => updateElement(el.id, { radius: Math.max(0, n) })} />
        </Row>
      )}
      <Row label={t("strokeColor")}>
        <ColorPicker value={el.stroke ?? "token:line"} onChange={(v) => updateElement(el.id, { stroke: v })} />
      </Row>
      <Row label={t("strokeWidth")}>
        <NumInput value={el.strokeWidth ?? 0} onChange={(n) => updateElement(el.id, { strokeWidth: Math.max(0, n) })} />
      </Row>
    </Section>
  );
}

function ImageInspector({ el }: { el: ImageEl }) {
  const t = useT();
  const updateElement = useEditor((s) => s.updateElement);
  const [cutting, setCutting] = React.useState(false);
  const [remakeInstruction, setRemakeInstruction] = React.useState("");
  const [remaking, setRemaking] = React.useState(false);

  // この画像だけをAIで作り直す(位置・サイズは維持)
  const remake = async () => {
    if (remaking || !remakeInstruction.trim()) return;
    setRemaking(true);
    try {
      const res = await fetch("/api/generate/image", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: remakeInstruction,
          // 切り抜きパーツ(contain)は透過で、写真スロット(cover)は不透過で作る
          transparent: el.fit === "contain",
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `${t("remakeImgFailed")} (${res.status})`);
      updateElement(el.id, { src: data.url });
      setRemakeInstruction("");
    } catch (e) {
      alert(e instanceof Error ? e.message : t("remakeImgFailed"));
    } finally {
      setRemaking(false);
    }
  };

  // AIで被写体を切り抜き、透過PNGに差し替える(アセット画像のみ)
  const removeBackground = async () => {
    if (cutting) return;
    setCutting(true);
    try {
      const res = await fetch("/api/edit-image", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ src: el.src }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `${t("removeBgFailed")} (${res.status})`);
      updateElement(el.id, { src: data.url, fit: "contain" });
    } catch (e) {
      alert(e instanceof Error ? e.message : t("removeBgFailed"));
    } finally {
      setCutting(false);
    }
  };

  return (
    <Section title={t("imageEl")}>
      <Row label={t("imageUrl")}>
        <input
          type="text"
          value={el.src}
          onChange={(e) => updateElement(el.id, { src: e.target.value })}
          className="w-36 rounded border border-neutral-300 px-1.5 py-1 text-xs"
        />
      </Row>
      {el.src.startsWith("/api/assets/") && (
        <Row label="AI編集">
          <button
            onClick={removeBackground}
            disabled={cutting}
            title={t("removeBgTitle")}
            className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
          >
            {cutting ? t("cutting") : t("removeBg")}
          </button>
        </Row>
      )}
      <div className="flex gap-1">
        <input
          type="text"
          value={remakeInstruction}
          onChange={(e) => setRemakeInstruction(e.target.value)}
          placeholder={t("remakePlaceholder")}
          className="min-w-0 flex-1 rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <button
          onClick={remake}
          disabled={remaking || !remakeInstruction.trim()}
          title={t("remakeImgTitle")}
          className="shrink-0 rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
        >
          {remaking ? "…" : "✦"}
        </button>
      </div>
      <Row label={t("fit")}>
        <select
          value={el.fit}
          onChange={(e) => updateElement(el.id, { fit: e.target.value as "cover" | "contain" })}
          className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
        >
          <option value="cover">{t("fitCover")}</option>
          <option value="contain">{t("fitContain")}</option>
        </select>
      </Row>
      <Row label="角丸">
        <NumInput value={el.radius ?? 0} onChange={(n) => updateElement(el.id, { radius: Math.max(0, n) })} />
      </Row>
    </Section>
  );
}
