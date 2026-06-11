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

// 画像生成。1536x1024(3:2)で生成し、呼び出し側で16:9に切り出す。
// 背景デザインの品質が製品価値そのものなので、既定のqualityはhigh
export async function generateImage(
  model: string,
  prompt: string,
  quality?: string,
): Promise<Buffer> {
  const res = await fetch(`${BASE}/images/generations`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      model,
      prompt,
      size: "1536x1024",
      quality: quality ?? process.env.OPENAI_IMAGE_QUALITY ?? "high",
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
