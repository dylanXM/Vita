import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, ImagePlus, Pencil, Plus, RefreshCw, Save, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";

import { agentApi } from "@/api/admin";
import type {
  AgentSettings,
  AIModel,
  AIModelInput,
  AIProvider,
  AIProviderInput,
  AdminCompanion,
  AdminCompanionInput,
  CompanionPortrait,
} from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

const textareaClass =
  "min-h-20 w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring";

const emptyProvider: AIProviderInput = {
  name: "",
  kind: "openai",
  base_url: "",
  api_key: "",
  enabled: true,
};

const emptyModel: AIModelInput = {
  provider_id: "",
  model_name: "",
  display_name: "",
  capabilities: ["text"],
  enabled: true,
};

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}

export function AgentPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const configQuery = useQuery({
    queryKey: ["agent-config"],
    queryFn: ({ signal }) => agentApi.config(signal),
  });
  const companionsQuery = useQuery({
    queryKey: ["agent-companions"],
    queryFn: ({ signal }) => agentApi.companions(signal),
  });

  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ["agent-config"] });
    void queryClient.invalidateQueries({ queryKey: ["agent-companions"] });
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("agent.title")}
        description={t("agent.desc")}
        actions={
          <Button variant="outline" onClick={refresh}>
            <RefreshCw /> {t("common.refresh")}
          </Button>
        }
      />
      {configQuery.isLoading ? (
        <div className="grid gap-4 md:grid-cols-2">
          <Skeleton className="h-72" />
          <Skeleton className="h-72" />
        </div>
      ) : configQuery.isError || !configQuery.data ? (
        <Card><CardContent className="pt-5 text-sm text-destructive">{t("common.failedToLoad")}</CardContent></Card>
      ) : (
        <>
          <ProviderSection providers={configQuery.data.providers} onSaved={refresh} />
          <ModelSection providers={configQuery.data.providers} models={configQuery.data.models} onSaved={refresh} />
          <SettingsSection models={configQuery.data.models} initial={configQuery.data.settings} onSaved={refresh} />
          <PortraitSection portraits={configQuery.data.portraits} onSaved={refresh} />
        </>
      )}
      <CompanionSection
        companions={companionsQuery.data?.items ?? []}
        models={configQuery.data?.models ?? []}
        portraits={configQuery.data?.portraits ?? []}
        loading={companionsQuery.isLoading}
        onSaved={refresh}
      />
    </div>
  );
}

function ProviderSection({ providers, onSaved }: { providers: AIProvider[]; onSaved: () => void }) {
  const { t } = useTranslation();
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<AIProviderInput>(emptyProvider);
  const save = useMutation({
    mutationFn: () => editing ? agentApi.updateProvider(editing, form) : agentApi.createProvider(form),
    onSuccess: () => {
      toast.success(t("agent.saved"));
      setEditing(null);
      setForm(emptyProvider);
      onSaved();
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const remove = useMutation({
    mutationFn: agentApi.removeProvider,
    onSuccess: onSaved,
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const edit = (provider: AIProvider) => {
    setEditing(provider.id);
    setForm({ name: provider.name, kind: provider.kind, base_url: provider.base_url, api_key: "", enabled: provider.enabled });
  };
  return (
    <Card>
      <CardHeader><CardTitle>{t("agent.providers")}</CardTitle><CardDescription>{t("agent.providersDesc")}</CardDescription></CardHeader>
      <CardContent className="space-y-5">
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
          <Field label={t("agent.providerName")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
          <Field label={t("agent.providerType")}>
            <select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value as AIProviderInput["kind"] })}>
              <option value="openai">OpenAI-compatible</option><option value="anthropic">Anthropic</option>
            </select>
          </Field>
          <Field label={t("agent.baseUrl")}><Input placeholder={form.kind === "anthropic" ? "https://api.anthropic.com" : "https://api.openai.com"} value={form.base_url} onChange={(e) => setForm({ ...form, base_url: e.target.value })} /></Field>
          <Field label={t("agent.apiKey")}><Input type="password" placeholder={editing ? t("agent.keepSecret") : "sk-…"} value={form.api_key ?? ""} onChange={(e) => setForm({ ...form, api_key: e.target.value })} /></Field>
          <div className="flex items-end gap-2"><Button disabled={!form.name || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <Plus />}{editing ? t("agent.update") : t("agent.add")}</Button>{editing && <Button variant="ghost" onClick={() => { setEditing(null); setForm(emptyProvider); }}>{t("users.cancel")}</Button>}</div>
        </div>
        <div className="divide-y rounded-md border">
          {providers.map((provider) => <div key={provider.id} className="flex flex-wrap items-center gap-3 p-3 text-sm"><div className="min-w-48 flex-1"><div className="font-medium">{provider.name}</div><div className="text-xs text-muted-foreground">{provider.kind} · {provider.base_url || t("agent.defaultEndpoint")}</div></div><Badge variant={provider.api_key_configured ? "success" : "warning"}>{provider.api_key_configured ? t("agent.keyConfigured") : t("agent.keyMissing")}</Badge><Button size="sm" variant="outline" onClick={() => edit(provider)}><Pencil />{t("users.edit")}</Button><Button size="sm" variant="ghost" onClick={() => remove.mutate(provider.id)}><Trash2 /></Button></div>)}
          {providers.length === 0 && <p className="p-4 text-sm text-muted-foreground">{t("agent.noProviders")}</p>}
        </div>
      </CardContent>
    </Card>
  );
}

function ModelSection({ providers, models, onSaved }: { providers: AIProvider[]; models: AIModel[]; onSaved: () => void }) {
  const { t } = useTranslation();
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<AIModelInput>(emptyModel);
  const save = useMutation({ mutationFn: () => editing ? agentApi.updateModel(editing, form) : agentApi.createModel(form), onSuccess: () => { toast.success(t("agent.saved")); setEditing(null); setForm(emptyModel); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const remove = useMutation({ mutationFn: agentApi.removeModel, onSuccess: onSaved, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const edit = (model: AIModel) => { setEditing(model.id); setForm({ provider_id: model.provider_id, model_name: model.model_name, display_name: model.display_name, capabilities: model.capabilities, enabled: model.enabled }); };
  return (
    <Card>
      <CardHeader><CardTitle>{t("agent.models")}</CardTitle><CardDescription>{t("agent.modelsDesc")}</CardDescription></CardHeader>
      <CardContent className="space-y-5">
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <Field label={t("agent.provider")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.provider_id} onChange={(e) => setForm({ ...form, provider_id: e.target.value })}><option value="">{t("agent.selectModel")}</option>{providers.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></Field>
          <Field label={t("agent.modelId")}><Input placeholder="gpt-5-mini / claude-sonnet-4-5" value={form.model_name} onChange={(e) => setForm({ ...form, model_name: e.target.value })} /></Field>
          <Field label={t("agent.displayName")}><Input value={form.display_name} onChange={(e) => setForm({ ...form, display_name: e.target.value })} /></Field>
          <div className="flex items-end gap-2"><Button disabled={!form.provider_id || !form.model_name || !form.display_name || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <Plus />}{editing ? t("agent.update") : t("agent.add")}</Button>{editing && <Button variant="ghost" onClick={() => { setEditing(null); setForm(emptyModel); }}>{t("users.cancel")}</Button>}</div>
        </div>
		<div className="flex flex-wrap gap-5">
			{(["text", "image", "audio"] as const).map((capability) => <label key={capability} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.capabilities.includes(capability)} onChange={(e) => setForm({ ...form, capabilities: e.target.checked ? [...form.capabilities, capability] : form.capabilities.filter((item) => item !== capability) })} />{t(`agent.capability.${capability}`)}</label>)}
		</div>
        <div className="divide-y rounded-md border">{models.map((model) => <div key={model.id} className="flex items-center gap-3 p-3 text-sm"><div className="flex-1"><div className="font-medium">{model.display_name}</div><div className="text-xs text-muted-foreground">{model.provider_name} · {model.model_name}</div></div><Badge variant="muted">{model.capabilities.join(" · ")}</Badge><Button size="sm" variant="outline" onClick={() => edit(model)}><Pencil />{t("users.edit")}</Button><Button size="sm" variant="ghost" onClick={() => remove.mutate(model.id)}><Trash2 /></Button></div>)}{models.length === 0 && <p className="p-4 text-sm text-muted-foreground">{t("agent.noModels")}</p>}</div>
      </CardContent>
    </Card>
  );
}

function SettingsSection({ models, initial, onSaved }: { models: AIModel[]; initial: AgentSettings; onSaved: () => void }) {
  const { t } = useTranslation();
  const [form, setForm] = useState(initial);
  useEffect(() => setForm(initial), [initial]);
  const save = useMutation({ mutationFn: () => agentApi.saveSettings(form), onSuccess: () => { toast.success(t("agent.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
	const modelSelect = (value: string | null, capability: "text" | "image" | "audio", onChange: (value: string | null) => void) => <select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={value ?? ""} onChange={(e) => onChange(e.target.value || null)}><option value="">{t("agent.selectModel")}</option>{models.filter((m) => m.enabled && m.capabilities.includes(capability)).map((m) => <option key={m.id} value={m.id}>{m.display_name}</option>)}</select>;
  return (
    <Card>
      <CardHeader><CardTitle>{t("agent.routing")}</CardTitle><CardDescription>{t("agent.routingDesc")}</CardDescription></CardHeader>
      <CardContent className="space-y-4">
		<div className="grid gap-3 md:grid-cols-2 xl:grid-cols-6"><Field label={t("agent.chatModel")}>{modelSelect(form.chat_model_id, "text", (v) => setForm({ ...form, chat_model_id: v }))}</Field><Field label={t("agent.lifeModel")}>{modelSelect(form.life_model_id, "text", (v) => setForm({ ...form, life_model_id: v }))}</Field><Field label={t("agent.proactiveModel")}>{modelSelect(form.proactive_model_id, "text", (v) => setForm({ ...form, proactive_model_id: v }))}</Field><Field label={t("agent.imageModel")}>{modelSelect(form.image_model_id, "image", (v) => setForm({ ...form, image_model_id: v }))}</Field><Field label={t("agent.transcriptionModel")}>{modelSelect(form.transcription_model_id, "audio", (v) => setForm({ ...form, transcription_model_id: v }))}</Field><Field label={t("agent.speechModel")}>{modelSelect(form.speech_model_id, "audio", (v) => setForm({ ...form, speech_model_id: v }))}</Field></div>
		<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-7"><NumberField label={t("agent.eventMin")} value={form.daily_event_min} min={8} max={15} onChange={(v) => setForm({ ...form, daily_event_min: v })} /><NumberField label={t("agent.eventMax")} value={form.daily_event_max} min={8} max={15} onChange={(v) => setForm({ ...form, daily_event_max: v })} /><NumberField label={t("agent.proactiveLimit")} value={form.daily_proactive_limit} min={0} max={8} onChange={(v) => setForm({ ...form, daily_proactive_limit: v })} /><NumberField label={t("agent.photoLimit")} value={form.daily_life_photo_limit} min={0} max={4} onChange={(v) => setForm({ ...form, daily_life_photo_limit: v })} /><NumberField label={t("agent.quietStart")} value={form.quiet_hours_start} min={0} max={23} onChange={(v) => setForm({ ...form, quiet_hours_start: v })} /><NumberField label={t("agent.quietEnd")} value={form.quiet_hours_end} min={0} max={23} onChange={(v) => setForm({ ...form, quiet_hours_end: v })} /><NumberField label={t("agent.freeDefaultChatHours")} value={form.free_default_chat_hours} min={1} max={720} onChange={(v) => setForm({ ...form, free_default_chat_hours: v })} /></div>
        <Button onClick={() => save.mutate()} disabled={save.isPending}><Save />{t("agent.saveSettings")}</Button>
      </CardContent>
    </Card>
  );
}

function NumberField({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  return <Field label={label}><Input type="number" value={value} min={min} max={max} onChange={(e) => onChange(Number(e.target.value))} /></Field>;
}

function PortraitSection({ portraits, onSaved }: { portraits: CompanionPortrait[]; onSaved: () => void }) {
  const { t } = useTranslation();
  const [name, setName] = useState(""); const [imageUrl, setImageUrl] = useState(""); const [gender, setGender] = useState("custom"); const [tags, setTags] = useState(""); const [isDefault, setIsDefault] = useState(false);
  const save = useMutation({ mutationFn: () => agentApi.createPortrait({ name, image_url: imageUrl, gender, personality_tags: tags.split(",").map((v) => v.trim()).filter(Boolean), is_default: isDefault, enabled: true, sort_order: portraits.length }), onSuccess: () => { setName(""); setImageUrl(""); setTags(""); setIsDefault(false); toast.success(t("agent.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const toggleDefault = useMutation({ mutationFn: (portrait: CompanionPortrait) => agentApi.updatePortrait(portrait.id, { ...portrait, is_default: !portrait.is_default }), onSuccess: onSaved, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  return <Card><CardHeader><CardTitle>{t("agent.portraits")}</CardTitle><CardDescription>{t("agent.portraitsDesc")}</CardDescription></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 md:grid-cols-4"><Field label={t("agent.portraitName")}><Input value={name} onChange={(e) => setName(e.target.value)} /></Field><Field label={t("agent.imageUrl")}><Input value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} /></Field><Field label={t("agent.gender")}><Input value={gender} onChange={(e) => setGender(e.target.value)} /></Field><Field label={t("agent.tags")}><Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="warm, calm" /></Field></div><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isDefault} onChange={(e) => setIsDefault(e.target.checked)} />{t("agent.defaultCompanion")}</label><Button disabled={!name || !imageUrl || save.isPending} onClick={() => save.mutate()}><ImagePlus />{t("agent.addPortrait")}</Button><div className="flex flex-wrap gap-3">{portraits.map((portrait) => <div key={portrait.id} className="flex items-center gap-3 rounded-md border p-2">{portrait.image_url.startsWith("asset://") ? <div className="grid size-12 place-items-center rounded-full bg-muted"><Bot className="size-5" /></div> : <img className="size-12 rounded-full object-cover" src={portrait.image_url} alt="" />}<div><div className="text-sm font-medium">{portrait.name}{portrait.is_default ? <Badge className="ms-2" variant="outline">{t("agent.defaultCompanionBadge")}</Badge> : null}</div><div className="text-xs text-muted-foreground">{portrait.personality_tags.join(" · ")}</div></div><Button size="sm" variant="ghost" disabled={toggleDefault.isPending} onClick={() => toggleDefault.mutate(portrait)}>{portrait.is_default ? t("agent.removeDefaultCompanion") : t("agent.makeDefaultCompanion")}</Button></div>)}</div></CardContent></Card>;
}

function CompanionSection({ companions, models, portraits, loading, onSaved }: { companions: AdminCompanion[]; models: AIModel[]; portraits: CompanionPortrait[]; loading: boolean; onSaved: () => void }) {
  const { t } = useTranslation();
  const [selectedId, setSelectedId] = useState("");
  const selected = useMemo(() => companions.find((item) => item.id === selectedId) ?? companions[0], [companions, selectedId]);
  const [form, setForm] = useState<AdminCompanion | null>(selected ?? null);
  useEffect(() => setForm(selected ?? null), [selected]);
  const save = useMutation({ mutationFn: () => {
    if (!form) throw new Error("No companion selected");
    const body: AdminCompanionInput = { ...form };
    return agentApi.updateCompanion(form.id, body);
  }, onSuccess: () => { toast.success(t("agent.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  if (loading) return <Skeleton className="h-72" />;
  return <Card><CardHeader><CardTitle>{t("agent.companions")}</CardTitle><CardDescription>{t("agent.companionsDesc")}</CardDescription></CardHeader><CardContent className="space-y-4">{companions.length === 0 || !form ? <p className="text-sm text-muted-foreground">{t("agent.noCompanions")}</p> : <><Field label={t("agent.companion")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.id} onChange={(e) => setSelectedId(e.target.value)}>{companions.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.user_email}</option>)}</select></Field><div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3"><Field label={t("agent.name")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field><Field label={t("agent.city")}><Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></Field><Field label={t("agent.occupation")}><Input value={form.occupation} onChange={(e) => setForm({ ...form, occupation: e.target.value })} /></Field><Field label={t("agent.model")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.model_id ?? ""} onChange={(e) => setForm({ ...form, model_id: e.target.value || null })}><option value="">{t("agent.useDefault")}</option>{models.map((model) => <option key={model.id} value={model.id}>{model.display_name}</option>)}</select></Field><Field label={t("agent.portrait")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.portrait_id ?? ""} onChange={(e) => setForm({ ...form, portrait_id: e.target.value || null })}><option value="">{t("agent.noPortrait")}</option>{portraits.map((portrait) => <option key={portrait.id} value={portrait.id}>{portrait.name}</option>)}</select></Field><Field label={t("agent.tags")}><Input value={form.personality_tags.join(", ")} onChange={(e) => setForm({ ...form, personality_tags: e.target.value.split(",").map((v) => v.trim()).filter(Boolean) })} /></Field></div><div className="grid gap-3 md:grid-cols-2"><Field label={t("agent.persona")}><textarea className={textareaClass} value={form.persona} onChange={(e) => setForm({ ...form, persona: e.target.value })} /></Field><Field label={t("agent.backstory")}><textarea className={textareaClass} value={form.backstory} onChange={(e) => setForm({ ...form, backstory: e.target.value })} /></Field><Field label={t("agent.speakingStyle")}><textarea className={textareaClass} value={form.speaking_style} onChange={(e) => setForm({ ...form, speaking_style: e.target.value })} /></Field><Field label={t("agent.habitsGoal")}><textarea className={textareaClass} value={`${form.life_habits}\n${form.life_goal}`} onChange={(e) => { const [life_habits, ...rest] = e.target.value.split("\n"); setForm({ ...form, life_habits, life_goal: rest.join("\n") }); }} /></Field></div><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.proactive_enabled} onChange={(e) => setForm({ ...form, proactive_enabled: e.target.checked })} />{t("agent.proactiveEnabled")}</label><Button disabled={save.isPending} onClick={() => save.mutate()}><Bot />{t("agent.saveCompanion")}</Button></>}</CardContent></Card>;
}
