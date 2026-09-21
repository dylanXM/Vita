import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { envApi, storageApi } from "@/api/admin";
import type { Environment, StorageConfig, StorageConfigInput, StorageProviderInput } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

const emptyProvider = (): StorageProviderInput => ({
  enabled: false,
  endpoint: "",
  bucket: "",
  region: "",
  access_key: "",
  secret_key: "",
});

const emptyForm = (): StorageConfigInput => ({
  active_provider: "postgres",
  r2: emptyProvider(),
  cos: emptyProvider(),
});

export function StoragePage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const activeEnv = environment ?? serverEnv.data?.environment;
  const query = useQuery({
    queryKey: ["storage-config", activeEnv],
    queryFn: ({ signal }) => storageApi.get(activeEnv!, signal),
    enabled: Boolean(activeEnv),
  });
  const [form, setForm] = useState<StorageConfigInput>(emptyForm);

  useEffect(() => {
    if (!query.data) return;
    setForm({
      active_provider: query.data.active_provider,
      r2: { ...query.data.r2, access_key: "", secret_key: "" },
      cos: { ...query.data.cos, access_key: "", secret_key: "" },
    });
  }, [query.data]);

  const save = useMutation({
    mutationFn: () => storageApi.save(activeEnv!, form),
    onSuccess: (data) => {
      queryClient.setQueryData(["storage-config", activeEnv], data);
      toast.success(t("storage.saved"));
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const test = useMutation({
    mutationFn: (provider: "r2" | "cos") => storageApi.test(activeEnv!, provider),
    onSuccess: () => toast.success(t("storage.tested")),
    onError: (error) => toast.error(errorMessage(error)),
  });

  const setProvider = (provider: "r2" | "cos", value: StorageProviderInput) => {
    setForm((current) => {
      let active = current.active_provider;
      if (value.enabled && active === "postgres") active = provider;
      if (!value.enabled && active === provider) {
        const other = provider === "r2" ? current.cos : current.r2;
        active = other.enabled ? (provider === "r2" ? "cos" : "r2") : "postgres";
      }
      return { ...current, active_provider: active, [provider]: value };
    });
  };

  return <div className="space-y-6">
    <PageHeader title={t("storage.title")} description={t("storage.desc")} actions={
      <Select value={activeEnv ?? ""} onValueChange={(value) => setEnvironment(value as Environment)}>
        <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
        <SelectContent>{ENVIRONMENTS.map((value) => <SelectItem key={value} value={value}>{value}</SelectItem>)}</SelectContent>
      </Select>
    } />
    {query.isLoading ? <Skeleton className="h-96 w-full" /> : query.isError ? <Card><CardContent className="pt-6 text-sm text-destructive">{errorMessage(query.error, t("common.failedToLoad"))}</CardContent></Card> : <>
      <Card>
        <CardHeader><CardTitle>{t("storage.activeProvider")}</CardTitle><CardDescription>{t("storage.fallbackHint")}</CardDescription></CardHeader>
        <CardContent className="space-y-3">
          <Select value={form.active_provider} onValueChange={(value) => setForm({ ...form, active_provider: value as StorageConfigInput["active_provider"] })}>
            <SelectTrigger className="max-w-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              {!form.r2.enabled && !form.cos.enabled ? <SelectItem value="postgres">{t("storage.postgresFallback")}</SelectItem> : null}
              {form.r2.enabled ? <SelectItem value="r2">Cloudflare R2</SelectItem> : null}
              {form.cos.enabled ? <SelectItem value="cos">Tencent Cloud COS</SelectItem> : null}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground">{t("storage.externalFailure")}</p>
        </CardContent>
      </Card>
      <div className="grid gap-6 xl:grid-cols-2">
        <ProviderCard provider="r2" title="Cloudflare R2" description={t("storage.r2Desc")} value={form.r2} saved={query.data} onChange={(value) => setProvider("r2", value)} onTest={() => test.mutate("r2")} testing={test.isPending} />
        <ProviderCard provider="cos" title="Tencent Cloud COS" description={t("storage.cosDesc")} value={form.cos} saved={query.data} onChange={(value) => setProvider("cos", value)} onTest={() => test.mutate("cos")} testing={test.isPending} />
      </div>
      <div className="flex justify-end"><Button disabled={!activeEnv || !query.data || save.isPending} onClick={() => save.mutate()}>{t("storage.save")}</Button></div>
    </>}
  </div>;
}

function ProviderCard({ provider, title, description, value, saved, onChange, onTest, testing }: {
  provider: "r2" | "cos";
  title: string;
  description: string;
  value: StorageProviderInput;
  saved?: StorageConfig;
  onChange: (value: StorageProviderInput) => void;
  onTest: () => void;
  testing: boolean;
}) {
  const { t } = useTranslation();
  const stored = saved?.[provider];
  const credentialsConfigured = Boolean(stored?.access_key_configured && stored?.secret_key_configured);
  const hasUnsavedChanges = !stored
    || value.enabled !== stored.enabled
    || value.endpoint !== stored.endpoint
    || value.bucket !== stored.bucket
    || value.region !== stored.region
    || value.access_key !== ""
    || value.secret_key !== "";
  const set = <K extends keyof StorageProviderInput>(key: K, next: StorageProviderInput[K]) => onChange({ ...value, [key]: next });
  return <Card>
    <CardHeader>
      <div className="flex items-center justify-between gap-3"><CardTitle>{title}</CardTitle><Badge variant={credentialsConfigured ? "default" : "outline"}>{t(credentialsConfigured ? "storage.configured" : "storage.notConfigured")}</Badge></div>
      <CardDescription>{description}</CardDescription>
    </CardHeader>
    <CardContent className="space-y-4">
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={value.enabled} onChange={(event) => set("enabled", event.target.checked)} />{t("storage.enabled")}</label>
      <Field label={t("storage.endpoint")}><Input type="url" value={value.endpoint} onChange={(event) => set("endpoint", event.target.value)} placeholder={provider === "r2" ? "https://ACCOUNT_ID.r2.cloudflarestorage.com" : "https://cos.ap-guangzhou.myqcloud.com"} /></Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t("storage.bucket")}><Input value={value.bucket} onChange={(event) => set("bucket", event.target.value)} /></Field>
        <Field label={t("storage.region")}><Input value={value.region} onChange={(event) => set("region", event.target.value)} placeholder={provider === "r2" ? "auto" : "ap-guangzhou"} /></Field>
      </div>
      <Field label={t("storage.accessKey")}><Input type="password" autoComplete="new-password" value={value.access_key} onChange={(event) => set("access_key", event.target.value)} /></Field>
      <Field label={t("storage.secretKey")}><Input type="password" autoComplete="new-password" value={value.secret_key} onChange={(event) => set("secret_key", event.target.value)} /></Field>
      <p className="text-xs text-muted-foreground">{t("storage.keepSecret")}</p>
      <Button variant="outline" disabled={!value.enabled || !credentialsConfigured || hasUnsavedChanges || testing} onClick={onTest}>{t("storage.test")}</Button>
      {value.enabled && (!credentialsConfigured || hasUnsavedChanges) ? <p className="text-xs text-muted-foreground">{t("storage.saveBeforeTest")}</p> : null}
    </CardContent>
  </Card>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-2"><Label>{label}</Label>{children}</div>;
}
