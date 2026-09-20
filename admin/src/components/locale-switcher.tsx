import { Languages, Check } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { setLocale, SUPPORTED_LOCALES, LOCALE_LABELS, type SupportedLocale } from "@/i18n";
import { cn } from "@/lib/utils";

/** Header language picker — Admin supports English and Simplified Chinese. */
export function LocaleSwitcher() {
  const { t, i18n } = useTranslation();
  const current = ((i18n.resolvedLanguage || i18n.language) as SupportedLocale) || "en";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" title={t("common.language")}>
          <Languages className="size-4" />
          <span className="sr-only">{t("common.language")}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-40">
        {SUPPORTED_LOCALES.map((loc) => (
          <DropdownMenuItem key={loc} onClick={() => void setLocale(loc)} className="justify-between">
            {LOCALE_LABELS[loc]}
            <Check className={cn("size-4", loc === current ? "opacity-100" : "opacity-0")} />
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
