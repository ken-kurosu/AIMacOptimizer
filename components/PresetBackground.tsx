import { Background, SLIDE_H, SLIDE_W, Theme, resolveColor } from "@/lib/types";

// 背景レイヤー: ベース色 + 手続き生成SVG装飾(テーマカラーに自動追従) + 任意の画像。
// 画像生成APIを繋いだ場合は background.image にURLを入れるだけで差し替わる。
export function PresetBackground({
  background,
  theme,
}: {
  background: Background;
  theme: Theme;
}) {
  const base = resolveColor(background.color, theme);
  const c = theme.colors;
  return (
    <div className="absolute inset-0" style={{ background: base }}>
      {background.image && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={background.image}
          alt=""
          className="absolute inset-0 h-full w-full object-cover"
        />
      )}
      {background.preset !== "none" && (
        <svg
          className="absolute inset-0"
          width="100%"
          height="100%"
          viewBox={`0 0 ${SLIDE_W} ${SLIDE_H}`}
          preserveAspectRatio="none"
        >
          {background.preset === "mesh" && (
            <>
              <defs>
                <radialGradient id="m1" cx="0.15" cy="0.1" r="0.7">
                  <stop offset="0%" stopColor={c.brand} stopOpacity="0.22" />
                  <stop offset="100%" stopColor={c.brand} stopOpacity="0" />
                </radialGradient>
                <radialGradient id="m2" cx="0.9" cy="0.9" r="0.8">
                  <stop offset="0%" stopColor={c.accent} stopOpacity="0.16" />
                  <stop offset="100%" stopColor={c.accent} stopOpacity="0" />
                </radialGradient>
                <radialGradient id="m3" cx="0.8" cy="0.05" r="0.5">
                  <stop offset="0%" stopColor={c.brandSoft} stopOpacity="0.8" />
                  <stop offset="100%" stopColor={c.brandSoft} stopOpacity="0" />
                </radialGradient>
              </defs>
              <rect width={SLIDE_W} height={SLIDE_H} fill="url(#m1)" />
              <rect width={SLIDE_W} height={SLIDE_H} fill="url(#m2)" />
              <rect width={SLIDE_W} height={SLIDE_H} fill="url(#m3)" />
            </>
          )}
          {background.preset === "blobs" && (
            <>
              <circle cx={1180} cy={80} r={260} fill={c.brand} opacity={0.1} />
              <circle cx={1280} cy={640} r={180} fill={c.accent} opacity={0.14} />
              <circle cx={60} cy={680} r={220} fill={c.brand} opacity={0.08} />
              <circle cx={140} cy={60} r={90} fill={c.brandSoft} opacity={0.9} />
            </>
          )}
          {background.preset === "diagonal" && (
            <>
              <polygon
                points={`0,${SLIDE_H} ${SLIDE_W},${SLIDE_H} ${SLIDE_W},520`}
                fill={c.brand}
                opacity={0.08}
              />
              <polygon
                points={`0,${SLIDE_H} ${SLIDE_W},${SLIDE_H} ${SLIDE_W},620`}
                fill={c.brand}
                opacity={0.12}
              />
              <rect x={0} y={0} width={SLIDE_W} height={10} fill={c.brand} />
            </>
          )}
          {background.preset === "grid" && (
            <>
              {Array.from({ length: 26 }, (_, i) => (
                <line
                  key={`v${i}`}
                  x1={i * 52}
                  y1={0}
                  x2={i * 52}
                  y2={SLIDE_H}
                  stroke={c.line}
                  strokeWidth={1}
                  opacity={0.5}
                />
              ))}
              {Array.from({ length: 15 }, (_, i) => (
                <line
                  key={`h${i}`}
                  x1={0}
                  y1={i * 52}
                  x2={SLIDE_W}
                  y2={i * 52}
                  stroke={c.line}
                  strokeWidth={1}
                  opacity={0.5}
                />
              ))}
            </>
          )}
          {background.preset === "waves" && (
            <>
              <path
                d={`M0 ${SLIDE_H - 120} C 320 ${SLIDE_H - 220}, 640 ${SLIDE_H - 40}, ${SLIDE_W} ${SLIDE_H - 160} L ${SLIDE_W} ${SLIDE_H} L 0 ${SLIDE_H} Z`}
                fill={c.brand}
                opacity={0.1}
              />
              <path
                d={`M0 ${SLIDE_H - 60} C 320 ${SLIDE_H - 150}, 720 ${SLIDE_H + 10}, ${SLIDE_W} ${SLIDE_H - 90} L ${SLIDE_W} ${SLIDE_H} L 0 ${SLIDE_H} Z`}
                fill={c.brand}
                opacity={0.16}
              />
            </>
          )}
          {background.preset === "dots" && (
            <>
              {Array.from({ length: 8 }, (_, row) =>
                Array.from({ length: 8 }, (_, col) => (
                  <circle
                    key={`${row}-${col}`}
                    cx={920 + col * 44}
                    cy={60 + row * 44}
                    r={3.5}
                    fill={c.brand}
                    opacity={0.25}
                  />
                )),
              )}
            </>
          )}
          {background.preset === "frame" && (
            <>
              <rect
                x={28}
                y={28}
                width={SLIDE_W - 56}
                height={SLIDE_H - 56}
                fill="none"
                stroke={c.brand}
                strokeWidth={1.5}
                opacity={0.55}
              />
              <rect x={28} y={28} width={120} height={6} fill={c.accent} />
            </>
          )}
          {background.preset === "rings" && (
            <>
              {[300, 230, 160, 90].map((r, i) => (
                <circle
                  key={r}
                  cx={1150}
                  cy={120}
                  r={r}
                  fill="none"
                  stroke={i === 2 ? c.accent : c.brand}
                  strokeWidth={i === 3 ? 14 : 1.5}
                  opacity={i === 3 ? 0.16 : 0.3}
                />
              ))}
              <circle cx={120} cy={650} r={130} fill="none" stroke={c.brand} strokeWidth={1.5} opacity={0.25} />
              <circle cx={120} cy={650} r={70} fill={c.brandSoft} opacity={0.7} />
            </>
          )}
          {background.preset === "stripes" && (
            <>
              {Array.from({ length: 9 }, (_, i) => (
                <line
                  key={i}
                  x1={SLIDE_W - 420 + i * 36}
                  y1={SLIDE_H + 60}
                  x2={SLIDE_W + 200 + i * 36}
                  y2={-60}
                  stroke={i === 4 ? c.accent : c.brand}
                  strokeWidth={i % 3 === 0 ? 10 : 2}
                  opacity={i === 4 ? 0.5 : 0.18}
                />
              ))}
              <rect x={0} y={SLIDE_H - 8} width={SLIDE_W} height={8} fill={c.brand} opacity={0.7} />
            </>
          )}
          {background.preset === "corner" && (
            <>
              <path d={`M0 0 L340 0 L0 260 Z`} fill={c.brand} opacity={0.12} />
              <path d={`M0 0 L220 0 L0 170 Z`} fill={c.brand} opacity={0.2} />
              <path
                d={`M${SLIDE_W} ${SLIDE_H} L${SLIDE_W - 300} ${SLIDE_H} L${SLIDE_W} ${SLIDE_H - 230} Z`}
                fill={c.accent}
                opacity={0.16}
              />
              <circle cx={SLIDE_W - 70} cy={90} r={10} fill={c.accent} opacity={0.8} />
            </>
          )}
          {background.preset === "sparkle" && (
            <>
              {[
                [90, 110, 7], [180, 70, 4], [1130, 90, 9], [1210, 190, 5],
                [1180, 620, 7], [1080, 670, 4], [140, 600, 5], [70, 520, 8],
                [640, 70, 4], [700, 660, 5],
              ].map(([x, y, r], i) => (
                <circle
                  key={i}
                  cx={x}
                  cy={y}
                  r={r}
                  fill={i % 3 === 0 ? c.accent : c.brand}
                  opacity={i % 2 === 0 ? 0.35 : 0.2}
                />
              ))}
              {[[260, 140], [1040, 560], [980, 150], [320, 580]].map(([x, y], i) => (
                <path
                  key={`s${i}`}
                  d={`M${x} ${y - 14} L${x + 4} ${y - 4} L${x + 14} ${y} L${x + 4} ${y + 4} L${x} ${y + 14} L${x - 4} ${y + 4} L${x - 14} ${y} L${x - 4} ${y - 4} Z`}
                  fill={c.brand}
                  opacity={0.3}
                />
              ))}
            </>
          )}
        </svg>
      )}
    </div>
  );
}
