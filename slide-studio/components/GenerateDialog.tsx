"use client";

import React, { useEffect, useRef, useState } from "react";
import { useEditor } from "@/lib/store";
import { normalizeDeck } from "@/lib/normalize";
import { uploadImageFile } from "@/lib/upload";

type Engine = "image2" | "structured";

interface RefImage {
  url: string;
}

export function GenerateDialog({ onClose }: { onClose: () => void }) {
  const setDeck = useEditor((s) => s.setDeck);
  const [topic, setTopic] = useState("");
  const [pages, setPages] = useState(8);
  const [audience, setAudience] = useState("");
  const [tone, setTone] = useState("信頼感のあるビジネス");
  const [notes, setNotes] = useState("");
  const [refs, setRefs] = useState<RefImage[]>([]);
  const [refUploading, setRefUploading] = useState(false);
  const refInput = useRef<HTMLInputElement>(null);
  const [engine, setEngine] = useState<Engine>("structured");
  const [avail, setAvail] = useState<{ openai: boolean; anthropic: boolean } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // 参考画像(任意・3枚まで)。配色・トーンの抽出元としてimage2の制作計画に渡す
  const addRefs = async (files: FileList) => {
    const images = Array.from(files)
      .filter((f) => f.type.startsWith("image/"))
      .slice(0, 3 - refs.length);
    if (images.length === 0) return;
    setRefUploading(true);
    try {
      const uploaded: RefImage[] = [];
      for (const f of images) {
        const { url } = await uploadImageFile(f);
        uploaded.push({ url });
      }
      setRefs((prev) => [...prev, ...uploaded].slice(0, 3));
    } catch (e) {
      setError(e instanceof Error ? e.message : "参考画像のアップロードに失敗しました");
    } finally {
      setRefUploading(false);
    }
  };

  useEffect(() => {
    fetch("/api/generate")
      .then((r) => r.json())
      .then((a) => {
        setAvail(a);
        if (a.openai) setEngine("image2");
      })
      .catch(() => setAvail({ openai: false, anthropic: false }));
  }, []);

  const generate = async () => {
    setLoading(true);
    setError(null);
    setNotice(null);
    try {
      const res = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topic,
          pages,
          audience,
          tone,
          engine,
          notes: notes.trim() || undefined,
          references: refs.length > 0 ? refs.map((r) => r.url) : undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? `生成に失敗しました (${res.status})`);
      const deck = normalizeDeck(data.deck);
      setDeck(deck);
      if (data.mode === "demo") {
        setNotice(
          data.warning ??
            "APIキーが未設定のため、テンプレートベースのデモ生成で作成しました。",
        );
        setTimeout(onClose, 2500);
      } else {
        onClose();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "生成に失敗しました");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
    >
      <div
        className="w-[520px] rounded-2xl bg-white p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-1 text-lg font-bold">AIでスライドを生成</h2>
        <p className="mb-4 text-xs text-neutral-500">
          生成後は全パーツ(テキスト・配置・色・リンク)を自由に編集できます。
        </p>

        <div className="mb-4 grid grid-cols-2 gap-2">
          <EngineCard
            active={engine === "image2"}
            disabled={avail !== null && !avail.openai}
            onClick={() => setEngine("image2")}
            title="🎨 image2 カンプ生成"
            desc={
              avail !== null && !avail.openai
                ? "OPENAI_API_KEY が必要です"
                : "画像生成でページ全面をデザインし、テキストを編集可能な層として配置(最高品質・2〜5分)"
            }
          />
          <EngineCard
            active={engine === "structured"}
            disabled={false}
            onClick={() => setEngine("structured")}
            title="📐 構造化生成"
            desc={
              avail !== null && !avail.anthropic
                ? "キー未設定時はデモ生成になります"
                : "テンプレート文法でレイアウトを構成(高速・完全ベクター)"
            }
          />
        </div>

        <label className="mb-3 block text-xs font-medium text-neutral-600">
          資料のテーマ・伝えたいこと *
          <textarea
            autoFocus
            value={topic}
            onChange={(e) => setTopic(e.target.value)}
            rows={3}
            placeholder="例: SaaSプロダクト「○○」の新機能を既存顧客に紹介し、アップセルにつなげる提案資料"
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
          />
        </label>

        <div className="mb-3 grid grid-cols-2 gap-3">
          <label className="block text-xs font-medium text-neutral-600">
            ページ数
            <input
              type="number"
              min={3}
              max={engine === "image2" ? 12 : 20}
              value={pages}
              onChange={(e) => setPages(parseInt(e.target.value) || 8)}
              className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
            />
          </label>
          <label className="block text-xs font-medium text-neutral-600">
            トーン
            <select
              value={tone}
              onChange={(e) => setTone(e.target.value)}
              className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
            >
              <option>信頼感のあるビジネス</option>
              <option>先進的でテック</option>
              <option>親しみやすくカジュアル</option>
              <option>上品でエディトリアル</option>
            </select>
          </label>
        </div>

        <label className="mb-3 block text-xs font-medium text-neutral-600">
          想定読者(任意)
          <input
            type="text"
            value={audience}
            onChange={(e) => setAudience(e.target.value)}
            placeholder="例: 製造業の経営層"
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
          />
        </label>

        <label className="mb-3 block text-xs font-medium text-neutral-600">
          補足・必ず入れたい内容(任意)
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
            placeholder="例: ブランドカラーは#1B4D3E / 料金は月額980円(税込) / 最後に問い合わせ先ページを入れる"
            className="mt-1 w-full rounded-lg border border-neutral-300 px-3 py-2 text-sm"
          />
        </label>

        <div className="mb-4">
          <div className="mb-1 flex items-center justify-between">
            <span className="text-xs font-medium text-neutral-600">
              参考画像(任意・3枚まで)
              <span className="ml-1 font-normal text-neutral-400">
                配色・トーンの参考にします(image2)
              </span>
            </span>
            <button
              onClick={() => refInput.current?.click()}
              disabled={refUploading || refs.length >= 3}
              className="rounded border border-neutral-300 px-2 py-1 text-xs text-neutral-600 hover:bg-neutral-100 disabled:opacity-40"
            >
              {refUploading ? "アップロード中…" : "+ 追加"}
            </button>
            <input
              ref={refInput}
              type="file"
              accept="image/*"
              multiple
              className="hidden"
              onChange={(e) => {
                if (e.target.files) addRefs(e.target.files);
                e.target.value = "";
              }}
            />
          </div>
          {refs.length > 0 && (
            <div className="flex gap-2">
              {refs.map((r) => (
                <div key={r.url} className="relative">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={r.url}
                    alt=""
                    className="h-14 w-20 rounded border border-neutral-200 object-cover"
                  />
                  <button
                    onClick={() => setRefs((prev) => prev.filter((x) => x.url !== r.url))}
                    className="absolute -right-1.5 -top-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-neutral-800 text-[9px] text-white"
                    title="削除"
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {error && <p className="mb-3 text-xs text-red-500">{error}</p>}
        {notice && <p className="mb-3 text-xs text-amber-600">{notice}</p>}

        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg px-4 py-2 text-sm text-neutral-500 hover:bg-neutral-100"
          >
            キャンセル
          </button>
          <button
            onClick={generate}
            disabled={loading || !topic.trim()}
            className="rounded-lg bg-neutral-900 px-5 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-40"
          >
            {loading
              ? engine === "image2"
                ? "画像を生成中…(2〜5分)"
                : "生成中…(最大1分)"
              : "生成する"}
          </button>
        </div>
      </div>
    </div>
  );
}

function EngineCard({
  active,
  disabled,
  onClick,
  title,
  desc,
}: {
  active: boolean;
  disabled: boolean;
  onClick: () => void;
  title: string;
  desc: string;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`rounded-xl border-2 p-3 text-left transition ${
        active
          ? "border-blue-500 bg-blue-50"
          : "border-neutral-200 hover:border-neutral-400"
      } ${disabled ? "cursor-not-allowed opacity-50" : ""}`}
    >
      <div className="mb-1 text-sm font-bold">{title}</div>
      <div className="text-[11px] leading-relaxed text-neutral-500">{desc}</div>
    </button>
  );
}
