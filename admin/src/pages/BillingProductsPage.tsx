import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, Plus, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/sonner";
import { coinPacksApi, envApi, subscriptionPlansApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import { ENVIRONMENTS, type BillingPlatform, type BillingProduct, type Environment } from "@/api/types";

const PLATFORMS: BillingPlatform[] = ["ios", "android", "web"];

function emptyProduct(environment: Environment, plan: boolean): BillingProduct {
  return {
    id: "", key: "", name: "", environment, platform: "ios", coins: 0,
    price_usd: 0, period: plan ? "month" : undefined, product_id: "", popular: false,
    enabled: true, sort_order: 0,
  };
}

export function SubscriptionPlansPage() {
  return <BillingProductsPage plan />;
}

export function CoinPacksPage() {
  return <BillingProductsPage plan={false} />;
}

function BillingProductsPage({ plan }: { plan: boolean }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const [platform, setPlatform] = useState<BillingPlatform | "all">("all");
  const [editing, setEditing] = useState<BillingProduct | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const activeEnv = environment ?? serverEnv.data?.environment;

  useEffect(() => {
    if (!environment && serverEnv.data?.environment) setEnvironment(serverEnv.data.environment);
  }, [environment, serverEnv.data]);

  const api = plan ? subscriptionPlansApi : coinPacksApi;
  const list = useQuery({
    queryKey: [plan ? "subscription-plans" : "coin-packs", activeEnv, platform],
    queryFn: ({ signal }) => api.list({ environment: activeEnv!, platform: platform === "all" ? undefined : platform }, signal),
    enabled: Boolean(activeEnv),
  });

  const remove = useMutation({
    mutationFn: (id: string) => api.remove(id),
    onSuccess: () => {
      toast.success(t("billing.deleted"));
      void queryClient.invalidateQueries({ queryKey: [plan ? "subscription-plans" : "coin-packs"] });
    },
    onError: (err) => toast.error(errorMessage(err, t("common.failedToLoad"))),
  });

  const titleKey = plan ? "billing.plansTitle" : "billing.packsTitle";
  const descKey = plan ? "billing.plansDesc" : "billing.packsDesc";
  return (
    <div className="space-y-6">
      <PageHeader title={t(titleKey)} description={t(descKey)} actions={
        <Button size="sm" disabled={!activeEnv} onClick={() => { setEditing(null); setDialogOpen(true); }}>
          <Plus />{t(plan ? "billing.addPlan" : "billing.addPack")}
        </Button>
      } />
      <Card><CardContent className="space-y-4 p-4">
        <div className="flex flex-wrap gap-3">
          <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}>
            <SelectTrigger className="w-44"><SelectValue placeholder={t("billing.environment")} /></SelectTrigger>
            <SelectContent>{ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}</SelectContent>
          </Select>
          <Select value={platform} onValueChange={(v) => setPlatform(v as BillingPlatform | "all")}>
            <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{t("billing.allPlatforms")}</SelectItem>
              {PLATFORMS.map((value) => <SelectItem key={value} value={value}>{t(`billing.platform.${value}`)}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        {list.isLoading || !activeEnv ? <div className="space-y-3">{[1,2,3].map((n) => <Skeleton key={n} className="h-10" />)}</div>
          : list.isError ? <p className="py-8 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
          : !list.data?.items.length ? <p className="py-8 text-center text-sm text-muted-foreground">{t("billing.empty")}</p>
          : <Table><TableHeader><TableRow>
              <TableHead>{t("billing.name")}</TableHead><TableHead>{t("billing.key")}</TableHead>
              <TableHead>{t("billing.platformLabel")}</TableHead><TableHead>{t("billing.coins")}</TableHead>
              <TableHead>{t("billing.price")}</TableHead>{plan && <TableHead>{t("billing.period")}</TableHead>}
              <TableHead>{t("billing.productId")}</TableHead><TableHead>{t("billing.status")}</TableHead>
              <TableHead className="text-end">{t("billing.actions")}</TableHead>
            </TableRow></TableHeader><TableBody>{list.data.items.map((item) => <TableRow key={item.id}>
              <TableCell className="font-medium">{item.name}</TableCell><TableCell className="font-mono text-xs">{item.key}</TableCell>
              <TableCell><Badge variant="outline">{t(`billing.platform.${item.platform}`)}</Badge></TableCell>
              <TableCell>{item.coins.toLocaleString()}</TableCell><TableCell>${Number(item.price_usd).toFixed(2)}</TableCell>
              {plan && <TableCell>{t(`billing.periods.${item.period}`)}</TableCell>}
              <TableCell className="max-w-48 truncate font-mono text-xs">{item.product_id || "—"}</TableCell>
              <TableCell><Badge variant={item.enabled ? "success" : "muted"}>{t(item.enabled ? "billing.enabled" : "billing.disabled")}</Badge></TableCell>
              <TableCell className="text-end"><div className="inline-flex gap-1">
                <Button variant="ghost" size="icon" onClick={() => { setEditing(item); setDialogOpen(true); }} aria-label={t("billing.edit")}><Pencil /></Button>
                <Button variant="ghost" size="icon" onClick={() => { if (window.confirm(t("billing.deleteConfirm", { name: item.name }))) remove.mutate(item.id); }} aria-label={t("billing.delete")}><Trash2 /></Button>
              </div></TableCell>
            </TableRow>)}</TableBody></Table>}
      </CardContent></Card>
      {activeEnv && <ProductDialog open={dialogOpen} onOpenChange={setDialogOpen} product={editing} environment={activeEnv} plan={plan}
        onSaved={() => void queryClient.invalidateQueries({ queryKey: [plan ? "subscription-plans" : "coin-packs"] })} />}
    </div>
  );
}

function ProductDialog({ open, onOpenChange, product, environment, plan, onSaved }: {
  open: boolean; onOpenChange: (value: boolean) => void; product: BillingProduct | null;
  environment: Environment; plan: boolean; onSaved: () => void;
}) {
  const { t } = useTranslation();
  const [form, setForm] = useState<BillingProduct>(() => emptyProduct(environment, plan));
  useEffect(() => { if (open) setForm(product ? { ...product } : emptyProduct(environment, plan)); }, [open, product, environment, plan]);
  const api = plan ? subscriptionPlansApi : coinPacksApi;
  const save = useMutation({
    mutationFn: () => {
      const { id: _id, ...body } = form;
      return product ? api.update(product.id, body) : api.create(body);
    },
    onSuccess: () => { toast.success(t("billing.saved")); onOpenChange(false); onSaved(); },
    onError: (err) => toast.error(errorMessage(err, t("common.failedToLoad"))),
  });
  const set = <K extends keyof BillingProduct>(key: K, value: BillingProduct[K]) => setForm((old) => ({ ...old, [key]: value }));
  const valid = form.key.trim() && form.name.trim() && form.coins >= (plan ? 0 : 1) && form.price_usd >= 0;
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent className="max-h-[90vh] overflow-y-auto">
    <DialogHeader><DialogTitle>{t(product ? "billing.edit" : plan ? "billing.addPlan" : "billing.addPack")}</DialogTitle>
      <DialogDescription>{t("billing.formDesc")}</DialogDescription></DialogHeader>
    <div className="grid gap-4 sm:grid-cols-2">
      <Field label={t("billing.name")}><Input value={form.name} onChange={(e) => set("name", e.target.value)} /></Field>
      <Field label={t("billing.key")}><Input value={form.key} onChange={(e) => set("key", e.target.value)} /></Field>
      <Field label={t("billing.environment")}><Select value={form.environment} onValueChange={(v) => set("environment", v as Environment)}><SelectTrigger className="w-full"><SelectValue /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((v) => <SelectItem key={v} value={v}>{t(`billing.env.${v}`)}</SelectItem>)}</SelectContent></Select></Field>
      <Field label={t("billing.platformLabel")}><Select value={form.platform} onValueChange={(v) => set("platform", v as BillingPlatform)}><SelectTrigger className="w-full"><SelectValue /></SelectTrigger><SelectContent>{PLATFORMS.map((v) => <SelectItem key={v} value={v}>{t(`billing.platform.${v}`)}</SelectItem>)}</SelectContent></Select></Field>
      <Field label={t("billing.coins")}><Input type="number" min={plan ? 0 : 1} value={form.coins} onChange={(e) => set("coins", Number(e.target.value))} /></Field>
      <Field label={t("billing.price")}><Input type="number" min="0" step="0.01" value={form.price_usd} onChange={(e) => set("price_usd", Number(e.target.value))} /></Field>
      {plan && <Field label={t("billing.period")}><Select value={form.period} onValueChange={(v) => set("period", v as BillingProduct["period"])}><SelectTrigger className="w-full"><SelectValue /></SelectTrigger><SelectContent>{["week","month","year"].map((v) => <SelectItem key={v} value={v}>{t(`billing.periods.${v}`)}</SelectItem>)}</SelectContent></Select></Field>}
      <Field label={t("billing.sortOrder")}><Input type="number" min="0" value={form.sort_order} onChange={(e) => set("sort_order", Number(e.target.value))} /></Field>
      <Field label={t("billing.productId")} wide><Input value={form.product_id} onChange={(e) => set("product_id", e.target.value)} placeholder={form.platform === "web" ? "price_..." : "com.vita..."} /></Field>
      {!plan && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={Boolean(form.popular)} onChange={(e) => set("popular", e.target.checked)} />{t("billing.popular")}</label>}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.enabled} onChange={(e) => set("enabled", e.target.checked)} />{t("billing.enabled")}</label>
    </div>
    <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>{t("billing.cancel")}</Button><Button disabled={!valid || save.isPending} onClick={() => save.mutate()}>{save.isPending ? t("common.loading") : t("billing.save")}</Button></DialogFooter>
  </DialogContent></Dialog>;
}

function Field({ label, wide, children }: { label: string; wide?: boolean; children: React.ReactNode }) {
  return <div className={`space-y-1.5 ${wide ? "sm:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}
