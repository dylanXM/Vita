// 简体中文 — mirrors the key set in en.ts.
const zhHans = {
  brand: "Vita Admin",

  common: {
    loading: "加载中…",
    language: "语言",
    toggleTheme: "切换主题",
    admin: "管理员",
    signOut: "退出登录",
    somethingWrong: "出错了",
    notFound: "该页面不存在。",
    backToDashboard: "返回仪表盘",
    refresh: "刷新",
    failedToLoad: "加载失败。",
  },

  nav: {
    overview: "概览",
    dashboard: "仪表盘",
  },

  login: {
    subtitle: "使用管理员账号登录",
    email: "邮箱",
    password: "密码",
    signIn: "登录",
    signingIn: "登录中…",
    emailInvalid: "请输入有效的邮箱",
    passwordRequired: "请输入密码",
    welcome: "欢迎回来",
    notAdmin: "该账号不是管理员。",
    failed: "登录失败",
    hint: "帐号由 VITA_ADMIN_EMAIL / VITA_ADMIN_PASSWORD 初始化。",
  },

  dashboard: {
    title: "仪表盘",
    desc: "直接读取 Vita 数据库的实时统计。",
    users: "用户总数",
    usersSub: "管理员 {{admins}}",
    newUsers7d: "近 7 天新增用户",
    newUsers7dSub: "近 7 天内注册",
    companions: "伴侣",
    companionsSub: "近 7 天新增 {{n}}",
    conversations: "会话",
    conversationsSub: "近 7 天新增 {{n}}",
    messages: "消息",
    messagesSub: "近 7 天新增 {{n}}",
    memories: "记忆",
    memoriesSub: "长期记忆条目",
    lifeEvents: "生活事件",
    lifeEventsSub: "今日安排 {{n}} 条",
    systemInfo: "系统",
    apiVersion: "API 版本",
    environment: "运行环境",
    generatedAt: "采集时间",
    dataNote: "所有数字都是对当前数据表的实时 COUNT，刷新即可重新读取。",
  },

  time: {
    justNow: "刚刚",
    minutesAgo: "{{n}} 分钟前",
    hoursAgo: "{{n}} 小时前",
    daysAgo: "{{n}} 天前",
  },
};

export default zhHans;
