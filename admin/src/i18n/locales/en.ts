// English — the master key set. Every other locale mirrors this structure.
const en = {
  brand: "Vita Admin",

  common: {
    loading: "Loading…",
    language: "Language",
    toggleTheme: "Toggle theme",
    admin: "Administrator",
    signOut: "Sign out",
    somethingWrong: "Something went wrong",
    notFound: "This page doesn't exist.",
    backToDashboard: "Back to dashboard",
    refresh: "Refresh",
    failedToLoad: "Failed to load.",
  },

  nav: {
    overview: "Overview",
    dashboard: "Dashboard",
  },

  login: {
    subtitle: "Sign in with an administrator account",
    email: "Email",
    password: "Password",
    signIn: "Sign in",
    signingIn: "Signing in…",
    emailInvalid: "Enter a valid email",
    passwordRequired: "Password is required",
    welcome: "Welcome back",
    notAdmin: "This account is not an administrator.",
    failed: "Sign-in failed",
    hint: "Seeded from VITA_ADMIN_EMAIL / VITA_ADMIN_PASSWORD.",
  },

  dashboard: {
    title: "Dashboard",
    desc: "Live counts read straight from the Vita database.",
    users: "Users",
    usersSub: "{{admins}} administrators",
    newUsers7d: "New users (7d)",
    newUsers7dSub: "Registered in the last 7 days",
    companions: "Companions",
    companionsSub: "{{n}} new in the last 7 days",
    conversations: "Conversations",
    conversationsSub: "{{n}} new in the last 7 days",
    messages: "Messages",
    messagesSub: "{{n}} new in the last 7 days",
    memories: "Memories",
    memoriesSub: "Long-term memory entries",
    lifeEvents: "Life events",
    lifeEventsSub: "{{n}} scheduled today",
    systemInfo: "System",
    apiVersion: "API version",
    environment: "Environment",
    generatedAt: "Collected at",
    dataNote: "Every figure is a live COUNT over the current tables. Refresh to re-read.",
  },

  time: {
    justNow: "just now",
    minutesAgo: "{{n}}m ago",
    hoursAgo: "{{n}}h ago",
    daysAgo: "{{n}}d ago",
  },
};

export default en;
