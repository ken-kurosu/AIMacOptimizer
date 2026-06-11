import sharp from "sharp";
import { saveAsset } from "@/lib/assets";
import { uid } from "@/lib/types";
import {
  generateImage,
  openaiAvailable,
  pickImageModel,
  pickTransparentImageModels,
} from "@/lib/openai";

export const maxDuration = 120;

// 画像パーツの単体生成。スライドに置く挿絵・アイコン・写真風素材を
// gpt-image系で作り、アセットとして保存してURLを返す。既定は透過背景。

interface ImageBrief {
  prompt?: string;
  transparent?: boolean;
  size?: "1024x1024" | "1536x1024" | "1024x1536";
}

export async function POST(req: Request) {
  if (!openaiAvailable()) {
    return Response.json({ error: "OPENAI_API_KEY が未設定です" }, { status: 400 });
  }
  let brief: ImageBrief;
  try {
    brief = (await req.json()) as ImageBrief;
    if (!brief.prompt?.trim()) throw new Error("no prompt");
  } catch {
    return Response.json({ error: "invalid request" }, { status: 400 });
  }

  const transparent = brief.transparent !== false;
  const prompt = transparent
    ? `${brief.prompt}\n\nIsolated subject on a fully transparent background. No backdrop, no ground shadow. ` +
      `ABSOLUTELY NO text, letters, words, numbers, or typography.`
    : `${brief.prompt}\n\nABSOLUTELY NO text, letters, words, numbers, or typography.`;

  try {
    // 透過背景は最新モデル(gpt-image-2)が非対応のため、対応モデルから選ぶ
    const models = transparent ? await pickTransparentImageModels() : [await pickImageModel()];
    if (models.length === 0) {
      return Response.json(
        { error: "このAPIキーでは透過背景対応の画像モデルが使えません。透過をオフにしてください" },
        { status: 400 },
      );
    }

    let raw: Buffer | null = null;
    let lastError: unknown = null;
    for (const model of models) {
      try {
        raw = await generateImage(model, prompt, {
          size: brief.size ?? "1024x1024",
          background: transparent ? "transparent" : undefined,
        });
        break;
      } catch (e) {
        lastError = e;
        // 透過非対応エラーのときだけ次の候補を試す
        if (!(e instanceof Error && /transparent background is not supported/i.test(e.message))) {
          throw e;
        }
      }
    }
    if (!raw) throw lastError ?? new Error("image generation failed");
    const meta = await sharp(raw).metadata();
    const url = await saveAsset(`gen-${uid()}`, await sharp(raw).png().toBuffer());
    return Response.json({ url, width: meta.width ?? 1024, height: meta.height ?? 1024 });
  } catch (e) {
    console.error("image generation failed:", e);
    return Response.json(
      { error: e instanceof Error ? e.message : "image generation failed" },
      { status: 502 },
    );
  }
}
