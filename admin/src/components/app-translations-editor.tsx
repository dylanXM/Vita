import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export const APP_COPY_LOCALES = [
  ["en", "English"], ["zh-Hans", "简体中文"], ["zh-Hant", "繁體中文"],
  ["ja", "日本語"], ["ko", "한국어"], ["pt", "Português"], ["es", "Español"], ["ar", "العربية"],
] as const;
export function localizedValue(values: Record<string, string>, locale: string) {
  return values[locale] ?? (locale === "zh-Hans" ? values.zh_CN ?? values.zh : locale === "zh-Hant" ? values.zh_TW : undefined) ?? "";
}
export function AppTranslationsEditor({ fields, onChange }: {
  fields: { key: string; label: string; values: Record<string, string>; multiline?: boolean; placeholder?: string }[];
  onChange: (field: string, locale: string, value: string) => void;
}) {
  const { t } = useTranslation();
  const [locale, setLocale] = useState("zh-Hans");
  return <section className="space-y-4 rounded-xl border p-3 sm:col-span-2 md:col-span-2">
    <div className="flex flex-wrap items-center justify-between gap-3"><h3 className="text-sm font-semibold">{t("content.translations")}</h3><div className="flex flex-wrap gap-1" role="group" aria-label={t("content.translations")}>{APP_COPY_LOCALES.map(([key, label]) => <button key={key} type="button" aria-pressed={locale === key} onClick={() => setLocale(key)} className={`rounded px-2 py-1 text-xs ${locale === key ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:text-foreground"}`}>{label}</button>)}</div></div>
    {fields.map(field => <div key={field.key} className="space-y-1.5"><Label htmlFor={`${field.key}-${locale}`}>{field.label}</Label>{field.multiline ? <textarea id={`${field.key}-${locale}`} dir={locale === "ar" ? "rtl" : undefined} className="min-h-24 w-full rounded-md border bg-background px-3 py-2 text-sm" value={localizedValue(field.values, locale)} placeholder={field.placeholder} onChange={e => onChange(field.key, locale, e.target.value)} /> : <Input id={`${field.key}-${locale}`} dir={locale === "ar" ? "rtl" : undefined} value={localizedValue(field.values, locale)} placeholder={field.placeholder} onChange={e => onChange(field.key, locale, e.target.value)} />}</div>)}
  </section>;
}
