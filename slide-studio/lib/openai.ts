// OpenAI API の薄いラッパー(サーバー専用)。
// SDKは使わずfetchで叩く。モデルIDは /v1/models から実行時に解決するので、
// gpt-image-2 など新しいモデルが出ても環境変数なしで自動的に最新を使う。

const BASE = process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1";

export function openaiAvailable(): boolean {
  return !!process.env.OPENAI_API_KEY;
}

function headers(): Record<string, string> {
  return {
    Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    "Content-Type": "application/json",
  };
}

let modelCache: string[] | null = null;

async function listModels(): Promise<string[]> {
  if (modelCache) return modelCache;
  const res = await fetch(`${BASE}/models`, { headers: headers() });
  if (!res.ok) throw new Error(`OpenAI /models failed: ${res.status}`);
  const data = (await res.json()) as { data: { id: string }[] };
  modelCache = data.data.map((m) => m.id);
  return modelCache;
}

// 画像モデル: OPENAI_IMAGE_MODEL > 利用可能な gpt-image 系の最新
export async function pickImageModel(): Promise<string> {
  if (process.env.OPENAI_IMAGE_MODEL) return process.env.OPENAI_IMAGE_MODEL;
  const models = (await listModels()).filter((id) => id.startsWith("gpt-image"));
  if (models.length === 0) throw new Error("no gpt-image model available for this API key");
  models.sort().reverse(); // gpt-image-2 > gpt-image-1.5 > gpt-image-1
  return models[0];
}

// 透過背景対応モデルの候補(新しい順)。gpt-image-2は透過非対応のため、
// 透過指定時はこちらへフォールバックする。miniは品質が落ちるので除外
export async function pickTransparentImageModels(): Promise<string[]> {
  return (await listModels())
    .filter((id) => /^gpt-image-1(\.\d+)?$/.test(id))
    .sort()
    .reverse();
}

// テキスト/ビジョンモデル: OPENAI_TEXT_MODEL > gpt-5系 > gpt-4.1 > gpt-4o
export async function pickTextModel(): Promise<string> {
  if (process.env.OPENAI_TEXT_MODEL) return process.env.OPENAI_TEXT_MODEL;
  const models = await listModels();
  const candidates = [
    ...models.filter((id) => /^gpt-5(\.\d+)?$/.test(id)).sort().reverse(),
    ...models.filter((id) => /^gpt-4\.1$/.test(id)),
    ...models.filter((id) => /^gpt-4o$/.test(id)),
  ];
  if (candidates.length === 0) throw new Error("no suitable chat model available");
  return candidates[0];
}

export type ChatContent =
  | string
  | (
      | { type: "text"; text: string }
      | { type: "image_url"; image_url: { url: string; detail?: "low" | "high" | "auto" } }
    )[];

export async function chatJSON<T>(
  model: string,
  system: string,
  userContent: ChatContent,
  maxTokens = 16000,
): Promise<T> {
  const res = await fetch(`${BASE}/chat/completions`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: userContent },
      ],
      response_format: { type: "json_object" },
      max_completion_tokens: maxTokens,
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenAI chat failed: ${res.status} ${body.slice(0, 300)}`);
  }
  const data = (await res.json()) as {
    choices: { message: { content: string } }[];
  };
  const text = data.choices[0]?.message?.content ?? "";
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no JSON in chat response");
  return JSON.parse(text.slice(start, end + 1)) as T;
}

export interface ImageGenOptions {
  quality?: string;
  size?: "1024x1024" | "1536x1024" | "1024x1536";
  background?: "transparent" | "opaque";
}

// 画像生成。既定は1536x1024(3:2)で、スライド背景は呼び出し側で16:9に切り出す。
// 背景デザインの品質が製品価値そのものなので、既定のqualityはhigh
export async function generateImage(
  model: string,
  prompt: string,
  opts: ImageGenOptions = {},
): Promise<Buffer> {
  const res = await fetch(`${BASE}/images/generations`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model,
      prompt,
      size: opts.size ?? "1536x1024",
      quality: opts.quality ?? process.env.OPENAI_IMAGE_QUALITY ?? "high",
      ...(opts.background ? { background: opts.background } : {}),
      n: 1,
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenAI image failed: ${res.status} ${body.slice(0, 300)}`);
  }
  const data = (await res.json()) as { data: { b64_json?: string; url?: string }[] };
  const item = data.data[0];
  if (item.b64_json) return Buffer.from(item.b64_json, "base64");
  if (item.url) {
    const img = await fetch(item.url);
    return Buffer.from(await img.arrayBuffer());
  }
  throw new Error("image response had no data");
}

// 画像編集(images/edits)。入力画像をプロンプトで編集する。背景除去などに使う
export async function editImage(
  model: string,
  image: Buffer,
  prompt: string,
  opts: ImageGenOptions = {},
): Promise<Buffer> {
  const form = new FormData();
  form.append("model", model);
  form.append("prompt", prompt);
  form.append("image", new Blob([new Uint8Array(image)], { type: "image/png" }), "image.png");
  form.append("quality", opts.quality ?? process.env.OPENAI_IMAGE_QUALITY ?? "high");
  if (opts.size) form.append("size", opts.size);
  if (opts.background) form.append("background", opts.background);
  const res = await fetch(`${BASE}/images/edits`, {
    method: "POST",
    headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
    body: form,
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenAI image edit failed: ${res.status} ${body.slice(0, 300)}`);
  }
  const data = (await res.json()) as { data: { b64_json?: string; url?: string }[] };
  const item = data.data[0];
  if (item.b64_json) return Buffer.from(item.b64_json, "base64");
  if (item.url) {
    const img = await fetch(item.url);
    return Buffer.from(await img.arrayBuffer());
  }
  throw new Error("image edit response had no data");
}
