import { ChevronLeft, ChevronRight, MoreHorizontal } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

/** Compact windowed page list: e.g. 1 … 4 5 6 … 20 */
function pageList(current: number, total: number): (number | "…")[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const candidates = [1, 2, current - 1, current, current + 1, total - 1, total].filter(
    (p) => p >= 1 && p <= total,
  );
  const sorted = [...new Set(candidates)].sort((a, b) => a - b);
  const out: (number | "…")[] = [];
  let prev = 0;
  for (const p of sorted) {
    if (p - prev > 1) out.push("…");
    out.push(p);
    prev = p;
  }
  return out;
}

export function Pagination({
  page,
  totalPages,
  total,
  onChange,
}: {
  page: number;
  totalPages: number;
  total: number;
  onChange: (page: number) => void;
}) {
  const { t } = useTranslation();
  if (totalPages <= 1) return null;

  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-muted-foreground">
        {t("users.total", { total })}
        <span className="mx-2 text-border">|</span>
        {t("users.pageInfo", { page, pages: totalPages })}
      </p>
      <div className="flex items-center gap-1">
        <Button
          variant="outline"
          size="sm"
          disabled={page <= 1}
          onClick={() => onChange(page - 1)}
        >
          <ChevronLeft />
          {t("users.previous")}
        </Button>
        {pageList(page, totalPages).map((p, i) =>
          p === "…" ? (
            <span
              key={`gap-${i}`}
              className="flex size-8 items-center justify-center text-muted-foreground"
            >
              <MoreHorizontal className="size-4" />
            </span>
          ) : (
            <Button
              key={p}
              variant={p === page ? "default" : "outline"}
              size="sm"
              className={cn(p === page && "pointer-events-none")}
              onClick={() => onChange(p)}
            >
              {p}
            </Button>
          ),
        )}
        <Button
          variant="outline"
          size="sm"
          disabled={page >= totalPages}
          onClick={() => onChange(page + 1)}
        >
          {t("users.next")}
          <ChevronRight />
        </Button>
      </div>
    </div>
  );
}
