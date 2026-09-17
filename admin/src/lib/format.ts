/** Number / date formatting helpers shared across pages. */
import i18n, { getLocale } from "@/i18n";

/** Map the UI locale to a BCP-47 tag Intl understands. */
export function intlLocale(): string {
  switch (getLocale()) {
    case "zh-Hans":
      return "zh-CN";
    case "zh-Hant":
      return "zh-TW";
    case "ja":
      return "ja-JP";
    case "ko":
      return "ko-KR";
    case "pt":
      return "pt-BR";
    case "es":
      return "es-ES";
    case "ar":
      return "ar";
    default:
      return "en-US";
  }
}

export function formatNumber(n: number | null | undefined): string {
  if (n == null) return "0";
  return new Intl.NumberFormat(intlLocale()).format(n);
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleString(intlLocale(), {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/** True only for a real, post-epoch timestamp (rejects the Go zero value). */
function isValidEpoch(iso: string | null | undefined): iso is string {
  if (!iso) return false;
  const t = new Date(iso).getTime();
  return !Number.isNaN(t) && t > 0;
}

export function relativeTime(iso: string | null | undefined): string {
  if (!isValidEpoch(iso)) return "—";
  const diff = Date.now() - new Date(iso).getTime();
  const sec = Math.round(diff / 1000);
  const min = Math.round(sec / 60);
  const hr = Math.round(min / 60);
  const day = Math.round(hr / 24);
  if (sec < 60) return i18n.t("time.justNow");
  if (min < 60) return i18n.t("time.minutesAgo", { n: min });
  if (hr < 24) return i18n.t("time.hoursAgo", { n: hr });
  if (day < 30) return i18n.t("time.daysAgo", { n: day });
  return formatDate(iso);
}
