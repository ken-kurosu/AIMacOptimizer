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

// 画像をスライドへ置くときの初期配置。アスペクト比を保って640x480に収め、
// 複数枚は少しずつずらして重ねる
export function imageElementFor(
  url: string,
  width: number,
  height: number,
  index = 0,
): ImageEl {
  const scale = Math.min(640 / width, 480 / height, 1);
  const w = Math.round(width * scale);
  const h = Math.round(height * scale);
  return {
    id: uid(),
    type: "image",
    src: url,
    x: Math.round((SLIDE_W - w) / 2) + index * 24,
    y: Math.round((SLIDE_H - h) / 2) + index * 24,
    w,
    h,
    fit: "cover",
    radius: 8,
  };
}
