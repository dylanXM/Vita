/**
 * i18next initialisation for the admin dashboard.
 *
 * Eight languages: English, Simplified/Traditional Chinese, Japanese, Korean,
 * Portuguese (pt-BR), Spanish and Arabic. Arabic is right-to-left (RTL) — the
 * document `dir` is flipped accordingly (see `syncHtmlLang`). The chosen locale
 * is persisted under `vita_admin_locale` (mirrors how the theme store keeps
 * `vita_admin_theme`), so the preference survives reloads. First visit defaults
 * to English; only a stored value overrides (the browser language is not
 * auto-detected, matching the reference dashboard).
 */
import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import LanguageDetector from "i18next-browser-languagedetector";

import en from "./locales/en";
import zhHans from "./locales/zh-Hans";
import zhHant from "./locales/zh-Hant";
import ja from "./locales/ja";
import ko from "./locales/ko";
import pt from "./locales/pt";
import es from "./locales/es";
import ar from "./locales/ar";

export const LOCALE_STORAGE_KEY = "vita_admin_locale";
export const SUPPORTED_LOCALES = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "pt", "es", "ar"] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/** Human labels for the switcher — each shown in its own language. */
export const LOCALE_LABELS: Record<SupportedLocale, string> = {
  en: "English",
  "zh-Hans": "简体中文",
  "zh-Hant": "繁體中文",
  ja: "日本語",
  ko: "한국어",
  pt: "Português",
  es: "Español",
  ar: "العربية",
};

function readStoredLocale(): SupportedLocale | undefined {
  try {
    const v = localStorage.getItem(LOCALE_STORAGE_KEY);
    if (v && (SUPPORTED_LOCALES as readonly string[]).includes(v)) return v as SupportedLocale;
  } catch {
    /* localStorage may be unavailable */
  }
  return undefined;
}

void i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { translation: en },
      "zh-Hans": { translation: zhHans },
      "zh-Hant": { translation: zhHant },
      ja: { translation: ja },
      ko: { translation: ko },
      pt: { translation: pt },
      es: { translation: es },
      ar: { translation: ar },
    },
    lng: readStoredLocale() ?? "en",
    fallbackLng: "en",
    supportedLngs: SUPPORTED_LOCALES as unknown as string[],
    interpolation: { escapeValue: false },
    detection: {
      // First visit → English; only a stored `vita_admin_locale` overrides.
      order: ["localStorage"],
      lookupLocalStorage: LOCALE_STORAGE_KEY,
      caches: ["localStorage"],
    },
  });

/** Locales that read right-to-left — the document `dir` flips for these. */
export const RTL_LOCALES = ["ar"] as const;

/** Keep the document <html lang>/<dir> in sync for a11y / layout mirroring. */
function syncHtmlLang(lng: string) {
  try {
    document.documentElement.lang = lng;
    document.documentElement.dir = (RTL_LOCALES as readonly string[]).includes(lng) ? "rtl" : "ltr";
  } catch {
    /* no document — ignore */
  }
}
syncHtmlLang(i18n.resolvedLanguage || i18n.language || "en");
i18n.on("languageChanged", syncHtmlLang);

/** Synchronous best-effort locale read (e.g. for the axios Accept-Language). */
export function getLocale(): string {
  try {
    return i18n.resolvedLanguage || i18n.language || "en";
  } catch {
    return "en";
  }
}

export function setLocale(locale: SupportedLocale): Promise<unknown> {
  try {
    localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  } catch {
    /* localStorage may be disabled — ignore */
  }
  return i18n.changeLanguage(locale);
}

export default i18n;
