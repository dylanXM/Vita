// 繁體中文 — mirrors the key set in en.ts.
const zhHant = {
  brand: "Vita Admin",

  common: {
    loading: "載入中…",
    language: "語言",
    toggleTheme: "切換主題",
    admin: "管理員",
    signOut: "登出",
    somethingWrong: "發生錯誤",
    notFound: "此頁面不存在。",
    backToDashboard: "返回儀表板",
    refresh: "重新整理",
    failedToLoad: "載入失敗。",
  },

  nav: {
    overview: "總覽",
    dashboard: "儀表板",
  },

  login: {
    subtitle: "使用管理員帳號登入",
    email: "電子郵件",
    password: "密碼",
    signIn: "登入",
    signingIn: "登入中…",
    emailInvalid: "請輸入有效的電子郵件",
    passwordRequired: "請輸入密碼",
    welcome: "歡迎回來",
    notAdmin: "此帳號不是管理員。",
    failed: "登入失敗",
    hint: "帳號由 VITA_ADMIN_EMAIL / VITA_ADMIN_PASSWORD 初始化。",
  },

  dashboard: {
    title: "儀表板",
    desc: "直接讀取 Vita 資料庫的即時統計。",
    users: "使用者總數",
    usersSub: "管理員 {{admins}}",
    newUsers7d: "近 7 天新增使用者",
    newUsers7dSub: "近 7 天內註冊",
    companions: "伴侶",
    companionsSub: "近 7 天新增 {{n}}",
    conversations: "對話",
    conversationsSub: "近 7 天新增 {{n}}",
    messages: "訊息",
    messagesSub: "近 7 天新增 {{n}}",
    memories: "記憶",
    memoriesSub: "長期記憶條目",
    lifeEvents: "生活事件",
    lifeEventsSub: "今日安排 {{n}} 筆",
    systemInfo: "系統",
    apiVersion: "API 版本",
    environment: "執行環境",
    generatedAt: "擷取時間",
    dataNote: "所有數字都是對目前資料表的即時 COUNT，重新整理即可重新讀取。",
  },

  time: {
    justNow: "剛剛",
    minutesAgo: "{{n}} 分鐘前",
    hoursAgo: "{{n}} 小時前",
    daysAgo: "{{n}} 天前",
  },
};

export default zhHant;
