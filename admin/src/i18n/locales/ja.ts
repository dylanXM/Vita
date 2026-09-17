// 日本語 — mirrors the key set in en.ts.
const ja = {
  brand: "Vita Admin",

  common: {
    loading: "読み込み中…",
    language: "言語",
    toggleTheme: "テーマを切り替え",
    admin: "管理者",
    signOut: "サインアウト",
    somethingWrong: "エラーが発生しました",
    notFound: "このページは存在しません。",
    backToDashboard: "ダッシュボードに戻る",
    refresh: "更新",
    failedToLoad: "読み込みに失敗しました。",
  },

  nav: {
    overview: "概要",
    dashboard: "ダッシュボード",
  },

  login: {
    subtitle: "管理者アカウントでサインインしてください",
    email: "メールアドレス",
    password: "パスワード",
    signIn: "サインイン",
    signingIn: "サインイン中…",
    emailInvalid: "有効なメールアドレスを入力してください",
    passwordRequired: "パスワードを入力してください",
    welcome: "おかえりなさい",
    notAdmin: "このアカウントは管理者ではありません。",
    failed: "サインインに失敗しました",
    hint: "アカウントは TOVIDEO_ADMIN_EMAIL / TOVIDEO_ADMIN_PASSWORD から初期化されます。",
  },

  dashboard: {
    title: "ダッシュボード",
    desc: "Vita データベースから直接読み取ったリアルタイム集計です。",
    users: "総ユーザー数",
    usersSub: "管理者 {{admins}} 名",
    newUsers7d: "新規ユーザー(7日間)",
    newUsers7dSub: "過去 7 日間の登録",
    companions: "コンパニオン",
    companionsSub: "過去 7 日間で {{n}} 件",
    conversations: "会話",
    conversationsSub: "過去 7 日間で {{n}} 件",
    messages: "メッセージ",
    messagesSub: "過去 7 日間で {{n}} 件",
    memories: "メモリー",
    memoriesSub: "長期メモリーの件数",
    lifeEvents: "ライフイベント",
    lifeEventsSub: "本日の予定 {{n}} 件",
    systemInfo: "システム",
    apiVersion: "API バージョン",
    environment: "環境",
    generatedAt: "取得時刻",
    dataNote: "すべての数値は現在のテーブルに対するリアルタイム COUNT です。更新すると再取得します。",
  },

  time: {
    justNow: "たった今",
    minutesAgo: "{{n}} 分前",
    hoursAgo: "{{n}} 時間前",
    daysAgo: "{{n}} 日前",
  },
};

export default ja;
