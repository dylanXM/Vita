import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { Activity, HeartHandshake, MessageCircle, RefreshCw, ShoppingBag, UserRoundPlus } from "lucide-react";
import { statsApi } from "@/api/admin";
import type { ProductMetrics } from "@/api/types";
import { StatCard } from "@/components/stat-card";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatNumber } from "@/lib/format";

function percentage(part: number | undefined, total: number | undefined): string {
  if (part === undefined || !total) return "—";
  return `${((part / total) * 100).toFixed(1)}%`;
}

function ratio(part: number | undefined, total: number | undefined): string {
  if (part === undefined || total === undefined) return "—";
  return `${formatNumber(part)} / ${formatNumber(total)}`;
}

export function ProductMetricsPanel() {
  const { t } = useTranslation();
  const [days, setDays] = useState<7 | 30>(7);
  const query = useQuery({
    queryKey: ["admin-product-metrics", days],
    queryFn: ({ signal }) => statsApi.product(days, signal),
    staleTime: 300_000,
    refetchInterval: 300_000,
  });
  const data: ProductMetrics | undefined = query.data;

  return (
    <section className="space-y-4" aria-label={t("productMetrics.title")}>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">{t("productMetrics.title")}</h2>
          <p className="text-sm text-muted-foreground">{t("productMetrics.description")}</p>
          {data && <p className="mt-1 text-xs tabular-nums text-muted-foreground">{data.window_start} – {data.daily.at(-1)?.date}</p>}
        </div>
        <div className="flex gap-2">
          {([7, 30] as const).map((n) => (
            <Button key={n} size="sm" variant={days === n ? "default" : "outline"}
              aria-pressed={days === n} onClick={() => setDays(n)}>
              {t("productMetrics.days", { count: n })}
            </Button>
          ))}
          <Button size="sm" variant="outline" onClick={() => void query.refetch()} disabled={query.isFetching}>
            <RefreshCw className={query.isFetching ? "animate-spin" : undefined} />
            {t("common.refresh")}
          </Button>
        </div>
      </div>

      {query.isError && <Card className="border-destructive/40"><CardContent className="p-5 text-sm text-destructive">{t("common.failedToLoad")}</CardContent></Card>}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label={t("productMetrics.activeUsers")} value={formatNumber(data?.active_users)}
          sub={t("productMetrics.activeUsersNote")} icon={Activity} loading={query.isLoading} accent />
        <StatCard label={t("productMetrics.payingRate")} value={percentage(data?.paying_users, data?.active_users)}
          sub={ratio(data?.paying_users, data?.active_users)} icon={ShoppingBag} loading={query.isLoading} />
        <StatCard label={t("productMetrics.activatedRate")} value={percentage(data?.activated_new_users, data?.new_users)}
          sub={ratio(data?.activated_new_users, data?.new_users)} icon={UserRoundPlus} loading={query.isLoading} />
        <StatCard label={t("productMetrics.meaningfulRepeatRate")} value={percentage(data?.meaningful_repeat_users, data?.active_users)}
          sub={ratio(data?.meaningful_repeat_users, data?.active_users)} icon={HeartHandshake} loading={query.isLoading} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card><CardHeader><CardTitle>{t("productMetrics.retention")}</CardTitle></CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            <Metric label={t("productMetrics.d1")} value={percentage(data?.d1.retained_users, data?.d1.cohort_users)} detail={ratio(data?.d1.retained_users, data?.d1.cohort_users)} />
            <Metric label={t("productMetrics.d7")} value={percentage(data?.d7.retained_users, data?.d7.cohort_users)} detail={ratio(data?.d7.retained_users, data?.d7.cohort_users)} />
            <Metric label={t("productMetrics.repeatActive")} value={percentage(data?.repeat_active_users, data?.active_users)} detail={ratio(data?.repeat_active_users, data?.active_users)} />
            <Metric label={t("productMetrics.dauMau")} value={percentage(data?.active_yesterday, data?.active_30d)} detail={ratio(data?.active_yesterday, data?.active_30d)} />
          </CardContent>
        </Card>
        <Card><CardHeader><CardTitle>{t("productMetrics.firstActions")}</CardTitle></CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            <Metric label={t("productMetrics.newUsers")} value={formatNumber(data?.new_users)} />
            <Metric label={t("productMetrics.firstChat")} value={percentage(data?.new_chat_users, data?.new_users)} detail={ratio(data?.new_chat_users, data?.new_users)} />
            <Metric label={t("productMetrics.firstVisit")} value={percentage(data?.new_visit_users, data?.new_users)} detail={ratio(data?.new_visit_users, data?.new_users)} />
            <Metric label={t("productMetrics.messagesPerActive")} value={data?.active_users ? (data.messages / data.active_users).toFixed(1) : "—"} detail={t("productMetrics.messagesCount", { count: data?.messages ?? 0 })} />
          </CardContent>
        </Card>
        <Card><CardHeader><CardTitle>{t("productMetrics.monetization")}</CardTitle></CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            <Metric label={t("productMetrics.payingUsers")} value={formatNumber(data?.paying_users)} />
            <Metric label={t("productMetrics.purchases")} value={formatNumber(data?.purchases)} />
            <Metric label={t("productMetrics.subscriptions")} value={formatNumber(data?.subscription_purchases)} />
            <Metric label={t("productMetrics.coinPacks")} value={formatNumber(data?.coin_pack_purchases)} />
          </CardContent>
        </Card>
        <Card><CardHeader><CardTitle>{t("productMetrics.experience")}</CardTitle></CardHeader>
          <CardContent className="grid grid-cols-2 gap-4">
            <Metric label={t("productMetrics.visits")} value={formatNumber(data?.visits)} />
            <Metric label={t("productMetrics.gifts")} value={formatNumber(data?.gifts)} />
            <Metric label={t("productMetrics.completionRate")} value={percentage(data?.completed_experiences, data?.due_experiences)} detail={ratio(data?.completed_experiences, data?.due_experiences)} />
            <Metric label={t("productMetrics.amountCoverage")} value={percentage(data?.purchases_with_amount, data?.purchases)} detail={ratio(data?.purchases_with_amount, data?.purchases)} />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle className="flex items-center gap-2"><MessageCircle className="size-4" />{t("productMetrics.daily")}</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[650px] text-left text-sm tabular-nums">
            <thead><tr className="border-b text-xs text-muted-foreground">
              {["date", "activeUsers", "newUsers", "payingUsers", "messages", "visits", "gifts"].map((key) =>
                <th key={key} className="px-2 py-2 font-medium">{t(`productMetrics.${key}`)}</th>)}</tr></thead>
            <tbody>{[...(data?.daily ?? [])].reverse().map((day) => <tr key={day.date} className="border-b last:border-0">
              <td className="px-2 py-2">{day.date}</td>
              <td className="px-2 py-2">{formatNumber(day.active_users)}</td>
              <td className="px-2 py-2">{formatNumber(day.new_users)}</td>
              <td className="px-2 py-2">{formatNumber(day.paying_users)}</td>
              <td className="px-2 py-2">{formatNumber(day.messages)}</td>
              <td className="px-2 py-2">{formatNumber(day.visits)}</td>
              <td className="px-2 py-2">{formatNumber(day.gifts)}</td>
            </tr>)}</tbody>
          </table>
        </CardContent>
      </Card>
      <div className="space-y-1 text-xs leading-relaxed text-muted-foreground">
        <p>{t("productMetrics.method")}</p>
        <p>{t("productMetrics.cohortNote")}</p>
        <p>{t("productMetrics.revenueNote")}</p>
      </div>
    </section>
  );
}

function Metric({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return <div className="min-w-0 border-l-2 border-primary/30 pl-3">
    <p className="text-xs text-muted-foreground">{label}</p>
    <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
    {detail && <p className="text-xs text-muted-foreground">{detail}</p>}
  </div>;
}
