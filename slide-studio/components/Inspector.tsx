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
import { COLOR_LABELS } from "@/lib/theme";

const PRESET_LABELS: Record<BackgroundPreset, string> = {
  none: "なし",
  mesh: "メッシュ",
  blobs: "ブロブ",
  diagonal: "斜めライン",
  grid: "グリッド",
  waves: "波",
  dots: "ドット",
  frame: "フレーム",
  rings: "リング",
  stripes: "ストライプ",
  corner: "コーナー",
  sparkle: "スパークル",
};

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
  const theme = useEditor((s) => s.deck.theme);
  const keys = Object.keys(theme.colors) as ColorKey[];
  return (
    <div className="flex flex-wrap items-center gap-1">
      {keys.map((k) => (
        <button
          key={k}
          title={COLOR_LABELS[k] ?? k}
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
        title="カスタム色"
      />
    </div>
  );
}

export function Inspector() {
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
  const setFxScanning = useEditor((s) => s.setFxScanning);
  const setFxPopIds = useEditor((s) => s.setFxPopIds);
  const select = useEditor((s) => s.select);

  // 背景をAIで「動かせるモチーフ画像 + 無地背景」に分解する
  const decompose = async () => {
    if (!slide?.background.image || decomposing) return;
    setDecomposing(true);
    setFxScanning(true);
    try {
      const res = await fetch("/api/decompose", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ src: slide.background.image, lang: "ja" }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `分解に失敗しました (${res.status})`);
      const motifs = (data.motifs ?? []) as {
        url: string; x: number; y: number; w: number; h: number; name?: string;
      }[];
      const newEls = motifs.map((m) => ({
        id: uid(),
        type: "image" as const,
        src: m.url,
        x: m.x,
        y: m.y,
        w: m.w,
        h: m.h,
        fit: "contain" as const,
        name: m.name || "motif",
      }));
      commit((d) => {
        const s = d.slides.find((x) => x.id === selectedSlideId);
        if (!s) return;
        s.background.image = data.background;
        // 背面(配列の先頭ほど背面)にdepth順で積む。テキストは常にレイヤーの前面
        s.elements = [...newEls, ...s.elements];
      });
      // ピール演出: 背面から順にポップイン
      setFxPopIds(newEls.map((e) => e.id));
      setTimeout(() => setFxPopIds([]), newEls.length * 90 + 900);
    } catch (e) {
      alert(e instanceof Error ? e.message : "分解に失敗しました");
    } finally {
      setDecomposing(false);
      setFxScanning(false);
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
            スライド設定
          </div>
          <Section title="背景">
            <Row label="ベース色">
              <ColorPicker
                value={slide.background.color}
                onChange={(v) => patchSlide((s) => (s.background.color = v))}
              />
            </Row>
            <Row label="装飾">
              <select
                value={slide.background.preset}
                onChange={(e) =>
                  patchSlide((s) => (s.background.preset = e.target.value as BackgroundPreset))
                }
                className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
              >
                {Object.entries(PRESET_LABELS).map(([v, label]) => (
                  <option key={v} value={v}>
                    {label}
                  </option>
                ))}
              </select>
            </Row>
            <Row label="背景画像URL">
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
              <Row label="AI編集">
                <button
                  onClick={decompose}
                  disabled={decomposing}
                  title="背景をオブジェクト単位の編集可能なレイヤーに分解します(2〜3分)"
                  className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
                >
                  {decomposing ? "分解中…" : "✦ レイヤーに分解"}
                </button>
              </Row>
            )}
          </Section>
          <Section title="スライド名">
            <input
              type="text"
              value={slide.name}
              onChange={(e) => patchSlide((s) => (s.name = e.target.value))}
              className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            />
          </Section>
          {slide.elements.length > 0 && (
            <Section title="レイヤー">
              <div className="max-h-56 space-y-0.5 overflow-y-auto">
                {[...slide.elements].reverse().map((e) => (
                  <button
                    key={e.id}
                    onClick={() => select(selectedSlideId, e.id)}
                    className="flex w-full items-center gap-2 rounded px-1.5 py-1 text-left text-xs text-neutral-700 hover:bg-neutral-100"
                  >
                    <span className="w-4 shrink-0 text-center text-[10px] text-neutral-400">
                      {e.type === "text" ? "T" : e.type === "image" ? "🖼" : "◆"}
                    </span>
                    <span className="min-w-0 flex-1 truncate">
                      {e.type === "text" ? e.text.slice(0, 24) : e.name || (e.type === "image" ? "画像" : "図形")}
                    </span>
                  </button>
                ))}
              </div>
            </Section>
          )}
          <div className="px-4 py-3 text-xs leading-relaxed text-neutral-400">
            要素をクリックすると詳細を編集できます。ダブルクリックでテキストを直接編集、ドラッグで移動できます。
          </div>
        </>
      ) : (
        <>
          <div className="flex items-center justify-between border-b border-neutral-200 px-4 py-3">
            <div className="text-sm font-bold">
              {el.type === "text" ? "テキスト" : el.type === "shape" ? "図形" : "画像"}
            </div>
            <div className="flex gap-1">
              <IconBtn title="背面へ" onClick={() => reorderElement(el.id, -1)}>▼</IconBtn>
              <IconBtn title="前面へ" onClick={() => reorderElement(el.id, 1)}>▲</IconBtn>
              <IconBtn title="複製" onClick={() => duplicateElement(el.id)}>⧉</IconBtn>
              <IconBtn title="削除" danger onClick={() => deleteElement(el.id)}>🗑</IconBtn>
            </div>
          </div>

          <Section title="位置とサイズ">
            <div className="grid grid-cols-2 gap-2">
              <Row label="X"><NumInput value={el.x} onChange={(n) => updateElement(el.id, { x: n })} /></Row>
              <Row label="Y"><NumInput value={el.y} onChange={(n) => updateElement(el.id, { y: n })} /></Row>
              <Row label="W"><NumInput value={el.w} onChange={(n) => updateElement(el.id, { w: Math.max(8, n) })} /></Row>
              <Row label="H"><NumInput value={el.h} onChange={(n) => updateElement(el.id, { h: Math.max(4, n) })} /></Row>
            </div>
            <Row label="回転">
              <NumInput value={el.rotation ?? 0} onChange={(n) => updateElement(el.id, { rotation: n })} />
            </Row>
            <Row label="不透明度">
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

          <Section title="ハイパーリンク">
            <input
              type="text"
              placeholder="https://example.com"
              value={el.link?.startsWith("#") ? "" : (el.link ?? "")}
              onChange={(e) => updateElement(el.id, { link: e.target.value || undefined })}
              className="w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            />
            <Row label="内部リンク">
              <select
                value={el.link?.startsWith("#") ? el.link : ""}
                onChange={(e) => updateElement(el.id, { link: e.target.value || undefined })}
                className="w-36 rounded border border-neutral-300 px-1.5 py-1 text-xs"
              >
                <option value="">なし</option>
                {deck.slides.map((s, i) => (
                  <option key={s.id} value={`#${s.id}`}>
                    {i + 1}. {s.name}
                  </option>
                ))}
              </select>
            </Row>
            <div className="text-[11px] leading-relaxed text-neutral-400">
              リンクはPDF書き出し時にも保持されます。
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
      if (!res.ok) throw new Error(data.error ?? `書き換えに失敗しました (${res.status})`);
      updateElement(el.id, { text: data.text });
      setInstruction("");
    } catch (e) {
      alert(e instanceof Error ? e.message : "書き換えに失敗しました");
    } finally {
      setRewriting(false);
    }
  };

  return (
    <>
      <Section title="テキスト">
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
            placeholder="AIへの指示(空なら磨くだけ)"
            className="min-w-0 flex-1 rounded border border-neutral-300 px-2 py-1 text-xs"
          />
          <button
            onClick={rewrite}
            disabled={rewriting}
            title="この文言だけをAIで書き直します(文字数は同程度に保たれます)"
            className="shrink-0 rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
          >
            {rewriting ? "…" : "✦"}
          </button>
        </div>
      </Section>
      <Section title="タイポグラフィ">
        <div className="grid grid-cols-2 gap-2">
          <Row label="サイズ"><NumInput value={el.fontSize} onChange={(n) => updateElement(el.id, { fontSize: Math.max(6, n) })} /></Row>
          <Row label="行間"><NumInput value={el.lineHeight} step={0.1} onChange={(n) => updateElement(el.id, { lineHeight: n })} /></Row>
        </div>
        <Row label="太さ">
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
        <Row label="揃え">
          <div className="flex gap-1">
            {(["left", "center", "right"] as const).map((a) => (
              <button
                key={a}
                onClick={() => updateElement(el.id, { align: a })}
                className={`rounded border px-2 py-0.5 text-xs ${
                  el.align === a ? "border-blue-500 bg-blue-50 text-blue-600" : "border-neutral-300"
                }`}
              >
                {a === "left" ? "左" : a === "center" ? "中" : "右"}
              </button>
            ))}
          </div>
        </Row>
        <Row label="フォント">
          <select
            value={el.font ?? "body"}
            onChange={(e) => updateElement(el.id, { font: e.target.value as "heading" | "body" })}
            className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
          >
            <option value="heading">見出し用</option>
            <option value="body">本文用</option>
          </select>
        </Row>
        <Row label="色">
          <ColorPicker value={el.color} onChange={(v) => updateElement(el.id, { color: v })} />
        </Row>
      </Section>
    </>
  );
}

function ShapeInspector({ el }: { el: ShapeEl }) {
  const updateElement = useEditor((s) => s.updateElement);
  return (
    <Section title="図形">
      <Row label="種類">
        <select
          value={el.shape}
          onChange={(e) => updateElement(el.id, { shape: e.target.value as ShapeEl["shape"] })}
          className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
        >
          <option value="rect">四角形</option>
          <option value="ellipse">円</option>
          <option value="line">線</option>
        </select>
      </Row>
      <Row label="塗り">
        <ColorPicker value={el.fill} onChange={(v) => updateElement(el.id, { fill: v })} />
      </Row>
      {el.shape === "rect" && (
        <Row label="角丸">
          <NumInput value={el.radius ?? 0} onChange={(n) => updateElement(el.id, { radius: Math.max(0, n) })} />
        </Row>
      )}
      <Row label="枠線色">
        <ColorPicker value={el.stroke ?? "token:line"} onChange={(v) => updateElement(el.id, { stroke: v })} />
      </Row>
      <Row label="枠線幅">
        <NumInput value={el.strokeWidth ?? 0} onChange={(n) => updateElement(el.id, { strokeWidth: Math.max(0, n) })} />
      </Row>
    </Section>
  );
}

function ImageInspector({ el }: { el: ImageEl }) {
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
      if (!res.ok) throw new Error(data.error ?? `作り直しに失敗しました (${res.status})`);
      updateElement(el.id, { src: data.url });
      setRemakeInstruction("");
    } catch (e) {
      alert(e instanceof Error ? e.message : "作り直しに失敗しました");
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
      if (!res.ok) throw new Error(data.error ?? `切り抜きに失敗しました (${res.status})`);
      updateElement(el.id, { src: data.url, fit: "contain" });
    } catch (e) {
      alert(e instanceof Error ? e.message : "切り抜きに失敗しました");
    } finally {
      setCutting(false);
    }
  };

  return (
    <Section title="画像">
      <Row label="URL">
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
            title="被写体だけを切り抜いて透過PNGにします(30〜90秒)"
            className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
          >
            {cutting ? "切り抜き中…" : "✦ 背景を透過"}
          </button>
        </Row>
      )}
      <div className="flex gap-1">
        <input
          type="text"
          value={remakeInstruction}
          onChange={(e) => setRemakeInstruction(e.target.value)}
          placeholder="この画像を作り直す指示"
          className="min-w-0 flex-1 rounded border border-neutral-300 px-2 py-1 text-xs"
        />
        <button
          onClick={remake}
          disabled={remaking || !remakeInstruction.trim()}
          title="位置とサイズを保ったまま、この画像だけをAIで生成し直します(30〜90秒)"
          className="shrink-0 rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100 disabled:opacity-40"
        >
          {remaking ? "…" : "✦"}
        </button>
      </div>
      <Row label="フィット">
        <select
          value={el.fit}
          onChange={(e) => updateElement(el.id, { fit: e.target.value as "cover" | "contain" })}
          className="rounded border border-neutral-300 px-1.5 py-1 text-xs"
        >
          <option value="cover">カバー</option>
          <option value="contain">全体表示</option>
        </select>
      </Row>
      <Row label="角丸">
        <NumInput value={el.radius ?? 0} onChange={(n) => updateElement(el.id, { radius: Math.max(0, n) })} />
      </Row>
    </Section>
  );
}
