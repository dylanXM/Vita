// العربية — mirrors the key set in en.ts. This locale is right-to-left.
const ar = {
  brand: "Vita Admin",

  common: {
    loading: "جارٍ التحميل…",
    language: "اللغة",
    toggleTheme: "تبديل المظهر",
    admin: "مدير",
    signOut: "تسجيل الخروج",
    somethingWrong: "حدث خطأ ما",
    notFound: "هذه الصفحة غير موجودة.",
    backToDashboard: "العودة إلى لوحة التحكم",
    refresh: "تحديث",
    failedToLoad: "فشل التحميل.",
  },

  nav: {
    overview: "نظرة عامة",
    dashboard: "لوحة التحكم",
  },

  login: {
    subtitle: "سجّل الدخول بحساب مدير",
    email: "البريد الإلكتروني",
    password: "كلمة المرور",
    signIn: "تسجيل الدخول",
    signingIn: "جارٍ تسجيل الدخول…",
    emailInvalid: "أدخل بريدًا إلكترونيًا صالحًا",
    passwordRequired: "كلمة المرور مطلوبة",
    welcome: "مرحبًا بعودتك",
    notAdmin: "هذا الحساب ليس حساب مدير.",
    failed: "فشل تسجيل الدخول",
    hint: "يُنشأ الحساب من VITA_ADMIN_EMAIL / VITA_ADMIN_PASSWORD.",
  },

  dashboard: {
    title: "لوحة التحكم",
    desc: "إحصاءات مباشرة تُقرأ من قاعدة بيانات Vita.",
    users: "المستخدمون",
    usersSub: "{{admins}} مدير",
    newUsers7d: "مستخدمون جدد (٧ أيام)",
    newUsers7dSub: "سُجّلوا خلال آخر ٧ أيام",
    companions: "الرفقاء",
    companionsSub: "{{n}} جديد خلال آخر ٧ أيام",
    conversations: "المحادثات",
    conversationsSub: "{{n}} جديدة خلال آخر ٧ أيام",
    messages: "الرسائل",
    messagesSub: "{{n}} جديدة خلال آخر ٧ أيام",
    memories: "الذكريات",
    memoriesSub: "مدخلات الذاكرة طويلة المدى",
    lifeEvents: "أحداث الحياة",
    lifeEventsSub: "{{n}} مجدولة اليوم",
    systemInfo: "النظام",
    apiVersion: "إصدار الواجهة",
    environment: "البيئة",
    generatedAt: "وُجمعت في",
    dataNote: "كل الأرقام هي COUNT مباشر على الجداول الحالية. حدّث لإعادة القراءة.",
  },

  time: {
    justNow: "الآن",
    minutesAgo: "قبل {{n}} دقيقة",
    hoursAgo: "قبل {{n}} ساعة",
    daysAgo: "قبل {{n}} يوم",
  },
};

export default ar;
