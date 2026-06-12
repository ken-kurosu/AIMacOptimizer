import { promises as fs } from "fs";
import path from "path";

// PDF書き出し中のヘッドレスブラウザが印刷ビューへデッキを渡すための一時エンドポイント

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  if (!/^[a-z0-9]+$/.test(id)) return new Response("not found", { status: 404 });
  try {
    const data = await fs.readFile(path.join(process.cwd(), ".assets", `export-${id}.json`));
    return new Response(data, { headers: { "Content-Type": "application/json" } });
  } catch {
    return new Response("not found", { status: 404 });
  }
}
