// pm2 用の起動定義。setup-macmini.sh から使われる。
// 環境変数(OPENAI_API_KEY / COMPDECK_API_TOKEN)は compdeck/.env.local から
// Next.js 自身が読み込む。ポートを変えたいときは args の -p を変更。
const path = require("path");

module.exports = {
  apps: [
    {
      name: "compdeck",
      cwd: path.join(__dirname, ".."),
      script: "node_modules/next/dist/bin/next",
      args: "start -p 3100",
      env: { NODE_ENV: "production" },
      max_restarts: 10,
      restart_delay: 3000,
    },
  ],
};
