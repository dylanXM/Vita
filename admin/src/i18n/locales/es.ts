// Español — mirrors the key set in en.ts.
const es = {
  brand: "Vita Admin",

  common: {
    loading: "Cargando…",
    language: "Idioma",
    toggleTheme: "Cambiar tema",
    admin: "Administrador",
    signOut: "Cerrar sesión",
    somethingWrong: "Algo salió mal",
    notFound: "Esta página no existe.",
    backToDashboard: "Volver al panel",
    refresh: "Actualizar",
    failedToLoad: "No se pudo cargar.",
  },

  nav: {
    overview: "Resumen",
    dashboard: "Panel",
  },

  login: {
    subtitle: "Inicia sesión con una cuenta de administrador",
    email: "Correo electrónico",
    password: "Contraseña",
    signIn: "Iniciar sesión",
    signingIn: "Iniciando sesión…",
    emailInvalid: "Introduce un correo válido",
    passwordRequired: "La contraseña es obligatoria",
    welcome: "Bienvenido de nuevo",
    notAdmin: "Esta cuenta no es de administrador.",
    failed: "Error al iniciar sesión",
    hint: "La cuenta se crea desde TOVIDEO_ADMIN_EMAIL / TOVIDEO_ADMIN_PASSWORD.",
  },

  dashboard: {
    title: "Panel",
    desc: "Recuentos en vivo leídos directamente de la base de datos de Vita.",
    users: "Usuarios",
    usersSub: "{{admins}} administradores",
    newUsers7d: "Nuevos usuarios (7d)",
    newUsers7dSub: "Registrados en los últimos 7 días",
    companions: "Compañeros",
    companionsSub: "{{n}} nuevos en los últimos 7 días",
    conversations: "Conversaciones",
    conversationsSub: "{{n}} nuevas en los últimos 7 días",
    messages: "Mensajes",
    messagesSub: "{{n}} nuevos en los últimos 7 días",
    memories: "Recuerdos",
    memoriesSub: "Entradas de memoria a largo plazo",
    lifeEvents: "Eventos de vida",
    lifeEventsSub: "{{n}} programados para hoy",
    systemInfo: "Sistema",
    apiVersion: "Versión de la API",
    environment: "Entorno",
    generatedAt: "Recopilado a las",
    dataNote: "Todas las cifras son un COUNT en vivo de las tablas actuales. Actualiza para releer.",
  },

  time: {
    justNow: "ahora mismo",
    minutesAgo: "hace {{n}} min",
    hoursAgo: "hace {{n}} h",
    daysAgo: "hace {{n}} d",
  },
};

export default es;
