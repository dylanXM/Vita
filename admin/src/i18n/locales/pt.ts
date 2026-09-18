// Português (pt-BR) — mirrors the key set in en.ts.
const pt = {
  brand: "Vita Admin",

  common: {
    loading: "Carregando…",
    language: "Idioma",
    toggleTheme: "Alternar tema",
    admin: "Administrador",
    signOut: "Sair",
    somethingWrong: "Algo deu errado",
    notFound: "Esta página não existe.",
    backToDashboard: "Voltar ao painel",
    refresh: "Atualizar",
    failedToLoad: "Falha ao carregar.",
  },

  nav: {
    overview: "Visão geral",
    dashboard: "Painel",
  },

  login: {
    subtitle: "Entre com uma conta de administrador",
    email: "E-mail",
    password: "Senha",
    signIn: "Entrar",
    signingIn: "Entrando…",
    emailInvalid: "Informe um e-mail válido",
    passwordRequired: "A senha é obrigatória",
    welcome: "Bem-vindo de volta",
    notAdmin: "Esta conta não é de administrador.",
    failed: "Falha no login",
    hint: "A conta é criada a partir de VITA_ADMIN_EMAIL / VITA_ADMIN_PASSWORD.",
  },

  dashboard: {
    title: "Painel",
    desc: "Contagens em tempo real lidas diretamente do banco da Vita.",
    users: "Usuários",
    usersSub: "{{admins}} administradores",
    newUsers7d: "Novos usuários (7d)",
    newUsers7dSub: "Registrados nos últimos 7 dias",
    companions: "Companheiros",
    companionsSub: "{{n}} novos nos últimos 7 dias",
    conversations: "Conversas",
    conversationsSub: "{{n}} novas nos últimos 7 dias",
    messages: "Mensagens",
    messagesSub: "{{n}} novas nos últimos 7 dias",
    memories: "Memórias",
    memoriesSub: "Entradas de memória de longo prazo",
    lifeEvents: "Eventos de vida",
    lifeEventsSub: "{{n}} agendados para hoje",
    systemInfo: "Sistema",
    apiVersion: "Versão da API",
    environment: "Ambiente",
    generatedAt: "Coletado em",
    dataNote: "Todos os números são COUNT em tempo real das tabelas atuais. Atualize para reler.",
  },

  time: {
    justNow: "agora mesmo",
    minutesAgo: "há {{n}}min",
    hoursAgo: "há {{n}}h",
    daysAgo: "há {{n}}d",
  },
};

export default pt;
