import React from "react";
import {
  ImageEl,
  ShapeEl,
  Slide,
  SlideElement,
  SLIDE_H,
  SLIDE_W,
  TextEl,
  Theme,
  resolveColor,
} from "@/lib/types";
import { PresetBackground } from "./PresetBackground";

// スライド1枚を 1280x720 の座標系でレンダリングする純粋コンポーネント。
// エディタ(interactive)、サムネイル、印刷ビューの全てで共有する。
// withLinks=true のとき <a href> を出力し、Chrome系の印刷PDFでリンクが保持される。

export function elementStyle(el: SlideElement): React.CSSProperties {
  return {
    position: "absolute",
    left: el.x,
    top: el.y,
    width: el.w,
    height: el.h,
    opacity: el.opacity ?? 1,
    transform: el.rotation ? `rotate(${el.rotation}deg)` : undefined,
  };
}

export function TextContent({ el, theme }: { el: TextEl; theme: Theme }) {
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        fontSize: el.fontSize,
        fontWeight: el.fontWeight,
        color: resolveColor(el.color, theme),
        textAlign: el.align,
        lineHeight: el.lineHeight,
        letterSpacing: el.letterSpacing,
        fontFamily: el.font === "heading" ? theme.headingFont : theme.bodyFont,
        whiteSpace: "pre-wrap",
        overflowWrap: "break-word",
      }}
    >
      {el.text}
    </div>
  );
}

export function ShapeContent({ el, theme }: { el: ShapeEl; theme: Theme }) {
  const fill = resolveColor(el.fill, theme);
  const stroke = el.stroke ? resolveColor(el.stroke, theme) : undefined;
  if (el.shape === "line") {
    return (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
        }}
      >
        <div style={{ width: "100%", height: Math.max(1, el.strokeWidth ?? 2), background: fill }} />
      </div>
    );
  }
  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: fill,
        border: stroke ? `${el.strokeWidth ?? 1}px solid ${stroke}` : undefined,
        borderRadius: el.shape === "ellipse" ? "50%" : el.radius,
      }}
    />
  );
}

export function ImageContent({ el }: { el: ImageEl }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={el.src}
      alt={el.name ?? ""}
      draggable={false}
      style={{
        width: "100%",
        height: "100%",
        objectFit: el.fit,
        borderRadius: el.radius,
        display: "block",
      }}
    />
  );
}

export function ElementContent({ el, theme }: { el: SlideElement; theme: Theme }) {
  if (el.type === "text") return <TextContent el={el} theme={theme} />;
  if (el.type === "shape") return <ShapeContent el={el} theme={theme} />;
  return <ImageContent el={el} />;
}

export function SlideRenderer({
  slide,
  theme,
  withLinks = false,
}: {
  slide: Slide;
  theme: Theme;
  withLinks?: boolean;
}) {
  return (
    <div
      style={{
        position: "relative",
        width: SLIDE_W,
        height: SLIDE_H,
        overflow: "hidden",
        fontFamily: theme.bodyFont,
      }}
    >
      <PresetBackground background={slide.background} theme={theme} />
      {slide.elements.map((el) => {
        const content = <ElementContent el={el} theme={theme} />;
        if (withLinks && el.link) {
          const internal = el.link.startsWith("#");
          return (
            <a
              key={el.id}
              href={el.link}
              target={internal ? undefined : "_blank"}
              rel={internal ? undefined : "noreferrer"}
              style={{ ...elementStyle(el), display: "block", textDecoration: "none" }}
            >
              {content}
            </a>
          );
        }
        return (
          <div key={el.id} style={elementStyle(el)}>
            {content}
          </div>
        );
      })}
    </div>
  );
}

// サムネイル等で使う縮小ラッパー
export function ScaledSlide({
  slide,
  theme,
  width,
  withLinks,
}: {
  slide: Slide;
  theme: Theme;
  width: number;
  withLinks?: boolean;
}) {
  const scale = width / SLIDE_W;
  return (
    <div style={{ width, height: SLIDE_H * scale, overflow: "hidden", position: "relative" }}>
      <div style={{ transform: `scale(${scale})`, transformOrigin: "top left" }}>
        <SlideRenderer slide={slide} theme={theme} withLinks={withLinks} />
      </div>
    </div>
  );
}
