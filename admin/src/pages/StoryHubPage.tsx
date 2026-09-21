import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BookOpen, Pencil, Plus, Save, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { envApi, storiesApi } from "@/api/admin";
import type { Environment, StoryBackground, StoryBackgroundInput, StoryConfig } from "@/api/types";
import { ENVIRONMENTS } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const blank = (environment: Environment): StoryBackgroundInput => ({ environment, title: "", cover_url: "", synopsis: "", world_setting: "", opening: "", genre: "", character_constraints: "", story_goal: "", sort_order: 0, enabled: true });
function Field({ label, children, wide = false }: { label: string; children: React.ReactNode; wide?: boolean }) { return <div className={`space-y-1.5 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>; }
const area = "min-h-24 w-full rounded-md border bg-background p-3 text-sm";

export function StoryHubPage() {
  const { t } = useTranslation(); const queryClient = useQueryClient();
  const env = useQuery({ queryKey: ["admin-environment"], queryFn: ({ signal }) => envApi.get(signal) });
  const [environment, setEnvironment] = useState<Environment | null>(null); const active = environment ?? env.data?.environment;
  const config = useQuery({ queryKey: ["story-config", active], queryFn: ({ signal }) => storiesApi.config(active!, signal), enabled: Boolean(active) });
  const backgrounds = useQuery({ queryKey: ["story-backgrounds", active], queryFn: ({ signal }) => storiesApi.backgrounds(active!, signal), enabled: Boolean(active) });
  const [rules, setRules] = useState<StoryConfig | null>(null); const [editing, setEditing] = useState<string | null>(null); const [form, setForm] = useState<StoryBackgroundInput>(blank("dev"));
  useEffect(() => { if (!environment && env.data?.environment) setEnvironment(env.data.environment); }, [environment, env.data]);
  useEffect(() => { if (config.data) setRules(config.data); }, [config.data]);
  useEffect(() => { if (active && !editing) setForm(blank(active)); }, [active, editing]);
  const refresh = () => { void queryClient.invalidateQueries({ queryKey: ["story-backgrounds"] }); };
  const saveRules = useMutation({ mutationFn: () => storiesApi.saveConfig(rules!), onSuccess: (value) => { setRules(value); toast.success(t("storyHub.saved")); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const save = useMutation({ mutationFn: () => editing ? storiesApi.updateBackground(editing, form) : storiesApi.createBackground(form), onSuccess: () => { toast.success(t("storyHub.saved")); setEditing(null); if (active) setForm(blank(active)); refresh(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const remove = useMutation({ mutationFn: storiesApi.removeBackground, onSuccess: () => { toast.success(t("storyHub.deleted")); refresh(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const edit = (x: StoryBackground) => { setEditing(x.id); const { id: _, ...input } = x; setForm(input); };
  return <div className="space-y-6"><PageHeader title={t("storyHub.title")} description={t("storyHub.desc")} actions={<Select value={active ?? ""} onValueChange={(v) => { setEnvironment(v as Environment); setEditing(null); }}><SelectTrigger className="w-40"><SelectValue /></SelectTrigger><SelectContent>{ENVIRONMENTS.map((x) => <SelectItem key={x} value={x}>{t(`billing.env.${x}`)}</SelectItem>)}</SelectContent></Select>} />
    <Card><CardHeader><CardTitle>{t("storyHub.rules")}</CardTitle><CardDescription>{t("storyHub.customLimitHint")}</CardDescription></CardHeader><CardContent>{rules && <div className="grid gap-4 md:grid-cols-3">{(["free_chapter_limit","custom_background_limit","storyboard_unlock_chapters","chapter_coins","storyboard_coins"] as const).map((key) => <Field key={key} label={t(`storyHub.${({free_chapter_limit:"freeLimit",custom_background_limit:"customLimit",storyboard_unlock_chapters:"unlock",chapter_coins:"chapterCoins",storyboard_coins:"storyboardCoins"} as const)[key]}`)}><Input type="number" min={key === "free_chapter_limit" || key === "custom_background_limit" ? 0 : 1} value={rules[key]} onChange={(e) => setRules({...rules,[key]:Number(e.target.value)})}/></Field>)}<div className="flex items-end"><Button disabled={saveRules.isPending} onClick={() => saveRules.mutate()}><Save />{t("storyHub.saveRules")}</Button></div></div>}</CardContent></Card>
    <Card><CardHeader><CardTitle>{editing ? t("storyHub.edit") : t("storyHub.create")}</CardTitle></CardHeader><CardContent className="space-y-4"><div className="grid gap-4 md:grid-cols-2"><Field label={t("storyHub.name")}><Input value={form.title} onChange={(e)=>setForm({...form,title:e.target.value})}/></Field><Field label={t("storyHub.cover")}><Input value={form.cover_url} onChange={(e)=>setForm({...form,cover_url:e.target.value})}/></Field><Field label={t("storyHub.genre")}><Input value={form.genre} onChange={(e)=>setForm({...form,genre:e.target.value})}/></Field><Field label={t("storyHub.sort")}><Input type="number" value={form.sort_order} onChange={(e)=>setForm({...form,sort_order:Number(e.target.value)})}/></Field><Field wide label={t("storyHub.synopsis")}><textarea className={area} value={form.synopsis} onChange={(e)=>setForm({...form,synopsis:e.target.value})}/></Field><Field wide label={t("storyHub.world")}><textarea className={area} value={form.world_setting} onChange={(e)=>setForm({...form,world_setting:e.target.value})}/></Field><Field wide label={t("storyHub.opening")}><textarea className={area} value={form.opening} onChange={(e)=>setForm({...form,opening:e.target.value})}/></Field><Field label={t("storyHub.constraints")}><textarea className={area} value={form.character_constraints} onChange={(e)=>setForm({...form,character_constraints:e.target.value})}/></Field><Field label={t("storyHub.goal")}><textarea className={area} value={form.story_goal} onChange={(e)=>setForm({...form,story_goal:e.target.value})}/></Field></div><label className="flex gap-2 text-sm"><input type="checkbox" checked={form.enabled} onChange={(e)=>setForm({...form,enabled:e.target.checked})}/>{t("storyHub.enabled")}</label><div className="flex gap-2"><Button disabled={!form.title.trim()||!form.world_setting.trim()||!form.opening.trim()||save.isPending} onClick={()=>save.mutate()}>{editing?<Save/>:<Plus/>}{t("storyHub.saveBackground")}</Button>{editing&&<Button variant="outline" onClick={()=>{setEditing(null);if(active)setForm(blank(active));}}>{t("users.cancel")}</Button>}</div></CardContent></Card>
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{(backgrounds.data?.items??[]).map((x)=><Card key={x.id}><CardContent className="p-4"><div className="flex items-start gap-3">{x.cover_url?<img src={x.cover_url} className="size-20 rounded-xl object-cover"/>:<div className="grid size-20 place-items-center rounded-xl bg-muted"><BookOpen/></div>}<div className="min-w-0 flex-1"><div className="flex gap-2 font-semibold">{x.title}<Badge variant={x.enabled?"success":"outline"}>{x.enabled?t("content.enabled"):t("content.disabled")}</Badge></div><p className="mt-2 line-clamp-3 text-sm text-muted-foreground">{x.synopsis||x.world_setting}</p></div></div><div className="mt-4 flex justify-end gap-2"><Button size="sm" variant="outline" onClick={()=>edit(x)}><Pencil/></Button><Button size="sm" variant="destructive" onClick={()=>{if(confirm(t("storyHub.deleteConfirm")))remove.mutate(x.id)}}><Trash2/></Button></div></CardContent></Card>)}</div>
  </div>;
}
