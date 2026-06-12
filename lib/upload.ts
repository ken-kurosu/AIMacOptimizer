import { ImageEl, SLIDE_H, SLIDE_W, uid } from "./types";

// 画像ファイルをサーバーへアップロードし、アセットURLと実寸を受け取る
export async function uploadImageFile(
  file: File,
): Promise<{ url: string; width: number; height: number }> {
  const res = await fetch("/api/assets", {
    method: "POST",
    headers: { "Content-Type": file.type || "application/octet-stream" },
    body: file,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error ?? `アップロードに失敗しました (${res.status})`);
  return data as { url: string; width: number; height: number };
}

interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

function overlapArea(a: Rect, b: Rect): number {
  const w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
  const h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
  return Math.max(0, w) * Math.max(0, h);
}

// 画像をスライドへ置くときの初期配置。アスペクト比を保って560x440に収め、
// 既存要素(テキスト等)との重なりが最小になる位置を候補から選ぶ
export function imageElementFor(
  url: string,
  width: number,
  height: number,
  index = 0,
  avoid: Rect[] = [],
): ImageEl {
  const scale = Math.min(560 / width, 440 / height, 1);
  const w = Math.round(width * scale);
  const h = Math.round(height * scale);
  const M = 80;
  const candidates: Rect[] = [
    { x: SLIDE_W - w - M, y: Math.round((SLIDE_H - h) / 2), w, h }, // 右
    { x: M, y: Math.round((SLIDE_H - h) / 2), w, h }, // 左
    { x: SLIDE_W - w - M, y: SLIDE_H - h - 64, w, h }, // 右下
    { x: Math.round((SLIDE_W - w) / 2), y: SLIDE_H - h - 64, w, h }, // 中央下
    { x: Math.round((SLIDE_W - w) / 2), y: Math.round((SLIDE_H - h) / 2), w, h }, // 中央
  ];
  let best = candidates[0];
  let bestScore = Infinity;
  for (const c of candidates) {
    const score = avoid.reduce((acc, r) => acc + overlapArea(c, r), 0);
    if (score < bestScore) {
      bestScore = score;
      best = c;
      if (score === 0) break;
    }
  }
  return {
    id: uid(),
    type: "image",
    src: url,
    x: best.x + index * 24,
    y: best.y + index * 24,
    w,
    h,
    fit: "cover",
    radius: 8,
  };
}
