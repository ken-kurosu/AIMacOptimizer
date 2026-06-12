import { NextRequest, NextResponse } from "next/server";

// 簡易トークン認証。COMPDECK_API_TOKEN を設定した環境(共有サーバー等)でのみ有効。
// 未設定ならすべて素通し(ローカル開発)。
//  - APIクライアント(Slackエージェント等): Authorization: Bearer <token>
//  - ブラウザ: 初回だけ ?token=<token> 付きで開くとCookieに保存され、以後は素のURLでOK
//    (/api/decks が返す editUrl には自動でtokenが付くので、Slackからワンクリックで開ける)
export function proxy(req: NextRequest) {
  const token = process.env.COMPDECK_API_TOKEN;
  if (!token) return NextResponse.next();

  const url = req.nextUrl;
  const queryToken = url.searchParams.get("token");
  if (queryToken === token) {
    // トークン付きURL → Cookieを焼いてURLからは消す
    url.searchParams.delete("token");
    const res = NextResponse.redirect(url);
    res.cookies.set("compdeck_token", token, {
      httpOnly: true,
      sameSite: "lax",
      maxAge: 60 * 60 * 24 * 365,
    });
    return res;
  }

  if (req.headers.get("authorization") === `Bearer ${token}`) return NextResponse.next();
  if (req.cookies.get("compdeck_token")?.value === token) return NextResponse.next();

  if (url.pathname.startsWith("/api/")) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  return new NextResponse(
    "Access requires a token: open this URL once with ?token=<shared token> appended.\nアクセスするには ?token=<共有されたトークン> を付けてこのURLを一度開いてください。",
    { status: 401, headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
}

export const config = {
  // 静的アセットは素通し(認証はページとAPIに対してかける)
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
