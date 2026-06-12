import { promises as fs } from "fs";
import path from "path";

// 生成画像の保存先。base64をlocalStorageに入れると容量上限(~5MB)を超えるため、
// サーバーのファイルとして保存し /api/assets/<id> のURLでデッキから参照する。
const ASSETS_DIR = path.join(process.cwd(), ".assets");

export async function saveAsset(id: string, data: Buffer): Promise<string> {
  await fs.mkdir(ASSETS_DIR, { recursive: true });
  await fs.writeFile(path.join(ASSETS_DIR, `${id}.png`), data);
  return `/api/assets/${id}`;
}

export async function readAsset(id: string): Promise<Buffer | null> {
  // パストラバーサル防止
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) return null;
  try {
    return await fs.readFile(path.join(ASSETS_DIR, `${id}.png`));
  } catch {
    return null;
  }
}
