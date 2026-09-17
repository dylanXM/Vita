// 한국어 — mirrors the key set in en.ts.
const ko = {
  brand: "Vita Admin",

  common: {
    loading: "불러오는 중…",
    language: "언어",
    toggleTheme: "테마 전환",
    admin: "관리자",
    signOut: "로그아웃",
    somethingWrong: "문제가 발생했습니다",
    notFound: "존재하지 않는 페이지입니다.",
    backToDashboard: "대시보드로 돌아가기",
    refresh: "새로고침",
    failedToLoad: "불러오지 못했습니다.",
  },

  nav: {
    overview: "개요",
    dashboard: "대시보드",
  },

  login: {
    subtitle: "관리자 계정으로 로그인하세요",
    email: "이메일",
    password: "비밀번호",
    signIn: "로그인",
    signingIn: "로그인 중…",
    emailInvalid: "올바른 이메일을 입력하세요",
    passwordRequired: "비밀번호를 입력하세요",
    welcome: "다시 오신 것을 환영합니다",
    notAdmin: "이 계정은 관리자가 아닙니다.",
    failed: "로그인 실패",
    hint: "계정은 TOVIDEO_ADMIN_EMAIL / TOVIDEO_ADMIN_PASSWORD 로 초기화됩니다.",
  },

  dashboard: {
    title: "대시보드",
    desc: "Vita 데이터베이스에서 직접 읽은 실시간 집계입니다.",
    users: "전체 사용자",
    usersSub: "관리자 {{admins}}명",
    newUsers7d: "신규 사용자 (7일)",
    newUsers7dSub: "최근 7일 내 가입",
    companions: "컴패니언",
    companionsSub: "최근 7일간 {{n}}개",
    conversations: "대화",
    conversationsSub: "최근 7일간 {{n}}개",
    messages: "메시지",
    messagesSub: "최근 7일간 {{n}}개",
    memories: "메모리",
    memoriesSub: "장기 메모리 항목",
    lifeEvents: "생활 이벤트",
    lifeEventsSub: "오늘 예정 {{n}}건",
    systemInfo: "시스템",
    apiVersion: "API 버전",
    environment: "환경",
    generatedAt: "수집 시각",
    dataNote: "모든 수치는 현재 테이블에 대한 실시간 COUNT 입니다. 새로고침하면 다시 읽습니다.",
  },

  time: {
    justNow: "방금",
    minutesAgo: "{{n}}분 전",
    hoursAgo: "{{n}}시간 전",
    daysAgo: "{{n}}일 전",
  },
};

export default ko;
