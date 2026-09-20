import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { creditLedgerApi, envApi, purchasesApi } from "@/api/admin";
import { ENVIRONMENTS, type BillingPlatform, type BillingPurchase, type CreditLedgerEntry, type Environment } from "@/api/types";
import { formatDate } from "@/lib/format";

type ActivityPlatform = BillingPlatform | "system" | "all";
const PAGE_SIZE = 20;

export function BillingActivityPage() {
  const { t } = useTranslation();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [platform, setPlatform] = useState<ActivityPlatform>("all");
  const [tab, setTab] = useState<"purchases" | "ledger">("purchases");
  const [page, setPage] = useState(1);
  const activeEnv = environment ?? serverEnv.data?.environment;

  useEffect(() => { if (!environment && serverEnv.data?.environment) setEnvironment(serverEnv.data.environment); }, [environment, serverEnv.data]);
  useEffect(() => setPage(1), [environment, platform, tab]);

  const params = { environment: activeEnv!, platform: platform === "all" ? undefined : platform, page, page_size: PAGE_SIZE };
  const purchases = useQuery({
    queryKey: ["billing-purchases", params], queryFn: ({ signal }) => purchasesApi.list(params, signal),
    enabled: Boolean(activeEnv) && tab === "purchases",
  });
  const ledger = useQuery({
    queryKey: ["credit-ledger", params], queryFn: ({ signal }) => creditLedgerApi.list(params, signal),
    enabled: Boolean(activeEnv) && tab === "ledger",
  });
  const result = tab === "purchases" ? purchases : ledger;

  return <div className="space-y-6">
    <PageHeader title={t("billing.activityTitle")} description={t("billing.activityDesc")} />
    <Card><CardContent className="space-y-4 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex gap-2">
          <Button size="sm" variant={tab === "purchases" ? "default" : "outline"} onClick={() => setTab("purchases")}>{t("billing.purchases")}</Button>
          <Button size="sm" variant={tab === "ledger" ? "default" : "outline"} onClick={() => setTab("ledger")}>{t("billing.ledger")}</Button>
        </div>
        <div className="flex flex-wrap gap-3">
          <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}><SelectTrigger className="w-44"><SelectValue placeholder={t("billing.environment")} /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}</SelectContent></Select>
          <Select value={platform} onValueChange={(v) => setPlatform(v as ActivityPlatform)}><SelectTrigger className="w-44"><SelectValue /></SelectTrigger><SelectContent>
            <SelectItem value="all">{t("billing.allPlatforms")}</SelectItem>
            {(["ios","android","web","system"] as const).map((value) => <SelectItem key={value} value={value}>{t(`billing.platform.${value}`)}</SelectItem>)}
          </SelectContent></Select>
        </div>
      </div>
      {!activeEnv || result.isLoading ? <div className="space-y-3">{[1,2,3,4].map((n) => <Skeleton key={n} className="h-10" />)}</div>
        : result.isError ? <p className="py-8 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
        : tab === "purchases" ? <PurchasesTable rows={purchases.data?.items ?? []} /> : <LedgerTable rows={ledger.data?.items ?? []} />}
      {result.data && result.data.total_pages > 1 && <Pagination page={result.data.page} totalPages={result.data.total_pages} total={result.data.total} onChange={setPage} />}
    </CardContent></Card>
  </div>;
}

function PurchasesTable({ rows }: { rows: BillingPurchase[] }) {
  const { t } = useTranslation();
  if (!rows.length) return <p className="py-8 text-center text-sm text-muted-foreground">{t("billing.empty")}</p>;
  return <Table><TableHeader><TableRow>
    <TableHead>{t("billing.user")}</TableHead><TableHead>{t("billing.kind")}</TableHead><TableHead>{t("billing.productId")}</TableHead>
    <TableHead>{t("billing.platformLabel")}</TableHead><TableHead>{t("billing.amount")}</TableHead><TableHead>{t("billing.coins")}</TableHead>
    <TableHead>{t("billing.status")}</TableHead><TableHead>{t("billing.time")}</TableHead>
  </TableRow></TableHeader><TableBody>{rows.map((row) => <TableRow key={row.id}>
    <TableCell><div className="font-medium">{row.user_email}</div><div className="font-mono text-xs text-muted-foreground">{row.user_id.slice(0, 8)}</div></TableCell>
    <TableCell><Badge variant="outline">{t(`billing.kinds.${row.kind}`)}</Badge></TableCell><TableCell className="font-mono text-xs">{row.product_id || "—"}</TableCell>
    <TableCell>{t(`billing.platform.${row.platform}`)}</TableCell><TableCell>{row.amount_minor == null ? "—" : `${row.currency || "USD"} ${(row.amount_minor / 100).toFixed(2)}`}</TableCell>
    <TableCell>{row.credits.toLocaleString()}</TableCell><TableCell><Badge variant={row.status === "paid" ? "success" : "muted"}>{row.status || "—"}</Badge></TableCell>
    <TableCell className="whitespace-nowrap text-muted-foreground">{formatDate(row.purchased_at)}</TableCell>
  </TableRow>)}</TableBody></Table>;
}

function LedgerTable({ rows }: { rows: CreditLedgerEntry[] }) {
  const { t } = useTranslation();
  if (!rows.length) return <p className="py-8 text-center text-sm text-muted-foreground">{t("billing.empty")}</p>;
  return <Table><TableHeader><TableRow>
    <TableHead>{t("billing.user")}</TableHead><TableHead>{t("billing.change")}</TableHead><TableHead>{t("billing.balance")}</TableHead>
    <TableHead>{t("billing.kind")}</TableHead><TableHead>{t("billing.description")}</TableHead><TableHead>{t("billing.platformLabel")}</TableHead><TableHead>{t("billing.time")}</TableHead>
  </TableRow></TableHeader><TableBody>{rows.map((row) => <TableRow key={row.id}>
    <TableCell><div className="font-medium">{row.user_email}</div><div className="font-mono text-xs text-muted-foreground">{row.user_id.slice(0, 8)}</div></TableCell>
    <TableCell className={row.amount >= 0 ? "font-medium text-emerald-600" : "font-medium text-destructive"}>{row.amount > 0 ? "+" : ""}{row.amount.toLocaleString()}</TableCell>
    <TableCell>{row.balance_after.toLocaleString()}</TableCell><TableCell><Badge variant="outline">{row.kind}</Badge></TableCell>
    <TableCell className="max-w-64 truncate font-mono text-xs">{row.description || "—"}</TableCell><TableCell>{t(`billing.platform.${row.platform}`)}</TableCell>
    <TableCell className="whitespace-nowrap text-muted-foreground">{formatDate(row.created_at)}</TableCell>
  </TableRow>)}</TableBody></Table>;
}
