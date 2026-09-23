import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plug, Pencil, Plus, RefreshCw, Settings2, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";

import { agentApi, envApi } from "@/api/admin";
import { ENVIRONMENTS, type Environment, type AIProvider, type AIModel, type AIModelScenario, type AIModelTestResult, type BillingProduct } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/sonner";

const ALL_SCENARIOS: AIModelScenario[] = [
  "text_chat",
  "text_life_plan",
  "text_proactive",
  "text_character_profile",
  "text_story_chapter",
  "text_storyboard",
  "image_life_photo",
  "image_requested_photo",
  "image_storyboard_sheet",
  "audio_transcription",
  "audio_speech",
  "video_life_clip",
  "video_realtime_avatar",
];

interface ServiceRow {
  model: AIModel;
  provider: AIProvider;
}

interface FormState {
  name: string;
  kind: AIProvider["kind"];
  base_url: string;
  api_key: string;
  remote_id: string;
  display_name: string;
  enabled: boolean;
}

const emptyForm: FormState = {
  name: "",
  kind: "openai",
  base_url: "",
  api_key: "",
  remote_id: "",
  display_name: "",
  enabled: true,
};

interface EditorState {
  mode: "create" | "edit";
  row: ServiceRow | null;
}

export function ModelServicesPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const activeEnv = environment ?? serverEnv.data?.environment;

  useEffect(() => {
    if (!environment && serverEnv.data?.environment) setEnvironment(serverEnv.data.environment);
  }, [environment, serverEnv.data]);

  const config = useQuery({
    queryKey: ["agent-config", activeEnv],
    queryFn: ({ signal }) => agentApi.config(activeEnv ?? undefined, signal),
    enabled: Boolean(activeEnv),
  });

  const [editor, setEditor] = useState<EditorState | null>(null);
  const [form, setForm] = useState<FormState>(emptyForm);
  const [scenariosTarget, setScenariosTarget] = useState<ServiceRow | null>(null);

  const rows: ServiceRow[] = (config.data?.models ?? [])
    .map((model) => ({ model, provider: (config.data?.providers ?? []).find((p) => p.id === model.provider_id) }))
    .filter((row): row is ServiceRow => Boolean(row.provider));

  const refresh = () => void queryClient.invalidateQueries({ queryKey: ["agent-config"] });
  const openCreate = () => {
    setForm(emptyForm);
    setEditor({ mode: "create", row: null });
  };
  const openEdit = (row: ServiceRow) => {
    setForm({
      name: row.provider.name,
      kind: row.provider.kind,
      base_url: row.provider.base_url,
      api_key: "",
      remote_id: row.model.model_name,
      display_name: row.model.display_name,
      enabled: row.model.enabled,
    });
    setEditor({ mode: "edit", row });
  };

  const save = useMutation({
    mutationFn: async () => {
      if (editor?.mode === "edit" && editor.row) {
        const { provider, model } = editor.row;
        await agentApi.updateProvider(provider.id, {
          name: form.name.trim(),
          kind: form.kind,
          base_url: form.base_url.trim(),
          ...(form.api_key ? { api_key: form.api_key } : {}),
          enabled: form.enabled,
        });
        await agentApi.updateModel(model.id, {
          provider_id: model.provider_id,
          model_name: model.model_name,
          display_name: form.display_name.trim(),
          capabilities: model.capabilities,
          subscription_plan_ids: model.subscription_plan_ids ?? [],
          enabled: form.enabled,
        });
        return;
      }
      const provider = await agentApi.createProvider({
        name: form.name.trim(),
        kind: form.kind,
        base_url: form.base_url.trim(),
        api_key: form.api_key,
        enabled: form.enabled,
      });
      await agentApi.createModel({
        provider_id: provider.id,
        model_name: form.remote_id.trim(),
        display_name: form.display_name.trim(),
        scenarios: [],
        subscription_plan_ids: [],
        enabled: form.enabled,
      });
    },
    onSuccess: () => {
      toast.success(t("modelServices.saved"));
      setEditor(null);
      setForm(emptyForm);
      refresh();
    },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });

  const toggle = useMutation({
    mutationFn: async (row: ServiceRow) => {
      const enabled = !row.model.enabled;
      await agentApi.updateProvider(row.provider.id, {
        name: row.provider.name,
        kind: row.provider.kind,
        base_url: row.provider.base_url,
        enabled,
      });
      await agentApi.updateModel(row.model.id, {
        provider_id: row.model.provider_id,
        model_name: row.model.model_name,
        display_name: row.model.display_name,
        capabilities: row.model.capabilities,
        subscription_plan_ids: row.model.subscription_plan_ids ?? [],
        enabled,
      });
    },
    onSuccess: refresh,
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });

  const remove = useMutation({
    mutationFn: async (row: ServiceRow) => {
      if (!window.confirm(t("modelServices.deleteConfirm", { name: row.model.display_name }))) {
        throw new Error("cancelled");
      }
      await agentApi.removeModel(row.model.id);
      await agentApi.removeProvider(row.provider.id);
    },
    onSuccess: () => {
      toast.success(t("modelServices.deleted"));
      refresh();
    },
    onError: (e) => {
      if (e instanceof Error && e.message === "cancelled") return;
      toast.error(errorMessage(e, t("common.failedToLoad")));
    },
  });

  const plans = config.data?.subscription_plans ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("modelServices.title")}
        description={t("modelServices.desc")}
        actions={
          <>
            <Button variant="outline" onClick={() => void config.refetch()} disabled={config.isFetching}>
              <RefreshCw className={config.isFetching ? "animate-spin" : undefined} />
              {t("common.refresh")}
            </Button>
            <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                {ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}
              </SelectContent>
            </Select>
            <Button onClick={openCreate}>
              <Plus /> {t("modelServices.create")}
            </Button>
          </>
        }
      />
      <Card>
        <CardContent className="p-0">
          {config.isLoading ? (
            <div className="space-y-3 p-4">{Array.from({ length: 5 }, (_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
          ) : config.isError ? (
            <p className="p-10 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
          ) : rows.length === 0 ? (
            <p className="p-10 text-center text-sm text-muted-foreground">{t("modelServices.empty")}</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("modelServices.name")}</TableHead>
                  <TableHead>{t("modelServices.kind")}</TableHead>
                  <TableHead>{t("modelServices.baseUrl")}</TableHead>
                  <TableHead>{t("modelServices.apiKey")}</TableHead>
                  <TableHead>{t("modelServices.remoteId")}</TableHead>
                  <TableHead>{t("modelServices.displayName")}</TableHead>
                  <TableHead>{t("modelServices.enabled")}</TableHead>
                  <TableHead className="text-end">{t("users.actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <TableRow key={row.model.id}>
                    <TableCell className="font-medium">{row.provider.name}</TableCell>
                    <TableCell><Badge variant="muted">{row.provider.kind}</Badge></TableCell>
                    <TableCell className="max-w-56 truncate text-muted-foreground" title={row.provider.base_url || undefined}>
                      {row.provider.base_url || t("modelServices.defaultEndpoint")}
                    </TableCell>
                    <TableCell>
                      <Badge variant={row.provider.api_key_configured ? "success" : "warning"}>
                        {row.provider.api_key_configured ? t("modelServices.keyConfigured") : t("modelServices.keyMissing")}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-xs">{row.model.model_name}</TableCell>
                    <TableCell>{row.model.display_name}</TableCell>
                    <TableCell>
                      <Switch
                        checked={row.model.enabled}
                        onCheckedChange={() => toggle.mutate(row)}
                        aria-label={t("modelServices.enabled")}
                      />
                    </TableCell>
                    <TableCell className="text-end">
                      <div className="flex justify-end gap-1">
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={!row.model.enabled}
                          title={row.model.enabled ? t("modelServices.configureScenarios") : t("modelServices.enableToConfigure")}
                          onClick={() => setScenariosTarget(row)}
                        >
                          <Settings2 /> {t("modelServices.configureScenarios")}
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => openEdit(row)}>
                          <Pencil /> {t("users.edit")}
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => remove.mutate(row)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <EditorDialog
        editor={editor}
        form={form}
        setForm={setForm}
        onClose={() => setEditor(null)}
        onSave={() => save.mutate()}
        saving={save.isPending}
      />

      <ScenariosDialog
        row={scenariosTarget}
        plans={plans}
        onClose={() => setScenariosTarget(null)}
        onSaved={() => {
          setScenariosTarget(null);
          refresh();
        }}
      />
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}

function EditorDialog({
  editor,
  form,
  setForm,
  onClose,
  onSave,
  saving,
}: {
  editor: EditorState | null;
  form: FormState;
  setForm: (form: FormState) => void;
  onClose: () => void;
  onSave: () => void;
  saving: boolean;
}) {
  const { t } = useTranslation();
  const open = editor !== null;
  const isEdit = editor?.mode === "edit";
  const [conn, setConn] = useState<{ success: boolean; message: string; models?: string[]; raw?: string } | null>(null);
  const test = useMutation({
    mutationFn: () =>
      agentApi.testProviderConnection({
        kind: form.kind,
        base_url: form.base_url.trim(),
        api_key: form.api_key || undefined,
        provider_id: editor?.row?.provider.id,
      }),
    onSuccess: (res) => {
      setConn(res);
      if (res.success) toast.success(t("modelServices.connectionOk"));
      else toast.error(res.message || t("modelServices.connectionFailed"));
    },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });
  const canSave = Boolean(
    form.name.trim() && form.kind && form.remote_id.trim() && form.display_name.trim() && (isEdit || form.api_key),
  );
  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) { onClose(); setConn(null); } }}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle>{isEdit ? t("modelServices.edit") : t("modelServices.create")}</DialogTitle>
          <DialogDescription>{t("modelServices.editorDesc")}</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t("modelServices.name")}>
            <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field label={t("modelServices.kind")}>
            <Select value={form.kind} onValueChange={(v) => setForm({ ...form, kind: v as AIProvider["kind"] })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="openai">OpenAI-compatible</SelectItem>
                <SelectItem value="anthropic">Anthropic</SelectItem>
              </SelectContent>
            </Select>
          </Field>
          <Field label={t("modelServices.baseUrl")}>
            <Input
              placeholder={form.kind === "anthropic" ? "https://api.anthropic.com" : "https://api.openai.com"}
              value={form.base_url}
              onChange={(e) => setForm({ ...form, base_url: e.target.value })}
            />
          </Field>
          <Field label={t("modelServices.apiKey")}>
            <Input
              type="password"
              placeholder={isEdit ? t("modelServices.keepSecret") : "sk-…"}
              value={form.api_key}
              onChange={(e) => setForm({ ...form, api_key: e.target.value })}
            />
          </Field>
          <Field label={t("modelServices.remoteId")}>
            <Input
              disabled={isEdit}
              placeholder="gpt-5-mini / claude-sonnet-4-5"
              value={form.remote_id}
              onChange={(e) => setForm({ ...form, remote_id: e.target.value })}
            />
          </Field>
          <Field label={t("modelServices.displayName")}>
            <Input value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} />
          </Field>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <Switch checked={form.enabled} onCheckedChange={(v) => setForm({ ...form, enabled: v })} />
          {t("modelServices.enabled")}
        </label>
        {conn && (
          <div className="space-y-2 text-sm">
            <div className="flex items-center gap-2">
              <Badge variant={conn.success ? "success" : "warning"}>
                {conn.success ? t("modelServices.connectionOk") : t("modelServices.connectionFailed")}
              </Badge>
              {conn.message && <span className="text-xs text-muted-foreground">{conn.message}</span>}
            </div>
            {conn.success && conn.models && conn.models.length > 0 && (
              <div>
                <div className="text-xs text-muted-foreground">{t("modelServices.availableModels")}（{conn.models.length}）</div>
                <pre className="mt-1 max-h-32 overflow-auto rounded bg-muted p-2 font-mono text-xs whitespace-pre-wrap break-words">{conn.models.join(", ")}</pre>
              </div>
            )}
            {conn.raw && (
              <div>
                <div className="text-xs text-muted-foreground">{t("modelServices.rawResponse")}</div>
                <pre className="mt-1 max-h-48 overflow-auto rounded bg-muted p-2 font-mono text-xs whitespace-pre-wrap break-words">{conn.raw}</pre>
              </div>
            )}
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => test.mutate()} disabled={test.isPending}>
            {test.isPending ? <RefreshCw className="animate-spin" /> : <Plug />}
            {test.isPending ? t("modelServices.testing") : t("modelServices.testConnection")}
          </Button>
          <Button variant="ghost" onClick={onClose}>{t("users.cancel")}</Button>
          <Button onClick={onSave} disabled={!canSave || saving}>
            {saving ? <RefreshCw className="animate-spin" /> : <Plus />}
            {t("users.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ScenarioResults({ results }: { results: AIModelTestResult[] }) {
  const { t } = useTranslation();
  return (
    <div className="space-y-2">
      <div className="font-medium">{t("modelServices.testResults")}</div>
      {results.map((r) => (
        <div key={r.scenario} className="rounded-md border p-3 text-sm">
          <div className="flex items-center gap-2">
            <Badge variant={r.success ? "success" : "warning"}>{r.success ? t("modelServices.ok") : t("modelServices.failed")}</Badge>
            <span className="font-medium">{t(`mediaModels.route.${r.scenario}`)}</span>
          </div>
          {r.method && r.url && (
            <div className="mt-2">
              <div className="text-xs text-muted-foreground">{t("modelServices.testEndpoint")}</div>
              <pre className="mt-0.5 overflow-auto rounded bg-muted p-2 font-mono text-xs whitespace-pre-wrap break-all">{r.method} {r.url}</pre>
            </div>
          )}
          {r.error && <p className="mt-2 whitespace-pre-wrap break-all text-xs text-destructive">{r.error}</p>}
          {r.request && (
            <div className="mt-2">
              <div className="text-xs text-muted-foreground">{t("modelServices.testRequest")}</div>
              <pre className="mt-0.5 max-h-64 overflow-auto rounded bg-muted p-2 font-mono text-xs whitespace-pre-wrap break-words">{r.request}</pre>
            </div>
          )}
          {r.response && (
            <div className="mt-2">
              <div className="text-xs text-muted-foreground">{t("modelServices.testResponse")}</div>
              <pre className="mt-0.5 max-h-64 overflow-auto rounded bg-muted p-2 font-mono text-xs whitespace-pre-wrap break-words">{r.response}</pre>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function ScenariosDialog({
  row,
  plans,
  onClose,
  onSaved,
}: {
  row: ServiceRow | null;
  plans: BillingProduct[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation();
  const [scenarios, setScenarios] = useState<AIModelScenario[]>([]);
  const [planIds, setPlanIds] = useState<string[]>([]);
  const [results, setResults] = useState<AIModelTestResult[] | null>(null);

  const [lastId, setLastId] = useState<string | null>(null);
  if (row && row.model.id !== lastId) {
    setLastId(row.model.id);
    setScenarios(row.model.configured_scenarios ?? []);
    setPlanIds(row.model.subscription_plan_ids ?? []);
    setResults(null);
  }

  const save = useMutation({
    mutationFn: () => {
      if (!row) throw new Error("no row");
      return agentApi.updateModel(row.model.id, {
        provider_id: row.model.provider_id,
        model_name: row.model.model_name,
        display_name: row.model.display_name,
        capabilities: row.model.capabilities,
        scenarios,
        subscription_plan_ids: planIds,
        enabled: row.model.enabled,
      });
    },
    onSuccess: () => {
      toast.success(t("modelServices.saved"));
      onSaved();
    },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });

  const test = useMutation({
    mutationFn: () => {
      if (!row) throw new Error("no row");
      if (scenarios.length === 0) throw new Error(t("modelServices.noScenariosToTest"));
      return agentApi.testModel({
        provider_id: row.provider.id,
        model_name: row.model.model_name,
        scenarios,
      });
    },
    onSuccess: (res) => setResults(res.results),
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });

  const toggleScenario = (scenario: AIModelScenario) =>
    setScenarios((prev) => (prev.includes(scenario) ? prev.filter((s) => s !== scenario) : [...prev, scenario]));
  const togglePlan = (id: string) =>
    setPlanIds((prev) => (prev.includes(id) ? prev.filter((p) => p !== id) : [...prev, id]));

  return (
    <Dialog open={row !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle>{t("modelServices.configureScenarios")}</DialogTitle>
          <DialogDescription>{row?.model.display_name}</DialogDescription>
        </DialogHeader>
        <div className="rounded-md border p-4">
          <div className="font-medium">{t("modelServices.scenarios")}</div>
          <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {ALL_SCENARIOS.map((scenario) => (
              <label key={scenario} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={scenarios.includes(scenario)} onChange={() => toggleScenario(scenario)} />
                {t(`mediaModels.route.${scenario}`)}
              </label>
            ))}
          </div>
        </div>
        <div className="rounded-md border p-4">
          <div className="font-medium">{t("modelServices.subscriptionPlans")}</div>
          <p className="mt-1 text-xs text-muted-foreground">{t("modelServices.subscriptionPlansDesc")}</p>
          <div className="mt-3 max-h-52 gap-2 overflow-y-auto">
            {plans.map((plan) => (
              <label key={plan.id} className="flex items-start gap-2 py-1 text-sm">
                <input className="mt-0.5" type="checkbox" checked={planIds.includes(plan.id)} onChange={() => togglePlan(plan.id)} />
                <span>
                  {plan.name}
                  <span className="block text-xs text-muted-foreground">
                    {t(`billing.env.${plan.environment}`)} · {t(`billing.platform.${plan.platform}`)} · {plan.product_id}
                  </span>
                </span>
              </label>
            ))}
            {plans.length === 0 && <p className="text-sm text-muted-foreground">{t("modelServices.noPlans")}</p>}
          </div>
        </div>
        {results && <ScenarioResults results={results} />}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => test.mutate()} disabled={test.isPending}>
            {test.isPending ? <RefreshCw className="animate-spin" /> : <Plug />}
            {test.isPending ? t("modelServices.testing") : t("modelServices.testConnection")}
          </Button>
          <Button variant="ghost" onClick={onClose}>{t("users.cancel")}</Button>
          <Button onClick={() => save.mutate()} disabled={save.isPending}>
            {save.isPending ? <RefreshCw className="animate-spin" /> : <Plug />}
            {t("users.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
