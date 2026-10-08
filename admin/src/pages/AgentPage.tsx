import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, ImagePlus, Pencil, RefreshCw, Save, Settings2 } from "lucide-react";
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
import { ConfigurationButton } from "@/components/configuration-button";
import { AdminImageInput, isAdminImageURL } from "@/components/admin-image-input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
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
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [portraitsOpen, setPortraitsOpen] = useState(false);

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
  const settings = configQuery.data?.settings;
  const settingsSummary = settings ? [
    `${t("agent.eventMin")}: ${settings.daily_event_min}`,
    `${t("agent.eventMax")}: ${settings.daily_event_max}`,
    `${t("agent.proactiveLimit")}: ${settings.daily_proactive_limit}`,
    `${t("agent.photoLimit")}: ${settings.daily_life_photo_limit}`,
    `${t("agent.quietStart")}: ${settings.quiet_hours_start}`,
    `${t("agent.quietEnd")}: ${settings.quiet_hours_end}`,
    `${t("agent.freeDefaultChatHours")}: ${settings.free_default_chat_hours}`,
  ] : [t(configQuery.isError ? "common.failedToLoad" : "common.loading")];
  const savedPortraits = configQuery.data?.portraits ?? [];
  const portraitsSummary = !configQuery.data ? [t(configQuery.isError ? "common.failedToLoad" : "common.loading")] : savedPortraits.length
    ? savedPortraits.map((portrait) => `${t("agent.portraitName")}: ${portrait.name} · ${t("agent.gender")}: ${portrait.gender} · ${t("agent.tags")}: ${portrait.personality_tags.join(", ") || "—"} · ${t("agent.imageUrl")}: ${portrait.image_url} · ${t(portrait.enabled ? "content.enabled" : "content.disabled")}${portrait.is_default ? ` · ${t("agent.defaultCompanionBadge")}` : ""}`)
    : [t("agent.noPortraits")];

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
            <Select value={activeEnv ?? ""} onValueChange={(v) => { setEnvironment(v as Environment); setSettingsOpen(false); setPortraitsOpen(false); }}>
              <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
              <SelectContent>
                {ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`billing.env.${env}`)}</SelectItem>)}
              </SelectContent>
            </Select>
            <ConfigurationButton label={t("agent.routing")} icon={<Settings2 />} onClick={() => setSettingsOpen(true)} disabled={!settings} details={settingsSummary} />
            <ConfigurationButton label={t("agent.portraits")} icon={<ImagePlus />} onClick={() => setPortraitsOpen(true)} disabled={!configQuery.data} details={portraitsSummary} />
          </>
        }
      />
      {configQuery.isError && <Card><CardContent className="p-4 text-sm text-destructive">{t("common.failedToLoad")}</CardContent></Card>}
      {companionsQuery.isError ? <Card><CardContent className="p-4 text-sm text-destructive">{t("common.failedToLoad")}</CardContent></Card> : <CompanionSection
        companions={companionsQuery.data?.items ?? []}
        models={(configQuery.data?.models ?? []).filter((model) => model.enabled && model.capabilities.includes("text"))}
        portraits={configQuery.data?.portraits ?? []}
        loading={companionsQuery.isLoading}
        onSaved={refresh}
      />}
      <Dialog open={settingsOpen} onOpenChange={setSettingsOpen}>
        <DialogContent className="max-h-[85vh] max-w-3xl overflow-y-auto">
          <DialogHeader><DialogTitle>{t("agent.routing")}</DialogTitle><DialogDescription>{t("agent.routingDesc")}</DialogDescription></DialogHeader>
          {settings && <SettingsSection key={activeEnv} initial={settings} onSaved={() => { setSettingsOpen(false); refresh(); }} />}
        </DialogContent>
      </Dialog>
      <Dialog open={portraitsOpen} onOpenChange={setPortraitsOpen}>
        <DialogContent className="max-h-[85vh] max-w-3xl overflow-y-auto">
          <DialogHeader><DialogTitle>{t("agent.portraits")}</DialogTitle><DialogDescription>{t("agent.portraitsDesc")}</DialogDescription></DialogHeader>
          {configQuery.data && <PortraitSection portraits={configQuery.data.portraits} onSaved={refresh} />}
        </DialogContent>
      </Dialog>
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
		<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3"><NumberField label={t("agent.eventMin")} value={form.daily_event_min} min={8} max={15} onChange={(v) => setForm({ ...form, daily_event_min: v })} /><NumberField label={t("agent.eventMax")} value={form.daily_event_max} min={8} max={15} onChange={(v) => setForm({ ...form, daily_event_max: v })} /><NumberField label={t("agent.proactiveLimit")} value={form.daily_proactive_limit} min={0} max={8} onChange={(v) => setForm({ ...form, daily_proactive_limit: v })} /><NumberField label={t("agent.photoLimit")} value={form.daily_life_photo_limit} min={0} max={4} onChange={(v) => setForm({ ...form, daily_life_photo_limit: v })} /><NumberField label={t("agent.quietStart")} value={form.quiet_hours_start} min={0} max={23} onChange={(v) => setForm({ ...form, quiet_hours_start: v })} /><NumberField label={t("agent.quietEnd")} value={form.quiet_hours_end} min={0} max={23} onChange={(v) => setForm({ ...form, quiet_hours_end: v })} /><NumberField label={t("agent.freeDefaultChatHours")} value={form.free_default_chat_hours} min={1} max={720} onChange={(v) => setForm({ ...form, free_default_chat_hours: v })} /></div>
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
  const [editing, setEditing] = useState<CompanionPortrait | null>(null);
  const [imageUploading, setImageUploading] = useState(false);
  const [name, setName] = useState(""); const [imageUrl, setImageUrl] = useState(""); const [gender, setGender] = useState("custom"); const [tags, setTags] = useState(""); const [isDefault, setIsDefault] = useState(false);
  const reset = () => { setEditing(null); setName(""); setImageUrl(""); setGender("custom"); setTags(""); setIsDefault(false); };
  const edit = (portrait: CompanionPortrait) => { setEditing(portrait); setName(portrait.name); setImageUrl(portrait.image_url); setGender(portrait.gender); setTags(portrait.personality_tags.join(", ")); setIsDefault(portrait.is_default); };
  const save = useMutation({ mutationFn: () => {
    const body = { name, image_url: imageUrl, gender, personality_tags: tags.split(",").map((v) => v.trim()).filter(Boolean), is_default: isDefault, enabled: editing?.enabled ?? true, sort_order: editing?.sort_order ?? portraits.length };
    return editing ? agentApi.updatePortrait(editing.id, body) : agentApi.createPortrait(body);
  }, onSuccess: () => { reset(); toast.success(t("agent.saved")); onSaved(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const toggleDefault = useMutation({ mutationFn: (portrait: CompanionPortrait) => agentApi.updatePortrait(portrait.id, { ...portrait, is_default: !portrait.is_default }), onSuccess: onSaved, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  return <Card><CardHeader><CardTitle>{t("agent.portraits")}</CardTitle><CardDescription>{t("agent.portraitsDesc")}</CardDescription></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 md:grid-cols-4"><Field label={t("agent.portraitName")}><Input value={name} onChange={(e) => setName(e.target.value)} /></Field><Field label={t("agent.imageUrl")}><AdminImageInput value={imageUrl} onChange={setImageUrl} onUploadingChange={setImageUploading} /></Field><Field label={t("agent.gender")}><Input value={gender} onChange={(e) => setGender(e.target.value)} /></Field><Field label={t("agent.tags")}><Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="warm, calm" /></Field></div><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={isDefault} onChange={(e) => setIsDefault(e.target.checked)} />{t("agent.defaultCompanion")}</label><div className="flex gap-2"><Button disabled={!name.trim() || !isAdminImageURL(imageUrl.trim()) || imageUploading || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <ImagePlus />}{editing ? t("users.save") : t("agent.addPortrait")}</Button>{editing && <Button variant="outline" onClick={reset}>{t("users.cancel")}</Button>}</div><div className="flex flex-wrap gap-3">{portraits.map((portrait) => <div key={portrait.id} className="flex items-center gap-3 rounded-md border p-2">{portrait.image_url.startsWith("asset://") ? <div className="grid size-12 place-items-center rounded-full bg-muted"><Bot className="size-5" /></div> : <img className="size-12 rounded-full object-cover" src={portrait.image_url} alt="" />}<div><div className="text-sm font-medium">{portrait.name}{portrait.is_default ? <Badge className="ms-2" variant="outline">{t("agent.defaultCompanionBadge")}</Badge> : null}</div><div className="text-xs text-muted-foreground">{portrait.personality_tags.join(" · ")}</div></div><Button size="sm" variant="ghost" onClick={() => edit(portrait)}><Pencil />{t("users.edit")}</Button><Button size="sm" variant="ghost" disabled={toggleDefault.isPending} onClick={() => toggleDefault.mutate(portrait)}>{portrait.is_default ? t("agent.removeDefaultCompanion") : t("agent.makeDefaultCompanion")}</Button></div>)}</div></CardContent></Card>;
}

function CompanionSection({ companions, models, portraits, loading, onSaved }: {
  companions: AdminCompanion[];
  models: AIModel[];
  portraits: CompanionPortrait[];
  loading: boolean;
  onSaved: () => void;
}) {
  const { t } = useTranslation();
  const [form, setForm] = useState<AdminCompanion | null>(null);
  const [imageUploading, setImageUploading] = useState(false);
  const chatModels = models.filter((model) => (model.configured_scenarios ?? []).includes("text_chat"));
  const save = useMutation({
    mutationFn: () => {
      if (!form) throw new Error("No companion selected");
      const body: AdminCompanionInput = { ...form };
      return agentApi.updateCompanion(form.id, body);
    },
    onSuccess: () => { toast.success(t("agent.saved")); setForm(null); onSaved(); },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });
  if (loading) return <Skeleton className="h-72" />;
  return <>
    <Card><CardContent className="p-4">
      {companions.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">{t("agent.noCompanions")}</p>
        : <Table><TableHeader><TableRow>
          <TableHead>{t("agent.companion")}</TableHead><TableHead>{t("companions.owner")}</TableHead>
          <TableHead>{t("agent.city")}</TableHead><TableHead>{t("agent.model")}</TableHead>
          <TableHead>{t("agent.proactiveEnabled")}</TableHead><TableHead className="text-end">{t("users.actions")}</TableHead>
        </TableRow></TableHeader><TableBody>{companions.map((item) => {
          const portrait = portraits.find((entry) => entry.id === item.portrait_id);
          const model = models.find((entry) => entry.id === item.model_id);
          const imageURL = item.avatar_url || portrait?.image_url || "";
          const summary = [
            `${t("agent.name")}: ${item.name}`,
            `${t("agent.city")}: ${item.city || "—"}`,
            `${t("agent.occupation")}: ${item.occupation || "—"}`,
            `${t("agent.model")}: ${model?.display_name ?? item.model_id ?? t("agent.useDefault")}`,
            `${t("agent.portrait")}: ${portrait?.name ?? item.portrait_id ?? t("agent.noPortrait")}`,
            `${t("agent.imageUrl")}: ${imageURL || "—"}`,
            `${t("agent.tags")}: ${item.personality_tags.join(", ") || "—"}`,
            `${t("agent.proactiveEnabled")}: ${t(item.proactive_enabled ? "content.enabled" : "content.disabled")}`,
            `${t("agent.persona")}: ${item.persona || "—"}`,
            `${t("agent.backstory")}: ${item.backstory || "—"}`,
            `${t("agent.speakingStyle")}: ${item.speaking_style || "—"}`,
            `${t("agent.habitsGoal")}: ${item.life_habits || "—"} / ${item.life_goal || "—"}`,
          ];
          return <TableRow key={item.id}>
            <TableCell><div className="flex items-center gap-3">
              {imageURL.startsWith("http://") || imageURL.startsWith("https://")
                ? <img src={imageURL} alt="" className="size-10 rounded-full object-cover" />
                : <span className="grid size-10 place-items-center rounded-full bg-muted"><Bot className="size-5" /></span>}
              <div><div className="font-medium">{item.name}</div><div className="text-xs text-muted-foreground">{item.occupation || "—"}</div></div>
            </div></TableCell>
            <TableCell>{item.user_email}</TableCell><TableCell>{item.city || "—"}</TableCell>
            <TableCell>{model?.display_name ?? t("agent.useDefault")}</TableCell>
            <TableCell><Badge variant={item.proactive_enabled ? "success" : "outline"}>{t(item.proactive_enabled ? "content.enabled" : "content.disabled")}</Badge></TableCell>
            <TableCell className="text-end"><ConfigurationButton label={t("users.edit")} icon={<Bot />} onClick={() => setForm({ ...item, personality_tags: [...item.personality_tags] })} details={summary} /></TableCell>
          </TableRow>;
        })}</TableBody></Table>}
    </CardContent></Card>
    <Dialog open={form !== null} onOpenChange={(next) => { if (!next) setForm(null); }}>
      <DialogContent className="max-h-[85vh] max-w-3xl overflow-y-auto">
        <DialogHeader><DialogTitle>{t("agent.saveCompanion")}</DialogTitle><DialogDescription>{t("agent.companionsDesc")}</DialogDescription></DialogHeader>
        {form && <div className="space-y-4">
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            <Field label={t("agent.name")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
            <Field label={t("agent.city")}><Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></Field>
            <Field label={t("agent.occupation")}><Input value={form.occupation} onChange={(e) => setForm({ ...form, occupation: e.target.value })} /></Field>
            <Field label={t("agent.model")}><Select value={form.model_id ?? "none"} onValueChange={(value) => setForm({ ...form, model_id: value === "none" ? null : value })}>
              <SelectTrigger className="w-full"><SelectValue placeholder={t("agent.useDefault")} /></SelectTrigger>
              <SelectContent><SelectItem value="none">{t("mediaModels.notSelected")}</SelectItem>{chatModels.map((model) => <SelectItem key={model.id} value={model.id}>{model.display_name}</SelectItem>)}</SelectContent>
            </Select></Field>
            <Field label={t("agent.portrait")}><Select value={form.portrait_id ?? "none"} onValueChange={(value) => setForm({ ...form, portrait_id: value === "none" ? null : value })}>
              <SelectTrigger className="w-full"><SelectValue placeholder={t("agent.noPortrait")} /></SelectTrigger>
              <SelectContent><SelectItem value="none">{t("mediaModels.notSelected")}</SelectItem>{portraits.map((portrait) => <SelectItem key={portrait.id} value={portrait.id}>{portrait.name}</SelectItem>)}</SelectContent>
            </Select></Field>
            <Field label={t("agent.tags")}><Input value={form.personality_tags.join(", ")} onChange={(e) => setForm({ ...form, personality_tags: e.target.value.split(",").map((value) => value.trim()).filter(Boolean) })} /></Field>
          </div>
          <Field label={t("agent.imageUrl")}><AdminImageInput value={form.avatar_url} allowExistingValue={companions.find((item) => item.id === form.id)?.avatar_url} onChange={(url) => setForm({ ...form, avatar_url: url })} onUploadingChange={setImageUploading} /></Field>
          <p className="text-xs text-muted-foreground">{t("adminImages.inheritPortrait")}</p>
          <div className="grid gap-3 md:grid-cols-2">
            <Field label={t("agent.persona")}><textarea className={textareaClass} value={form.persona} onChange={(e) => setForm({ ...form, persona: e.target.value })} /></Field>
            <Field label={t("agent.backstory")}><textarea className={textareaClass} value={form.backstory} onChange={(e) => setForm({ ...form, backstory: e.target.value })} /></Field>
            <Field label={t("agent.speakingStyle")}><textarea className={textareaClass} value={form.speaking_style} onChange={(e) => setForm({ ...form, speaking_style: e.target.value })} /></Field>
            <Field label={t("agent.habitsGoal")}><textarea className={textareaClass} value={`${form.life_habits}\n${form.life_goal}`} onChange={(e) => { const [life_habits, ...rest] = e.target.value.split("\n"); setForm({ ...form, life_habits, life_goal: rest.join("\n") }); }} /></Field>
          </div>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.proactive_enabled} onChange={(e) => setForm({ ...form, proactive_enabled: e.target.checked })} />{t("agent.proactiveEnabled")}</label>
          <div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setForm(null)}>{t("users.cancel")}</Button><Button disabled={save.isPending || imageUploading || (form.avatar_url.trim() !== "" && form.avatar_url !== companions.find((item) => item.id === form.id)?.avatar_url && !isAdminImageURL(form.avatar_url.trim()))} onClick={() => save.mutate()}><Save />{t("agent.saveCompanion")}</Button></div>
        </div>}
      </DialogContent>
    </Dialog>
  </>;
}
