"use client";

import React from "react";
import { ColorKey } from "@/lib/types";
import { useEditor } from "@/lib/store";
import { FONT_OPTIONS, THEME_PRESETS } from "@/lib/theme";
import { COLOR_LABEL_KEYS, useT } from "@/lib/i18n";

// テーマトークンパネル。色を変えると token 参照している全要素・全ページに即時反映される。
export function ThemePanel() {
  const t = useT();
  const theme = useEditor((s) => s.deck.theme);
  const updateTheme = useEditor((s) => s.updateTheme);

  return (
    <div className="flex h-full w-64 shrink-0 flex-col overflow-y-auto border-r border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-4 py-3 text-sm font-bold">{t("themeTitle")}</div>

      <div className="border-b border-neutral-200 px-4 py-3">
        <div className="mb-2 text-[11px] font-bold tracking-wider text-neutral-400">{t("presets")}</div>
        <div className="grid grid-cols-2 gap-2">
          {THEME_PRESETS.map((p) => (
            <button
              key={p.name}
              onClick={() => updateTheme(p.theme)}
              className="rounded-lg border border-neutral-200 p-2 text-left hover:border-neutral-400"
            >
              <div className="mb-1 flex gap-1">
                {[p.theme.colors.brand, p.theme.colors.accent, p.theme.colors.bg, p.theme.colors.ink].map(
                  (c, i) => (
                    <span
                      key={i}
                      className="h-4 w-4 rounded-full border border-black/10"
                      style={{ background: c }}
                    />
                  ),
                )}
              </div>
              <div className="text-[11px] text-neutral-600">{p.name}</div>
            </button>
          ))}
        </div>
      </div>

      <div className="border-b border-neutral-200 px-4 py-3">
        <div className="mb-2 text-[11px] font-bold tracking-wider text-neutral-400">
          {t("colorTokens")}
        </div>
        <div className="space-y-1.5">
          {(Object.keys(theme.colors) as ColorKey[]).map((key) => (
            <label key={key} className="flex items-center justify-between text-xs text-neutral-600">
              <span>{COLOR_LABEL_KEYS[key] ? t(COLOR_LABEL_KEYS[key]) : key}</span>
              <span className="flex items-center gap-2">
                <span className="font-mono text-[10px] text-neutral-400">
                  {theme.colors[key].toUpperCase()}
                </span>
                <input
                  type="color"
                  value={theme.colors[key]}
                  onChange={(e) =>
                    updateTheme({ colors: { ...theme.colors, [key]: e.target.value } })
                  }
                  className="h-6 w-8 cursor-pointer rounded border border-neutral-300 p-0"
                />
              </span>
            </label>
          ))}
        </div>
        <p className="mt-2 text-[11px] leading-relaxed text-neutral-400">
          変更は全ページのトークン参照要素に即時反映されます。
        </p>
      </div>

      <div className="px-4 py-3">
        <div className="mb-2 text-[11px] font-bold tracking-wider text-neutral-400">フォント</div>
        <div className="space-y-2">
          <label className="block text-xs text-neutral-600">
            見出し
            <select
              value={theme.headingFont}
              onChange={(e) => updateTheme({ headingFont: e.target.value })}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            >
              {FONT_OPTIONS.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.label}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs text-neutral-600">
            本文
            <select
              value={theme.bodyFont}
              onChange={(e) => updateTheme({ bodyFont: e.target.value })}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1 text-xs"
            >
              {FONT_OPTIONS.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      </div>
    </div>
  );
}
