"use client";

import { useSyncExternalStore } from "react";

// 軽量i18n。UI文字列はja/enの2辞書のみ(キーはjaを正とし、型で漏れを検出)。
// ロケールは localStorage > ブラウザ言語 で決まり、ヘッダーのトグルで切替できる。
// 本格的なi18n基盤を入れないのは意図的(文字列は~150個で増殖しない想定)。

export type Locale = "ja" | "en";
const STORAGE_KEY = "compdeck-locale";

const ja = {
  // 共通
  cancel: "キャンセル",
  close: "閉じる",
  del: "削除",
  loading: "読み込み中…",

  // TopBar
  heading: "見出し",
  text: "テキスト",
  rectTitle: "四角形",
  ellipseTitle: "円",
  lineTitle: "線",
  image: "画像",
  imageUploading: "アップロード中…",
  imageTitle: "画像をアップロードして配置(キャンバスへのドラッグ&ドロップも可)",
  aiImage: "✦画像",
  aiImageTitle: "AIで画像パーツを生成して配置",
  undoTitle: "元に戻す (Ctrl+Z)",
  redoTitle: "やり直す (Ctrl+Shift+Z)",
  createDeck: "✦ 資料を作る",
  createDeckTitle: "作りたい内容を書くと、AIが構成案→デザイン込みのデッキを自動作成します",
  deckBtn: "デッキ",
  deckBtnTitle: "デッキの切り替え・共有リンク・ファイル保存/読み込みはここから",
  exportPdf: "PDF書き出し",
  exportPdfBusy: "書き出し中…",
  exportPdfTitle: "Chromeを自動検出してワンクリックでPDF化。使えない環境では印刷ビューが開きます",

  // GenerateDialog
  gdTitle: "新しい資料を作る",
  gdIntro: "内容を書くと、まず構成案が出ます。確認してOKなら生成に進みます。",
  gdPlaceholder:
    "どんな資料を作りたいか、自由に書いてください。\n誰向けか・トーン・必ず入れたい数字や構成があれば一緒に。\n\n例: 自家焙煎コーヒー定期便の紹介資料。在宅ワーカー向けに上品なトーンで。月額980円(税込)は必ず載せる",
  pagesLabel: "ページ数",
  addRef: "+ 参考画像",
  refUploading: "追加中…",
  refTitle: "ブランド資料やトンマナの近い画像を渡すと、配色・雰囲気の参考にします",
  makePlan: "構成案を見る",
  planning: "構成を考えています…(30秒〜1分)",
  generatingShort: "生成中…",
  reviewCount: "この内容で{n}ページ生成します",
  planBy: "構成:",
  feedbackPlaceholder: "修正したい点があれば書いて「作り直す」(例: 3ページ目は事例紹介にして)",
  backToInput: "← 入力に戻る",
  remake: "作り直す",
  remaking: "作り直し中…",
  approveGenerate: "この構成で生成する",
  generatingLong: "生成中…(1ページ約1分)",
  estimate: "目安: 1ページあたり約1分",
  demoNotice: "APIキーが未設定のため、デモ生成で作成しました。",
  planFailed: "構成案の作成に失敗しました",
  generateFailed: "生成に失敗しました",
  uploadFailed: "画像のアップロードに失敗しました",
  spaceLeft: "テキストは左",
  spaceRight: "テキストは右",
  spaceTop: "テキストは上",
  spaceBottom: "テキストは下",
  spaceCenter: "テキストは中央",
  planFallbackTitle: "構成案",
  researchToggle: "Web検索で最新情報を反映",
  researchToggleTitle: "構成案を作る前にWebで事実(料金・実績・正式名称など)を調べて反映します(+30秒〜1分)",
  researching: "Webで調べています…(1〜2分)",
  sourcesLabel: "参照した情報源",

  // SlideList
  pages: "ページ",
  aiAddBtn: "✦ AI",
  aiAddBtnTitle: "内容を書くと、デッキのテーマに合わせてAIがページを1枚生成します",
  addPage: "+ 追加",
  moveUp: "上へ",
  moveDown: "下へ",
  regenTitle: "このページをAIで再デザイン(テキストは維持)",
  duplicate: "複製",
  regenerating: "再デザイン中…",
  regenFailed: "再生成に失敗しました",
  aiAddTitle2: "AIでページを追加",
  aiAddIntro: "デッキのテーマ(配色・トーン)に合わせて、背景デザイン込みの1ページを生成します。",
  aiAddPlaceholder:
    "例: 導入スケジュールを3フェーズで説明するページ。各フェーズの期間と到達目標を載せる",
  aiAddCreate: "生成して追加",
  aiAddCreating: "生成中…(1〜2分)",

  // DeckLibraryDialog
  deckDialogTitle: "デッキ",
  thisDeck: "このデッキ「{title}」",
  shareLink: "共有リンクを作る",
  shareLinkTitle: "サーバーに保存して、誰でも開ける共有リンクをコピーします",
  saving: "保存中…",
  saveJson: "ファイルに保存 (JSON)",
  saveJsonTitle: "バックアップ用にJSONファイルとしてダウンロードします",
  openSection: "開く",
  openFile: "ファイルから開く (JSON / PDF)",
  openFileTitle: "JSONはそのまま、PDFは「背景画像+編集できるテキスト」に分解して取り込みます",
  importingPdf: "PDFを分解中…(ページ数×1分)",
  linkCopied: "共有リンクをコピーしました:",
  noSavedDecks: "保存されたデッキはまだありません",
  openDeckFailed: "デッキを開けませんでした",
  saveFailed: "保存に失敗しました",
  importFailed: "取り込みに失敗しました",
  jsonReadFailed: "JSONの読み込みに失敗しました",
  pdfImportFailed: "PDFの取り込みに失敗しました",

  // Inspector
  slideSettings: "スライド設定",
  background: "背景",
  baseColor: "ベース色",
  decoration: "装飾",
  bgImageUrl: "背景画像URL",
  aiEdit: "AI編集",
  decompose: "✦ レイヤーに分解",
  decomposing: "分解中…",
  decomposeTitle: "背景をオブジェクト単位の編集可能なレイヤーに分解します(2〜3分)",
  layersLabel: "レイヤー",
  layerBg: "背景",
  decomposeFailed: "分解に失敗しました",
  slideName: "スライド名",
  editorHint:
    "要素をクリックすると詳細を編集できます。ダブルクリックでテキストを直接編集、ドラッグで移動できます。",
  textEl: "テキスト",
  shapeEl: "図形",
  imageEl: "画像",
  toBack: "背面へ",
  toFront: "前面へ",
  posSize: "位置とサイズ",
  rotation: "回転",
  opacity: "不透明度",
  rewritePlaceholder: "AIへの指示(空なら磨くだけ)",
  rewriteTitle: "この文言だけをAIで書き直します(文字数は同程度に保たれます)",
  rewriteFailed: "書き換えに失敗しました",
  typography: "タイポグラフィ",
  fontSize: "サイズ",
  lineHeight: "行間",
  fontWeight: "太さ",
  align: "揃え",
  alignLeft: "左",
  alignCenter: "中",
  alignRight: "右",
  fontLabel: "フォント",
  fontHeading: "見出し用",
  fontBody: "本文用",
  colorLabel: "色",
  customColor: "カスタム色",
  shapeKind: "種類",
  shapeRect: "四角形",
  shapeEllipse: "円",
  shapeLine: "線",
  fill: "塗り",
  cornerRadius: "角丸",
  strokeColor: "枠線色",
  strokeWidth: "枠線幅",
  imageUrl: "URL",
  fit: "フィット",
  fitCover: "カバー",
  fitContain: "全体表示",
  removeBg: "✦ 背景を透過",
  cutting: "切り抜き中…",
  removeBgTitle: "被写体だけを切り抜いて透過PNGにします(30〜90秒)",
  removeBgFailed: "切り抜きに失敗しました",
  remakePlaceholder: "この画像を作り直す指示",
  remakeImgTitle: "位置とサイズを保ったまま、この画像だけをAIで生成し直します(30〜90秒)",
  remakeImgFailed: "作り直しに失敗しました",
  hyperlink: "ハイパーリンク",
  internalLink: "内部リンク",
  linkNone: "なし",
  linkNote: "リンクはPDF書き出し時にも保持されます。",

  // ThemePanel
  themeTitle: "テーマ",
  presets: "プリセット",
  colorTokens: "カラートークン",
  fonts: "フォント",
  headingFontLabel: "見出し",
  bodyFontLabel: "本文",

  // GenerateImageDialog
  giTitle: "AIで画像パーツを生成",
  giIntro: "挿絵・アイコン・写真風素材を1枚生成して、選択中のスライドに配置します。",
  giPlaceholder: "例: 聴診器と母子手帳のフラットイラスト、淡いグリーン基調、線は少なめ",
  giTransparent: "透過背景(パーツとして重ねやすい)",
  giSquare: "正方形",
  giLandscape: "横長",
  giPortrait: "縦長",
  giCreate: "生成して配置",
  giCreating: "生成中…(30〜90秒)",

  // print
  printNoDeck: "デッキが見つかりません。エディタで作成してから再度開いてください。",
  printSave: "印刷 / PDFに保存",
  printHint:
    "印刷ダイアログで「送信先: PDFに保存」「余白: なし」「背景のグラフィック: ON」を選択してください。ハイパーリンク(外部・ページ内)はPDFに保持されます。",

  // タブ
  tabSlides: "頁",
  tabTheme: "色",

  // プリセット名
  presetNone: "なし",
  presetMesh: "メッシュ",
  presetBlobs: "ブロブ",
  presetDiagonal: "斜めライン",
  presetGrid: "グリッド",
  presetWaves: "波",
  presetDots: "ドット",
  presetFrame: "フレーム",
  presetRings: "リング",
  presetStripes: "ストライプ",
  presetCorner: "コーナー",
  presetSparkle: "スパークル",

  // カラートークン名
  colorBrand: "ブランド",
  colorBrandDark: "ブランド(濃)",
  colorBrandSoft: "ブランド(淡)",
  colorAccent: "アクセント",
  colorBg: "背景",
  colorSurface: "サーフェス",
  colorInk: "文字",
  colorMuted: "サブテキスト",
  colorLine: "罫線",
};

const en: Record<keyof typeof ja, string> = {
  cancel: "Cancel",
  close: "Close",
  del: "Delete",
  loading: "Loading…",

  heading: "Heading",
  text: "Text",
  rectTitle: "Rectangle",
  ellipseTitle: "Ellipse",
  lineTitle: "Line",
  image: "Image",
  imageUploading: "Uploading…",
  imageTitle: "Upload an image (or drag & drop onto the canvas)",
  aiImage: "✦Image",
  aiImageTitle: "Generate an image part with AI",
  undoTitle: "Undo (Ctrl+Z)",
  redoTitle: "Redo (Ctrl+Shift+Z)",
  createDeck: "✦ Create deck",
  createDeckTitle: "Describe what you want — AI drafts an outline, you approve, it designs the deck",
  deckBtn: "Decks",
  deckBtnTitle: "Switch decks, share links, save/open files",
  exportPdf: "Export PDF",
  exportPdfBusy: "Exporting…",
  exportPdfTitle: "One-click server-side PDF via your installed Chrome (falls back to the print view)",

  gdTitle: "Create a new deck",
  gdIntro: "Describe it, review the outline, then approve to generate.",
  gdPlaceholder:
    "Describe the deck you want, in any language.\nInclude the audience, tone, and any numbers that must appear.\n\ne.g. Intro deck for our coffee subscription. Elegant tone for remote workers. Must include the $9/mo price.",
  pagesLabel: "Pages",
  addRef: "+ Reference",
  refUploading: "Adding…",
  refTitle: "Reference images guide the color palette and mood",
  makePlan: "Draft the outline",
  planning: "Drafting the outline… (30–60 s)",
  generatingShort: "Generating…",
  reviewCount: "{n} pages will be generated from this outline",
  planBy: "outline:",
  feedbackPlaceholder: "Want changes? Describe them and hit Redraft (e.g. make page 3 a case study)",
  backToInput: "← Back",
  remake: "Redraft",
  remaking: "Redrafting…",
  approveGenerate: "Generate with this outline",
  generatingLong: "Generating… (~1 min/page)",
  estimate: "Estimate: about 1 minute per page",
  demoNotice: "No API key configured — created with the demo generator.",
  planFailed: "Failed to draft the outline",
  generateFailed: "Generation failed",
  uploadFailed: "Image upload failed",
  spaceLeft: "text left",
  spaceRight: "text right",
  spaceTop: "text top",
  spaceBottom: "text bottom",
  spaceCenter: "text centered",
  planFallbackTitle: "Outline",
  researchToggle: "Research the web for facts",
  researchToggleTitle: "Searches the web for facts (pricing, names, track record) before drafting (+30–60 s)",
  researching: "Researching the web… (1–2 min)",
  sourcesLabel: "Sources",

  pages: "Pages",
  aiAddBtn: "✦ AI",
  aiAddBtnTitle: "Describe a page and AI generates it to match the deck's theme",
  addPage: "+ Add",
  moveUp: "Move up",
  moveDown: "Move down",
  regenTitle: "Redesign this page with AI (keeps the text)",
  duplicate: "Duplicate",
  regenerating: "Redesigning…",
  regenFailed: "Regeneration failed",
  aiAddTitle2: "Add a page with AI",
  aiAddIntro: "Generates one page, background design included, matching the deck's theme.",
  aiAddPlaceholder:
    "e.g. A rollout schedule page with three phases, each with duration and goals",
  aiAddCreate: "Generate & add",
  aiAddCreating: "Generating… (1–2 min)",

  deckDialogTitle: "Decks",
  thisDeck: "This deck “{title}”",
  shareLink: "Create share link",
  shareLinkTitle: "Saves to the server and copies a link anyone can open",
  saving: "Saving…",
  saveJson: "Save as file (JSON)",
  saveJsonTitle: "Download as a JSON file for backup",
  openSection: "Open",
  openFile: "Open a file (JSON / PDF)",
  openFileTitle: "JSON loads as-is; PDFs are decomposed into background art + editable text",
  importingPdf: "Decomposing PDF… (~1 min/page)",
  linkCopied: "Share link copied:",
  noSavedDecks: "No saved decks yet",
  openDeckFailed: "Could not open the deck",
  saveFailed: "Save failed",
  importFailed: "Import failed",
  jsonReadFailed: "Could not read the JSON file",
  pdfImportFailed: "PDF import failed",

  slideSettings: "Slide settings",
  background: "Background",
  baseColor: "Base color",
  decoration: "Decoration",
  bgImageUrl: "Background image URL",
  aiEdit: "AI edit",
  decompose: "✦ Split into layers",
  decomposing: "Splitting…",
  decomposeTitle: "Splits the background into individually editable object layers (2–3 min)",
  layersLabel: "Layers",
  layerBg: "Background",
  decomposeFailed: "Decomposition failed",
  slideName: "Slide name",
  editorHint:
    "Click an element to edit its details. Double-click to edit text inline, drag to move.",
  textEl: "Text",
  shapeEl: "Shape",
  imageEl: "Image",
  toBack: "Send backward",
  toFront: "Bring forward",
  posSize: "Position & size",
  rotation: "Rotation",
  opacity: "Opacity",
  rewritePlaceholder: "Instruction for AI (empty = just polish)",
  rewriteTitle: "Rewrites just this text with AI (keeps roughly the same length)",
  rewriteFailed: "Rewrite failed",
  typography: "Typography",
  fontSize: "Size",
  lineHeight: "Leading",
  fontWeight: "Weight",
  align: "Align",
  alignLeft: "L",
  alignCenter: "C",
  alignRight: "R",
  fontLabel: "Font",
  fontHeading: "Heading",
  fontBody: "Body",
  colorLabel: "Color",
  customColor: "Custom color",
  shapeKind: "Kind",
  shapeRect: "Rectangle",
  shapeEllipse: "Ellipse",
  shapeLine: "Line",
  fill: "Fill",
  cornerRadius: "Radius",
  strokeColor: "Stroke",
  strokeWidth: "Stroke width",
  imageUrl: "URL",
  fit: "Fit",
  fitCover: "Cover",
  fitContain: "Contain",
  removeBg: "✦ Remove background",
  cutting: "Cutting out…",
  removeBgTitle: "Cuts out the subject as a transparent PNG (30–90 s)",
  removeBgFailed: "Background removal failed",
  remakePlaceholder: "Instruction to regenerate this image",
  remakeImgTitle: "Regenerates just this image in place (30–90 s)",
  remakeImgFailed: "Regeneration failed",
  hyperlink: "Hyperlink",
  internalLink: "Internal link",
  linkNone: "None",
  linkNote: "Links are preserved in exported PDFs.",

  themeTitle: "Theme",
  presets: "Presets",
  colorTokens: "Color tokens",
  fonts: "Fonts",
  headingFontLabel: "Heading",
  bodyFontLabel: "Body",

  giTitle: "Generate an image part",
  giIntro: "Generates one illustration/icon/photo-style asset onto the selected slide.",
  giPlaceholder: "e.g. flat illustration of a stethoscope, soft green palette, minimal lines",
  giTransparent: "Transparent background (easy to layer)",
  giSquare: "Square",
  giLandscape: "Landscape",
  giPortrait: "Portrait",
  giCreate: "Generate & place",
  giCreating: "Generating… (30–90 s)",

  printNoDeck: "No deck found. Create one in the editor first.",
  printSave: "Print / Save as PDF",
  printHint:
    'In the print dialog choose "Save as PDF", margins: none, background graphics: on. Hyperlinks (external & internal) are preserved.',

  tabSlides: "P",
  tabTheme: "T",

  presetNone: "None",
  presetMesh: "Mesh",
  presetBlobs: "Blobs",
  presetDiagonal: "Diagonal",
  presetGrid: "Grid",
  presetWaves: "Waves",
  presetDots: "Dots",
  presetFrame: "Frame",
  presetRings: "Rings",
  presetStripes: "Stripes",
  presetCorner: "Corner",
  presetSparkle: "Sparkle",

  colorBrand: "Brand",
  colorBrandDark: "Brand (dark)",
  colorBrandSoft: "Brand (soft)",
  colorAccent: "Accent",
  colorBg: "Background",
  colorSurface: "Surface",
  colorInk: "Ink",
  colorMuted: "Muted",
  colorLine: "Line",
};

export type MessageKey = keyof typeof ja;
const dicts: Record<Locale, Record<MessageKey, string>> = { ja, en };

let current: Locale | null = null;
const listeners = new Set<() => void>();

function detect(): Locale {
  if (typeof window === "undefined") return "ja";
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved === "ja" || saved === "en") return saved;
  return navigator.language?.toLowerCase().startsWith("ja") ? "ja" : "en";
}

export function getLocale(): Locale {
  if (current === null) current = detect();
  return current;
}

export function setLocale(l: Locale) {
  current = l;
  try {
    localStorage.setItem(STORAGE_KEY, l);
  } catch {}
  listeners.forEach((f) => f());
}

export function useLocale(): Locale {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    getLocale,
    () => "ja",
  );
}

// t("key") / t("key", { n: 3 })
export function useT() {
  const locale = useLocale();
  return (key: MessageKey, vars?: Record<string, string | number>) => {
    let s = dicts[locale][key] ?? dicts.ja[key];
    if (vars) for (const [k, v] of Object.entries(vars)) s = s.replace(`{${k}}`, String(v));
    return s;
  };
}

// プリセット/カラートークンの表示名キー(値はlib/theme.tsの定義と対応)
export const PRESET_LABEL_KEYS: Record<string, MessageKey> = {
  none: "presetNone",
  mesh: "presetMesh",
  blobs: "presetBlobs",
  diagonal: "presetDiagonal",
  grid: "presetGrid",
  waves: "presetWaves",
  dots: "presetDots",
  frame: "presetFrame",
  rings: "presetRings",
  stripes: "presetStripes",
  corner: "presetCorner",
  sparkle: "presetSparkle",
};

export const COLOR_LABEL_KEYS: Record<string, MessageKey> = {
  brand: "colorBrand",
  brandDark: "colorBrandDark",
  brandSoft: "colorBrandSoft",
  accent: "colorAccent",
  bg: "colorBg",
  surface: "colorSurface",
  ink: "colorInk",
  muted: "colorMuted",
  line: "colorLine",
};
