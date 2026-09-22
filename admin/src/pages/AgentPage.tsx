import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, ImagePlus, RefreshCw, Save } from "lucide-react";
import { useTranslation } from "react-i18next";

import { agentApi, envApi } from "@/api/admin";
import { ENVIRONMENTS, type Environment } from "@/api/types";
import type {
  AgentSettings,
  AIModel,
  AdminCompanion,
  AdminCompanionInput,
  CompanionPortrait,
} from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";

const textareaClass =
  "min-h-20 w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring";

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
  const serverEnv = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null);
  const activeEnv = environment ?? serverEnv.data?.environment;

  useEffect(() => {
    if (!environment && serverEnv.data?.environment) setEnvironment(serverEnv.data.environment);
  }, [environment, serverEnv.data]);

  const configQuery = useQuery({
    queryKey: ["agent-config", activeEnv],
    queryFn: ({ signal }) => agentApi.config(activeEnv ?? undefined, signal),
    enabled: Boolean(activeEnv),
  });
  const companionsQuery = useQuery({
    queryKey: ["agent-companions", activeEnv],
    queryFn: ({ signal }) => agentApi.companions(activeEnv ?? undefined, signal),
    enabled: Boolean(activeEnv),
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
          <>
            <Button variant="outline" onClick={refresh}>
              <RefreshCw /> {t("common.refresh")}
            </Button>
            <Select value={activeEnv ?? ""} onValueChange={(v) => setEnvironment(v as Environment)}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                {ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}
              </SelectContent>
            </Select>
          </>
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
          <SettingsSection initial={configQuery.data.settings} onSaved={refresh} />
          <PortraitSection portraits={configQuery.data.portraits} onSaved={refresh} />
        </>
      )}
      <CompanionSection
        companions={companionsQuery.data?.items ?? []}
        models={(configQuery.data?.models ?? []).filter((model) => model.enabled && model.capabilities.includes("text"))}
        portraits={configQuery.data?.portraits ?? []}
        loading={companionsQuery.isLoading}
        onSaved={refresh}
      />
    </div>
  );
}

function SettingsSection({ initial, onSaved }: { initial: AgentSettings; onSaved: () => void }) {
  const { t } = useTranslation();
  const [form, setForm] = useState(initial);
  useEffect(() => setForm(initial), [initial]);
  const save = useMutation({ mutationFn: () => agentApi.saveSettings(form), onSuccess: () => { toast.success(t("agent.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  return (
    <Card>
      <CardHeader><CardTitle>{t("agent.routing")}</CardTitle><CardDescription>{t("agent.routingDesc")}</CardDescription></CardHeader>
      <CardContent className="space-y-4">
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
  const chatModels = models.filter((model) => (model.configured_scenarios ?? []).includes("text_chat"));
  if (loading) return <Skeleton className="h-72" />;
  return <Card><CardHeader><CardTitle>{t("agent.companions")}</CardTitle><CardDescription>{t("agent.companionsDesc")}</CardDescription></CardHeader><CardContent className="space-y-4">{companions.length === 0 || !form ? <p className="text-sm text-muted-foreground">{t("agent.noCompanions")}</p> : <><Field label={t("agent.companion")}>
          <Select value={form.id} onValueChange={setSelectedId}>
            <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>
              {companions.map((item) => <SelectItem key={item.id} value={item.id}>{item.name} · {item.user_email}</SelectItem>)}
            </SelectContent>
          </Select>
        </Field><div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3"><Field label={t("agent.name")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field><Field label={t("agent.city")}><Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></Field><Field label={t("agent.occupation")}><Input value={form.occupation} onChange={(e) => setForm({ ...form, occupation: e.target.value })} /></Field><Field label={t("agent.model")}>
          <Select value={form.model_id ?? "none"} onValueChange={(v) => setForm({ ...form, model_id: v === "none" ? null : v })}>
            <SelectTrigger className="w-full"><SelectValue placeholder={t("agent.useDefault")} /></SelectTrigger>
            <SelectContent>
              <SelectItem value="none">{t("mediaModels.notSelected")}</SelectItem>
              {chatModels.map((model) => <SelectItem key={model.id} value={model.id}>{model.display_name}</SelectItem>)}
            </SelectContent>
          </Select>
        </Field><Field label={t("agent.portrait")}>
          <Select value={form.portrait_id ?? "none"} onValueChange={(v) => setForm({ ...form, portrait_id: v === "none" ? null : v })}>
            <SelectTrigger className="w-full"><SelectValue placeholder={t("agent.noPortrait")} /></SelectTrigger>
            <SelectContent>
              <SelectItem value="none">{t("mediaModels.notSelected")}</SelectItem>
              {portraits.map((portrait) => <SelectItem key={portrait.id} value={portrait.id}>{portrait.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </Field><Field label={t("agent.tags")}><Input value={form.personality_tags.join(", ")} onChange={(e) => setForm({ ...form, personality_tags: e.target.value.split(",").map((v) => v.trim()).filter(Boolean) })} /></Field></div><div className="grid gap-3 md:grid-cols-2"><Field label={t("agent.persona")}><textarea className={textareaClass} value={form.persona} onChange={(e) => setForm({ ...form, persona: e.target.value })} /></Field><Field label={t("agent.backstory")}><textarea className={textareaClass} value={form.backstory} onChange={(e) => setForm({ ...form, backstory: e.target.value })} /></Field><Field label={t("agent.speakingStyle")}><textarea className={textareaClass} value={form.speaking_style} onChange={(e) => setForm({ ...form, speaking_style: e.target.value })} /></Field><Field label={t("agent.habitsGoal")}><textarea className={textareaClass} value={`${form.life_habits}\n${form.life_goal}`} onChange={(e) => { const [life_habits, ...rest] = e.target.value.split("\n"); setForm({ ...form, life_habits, life_goal: rest.join("\n") }); }} /></Field></div><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.proactive_enabled} onChange={(e) => setForm({ ...form, proactive_enabled: e.target.checked })} />{t("agent.proactiveEnabled")}</label><Button disabled={save.isPending} onClick={() => save.mutate()}><Bot />{t("agent.saveCompanion")}</Button></>}</CardContent></Card>;
}
