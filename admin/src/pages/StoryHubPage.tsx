import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BookOpen, Pencil, Plus, Save, Settings2, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { storiesApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { Environment, StoryBackground, StoryBackgroundInput, StoryConfig } from "@/api/types";
import { ConfigurationButton } from "@/components/configuration-button";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

const blank = (environment: Environment): StoryBackgroundInput => ({
  environment, title: "", cover_url: "", synopsis: "", world_setting: "", opening: "",
  genre: "", character_constraints: "", story_goal: "", sort_order: 0, enabled: true,
});
const area = "min-h-24 w-full rounded-md border bg-background p-3 text-sm";
const ruleKeys = ["free_chapter_limit", "custom_background_limit", "storyboard_unlock_chapters", "chapter_coins", "storyboard_coins"] as const;
const ruleLabels = { free_chapter_limit: "freeLimit", custom_background_limit: "customLimit", storyboard_unlock_chapters: "unlock", chapter_coins: "chapterCoins", storyboard_coins: "storyboardCoins" } as const;

function Field({ label, children, wide = false }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return <div className={`space-y-1.5 ${wide ? "md:col-span-2" : ""}`}><Label>{label}</Label>{children}</div>;
}

export function StoryHubPage() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const active: Environment = "prod";
  const config = useQuery({ queryKey: ["story-config", active], queryFn: ({ signal }) => storiesApi.config(active!, signal), enabled: Boolean(active) });
  const backgrounds = useQuery({ queryKey: ["story-backgrounds", active], queryFn: ({ signal }) => storiesApi.backgrounds(active!, signal), enabled: Boolean(active) });
  const [rulesOpen, setRulesOpen] = useState(false);
  const [backgroundOpen, setBackgroundOpen] = useState(false);
  const [rules, setRules] = useState<StoryConfig | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<StoryBackground | null>(null);
  const [form, setForm] = useState<StoryBackgroundInput>(blank("prod"));

  useEffect(() => { if (!rulesOpen && config.data) setRules(config.data); }, [config.data, rulesOpen]);
  const refresh = () => { void queryClient.invalidateQueries({ queryKey: ["story-backgrounds", active] }); };
  const closeBackground = () => { setBackgroundOpen(false); setEditing(null); };
  const saveRules = useMutation({
    mutationFn: () => storiesApi.saveConfig(rules!),
    onSuccess: (value) => {
      setRules(value);
      setRulesOpen(false);
      queryClient.setQueryData(["story-config", active], value);
      toast.success(t("storyHub.saved"));
    },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });
  const save = useMutation({
    mutationFn: () => editing ? storiesApi.updateBackground(editing, form) : storiesApi.createBackground(form),
    onSuccess: () => { toast.success(t("storyHub.saved")); closeBackground(); refresh(); },
    onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))),
  });
  const remove = useMutation({ mutationFn: storiesApi.removeBackground, onSuccess: () => { toast.success(t("storyHub.deleted")); setDeleteTarget(null); refresh(); }, onError: (e) => toast.error(errorMessage(e, t("common.failedToLoad"))) });
  const create = () => { if (!active) return; setEditing(null); setForm(blank(active)); setBackgroundOpen(true); };
  const edit = (item: StoryBackground) => { const { id: _, ...input } = item; setEditing(item.id); setForm(input); setBackgroundOpen(true); };
  const savedRules = config.data;
  const ruleSummary = savedRules
    ? ruleKeys.map((key) => `${t(`storyHub.${ruleLabels[key]}`)}: ${savedRules[key]}`)
    : [t(config.isError ? "common.failedToLoad" : "common.loading")];

  return <div className="space-y-6">
    <PageHeader title={t("storyHub.title")} description={t("storyHub.desc")} actions={<>
      <ConfigurationButton label={t("storyHub.rules")} icon={<Settings2 />} onClick={() => { setRules(savedRules ? { ...savedRules } : null); setRulesOpen(true); }} disabled={!savedRules} details={ruleSummary} />
      <ConfigurationButton label={t("storyHub.create")} icon={<Plus />} onClick={create} disabled={!active}
        details={backgrounds.data ? [`${t("storyHub.configuredCount")}: ${backgrounds.data.items.length}`, ...backgrounds.data.items.map((item) => item.title)] : [t(backgrounds.isError ? "common.failedToLoad" : "common.loading")]} />
    </>} />
    <Card><CardContent className="p-4">
      {backgrounds.isError ? <p className="py-8 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
        : backgrounds.isLoading ? <p className="py-8 text-center text-sm text-muted-foreground">{t("common.loading")}</p>
        : !backgrounds.data?.items.length ? <p className="py-8 text-center text-sm text-muted-foreground">{t("storyHub.empty")}</p>
        : <Table><TableHeader><TableRow>
          <TableHead>{t("storyHub.name")}</TableHead><TableHead>{t("storyHub.genre")}</TableHead>
          <TableHead>{t("storyHub.sort")}</TableHead><TableHead>{t("storyHub.enabled")}</TableHead>
          <TableHead className="text-end">{t("users.actions")}</TableHead>
        </TableRow></TableHeader><TableBody>{backgrounds.data.items.map((item) => <TableRow key={item.id}>
          <TableCell><div className="flex items-center gap-3">
            {item.cover_url ? <img src={item.cover_url} alt="" className="size-12 shrink-0 rounded-lg object-cover" /> : <span className="grid size-12 shrink-0 place-items-center rounded-lg bg-muted"><BookOpen className="size-5" /></span>}
            <div><div className="font-medium">{item.title}</div><div className="line-clamp-1 max-w-72 text-xs text-muted-foreground">{item.synopsis || item.world_setting}</div></div>
          </div></TableCell>
          <TableCell>{item.genre || "—"}</TableCell><TableCell>{item.sort_order}</TableCell>
          <TableCell><Badge variant={item.enabled ? "success" : "outline"}>{t(item.enabled ? "content.enabled" : "content.disabled")}</Badge></TableCell>
          <TableCell className="text-end"><div className="inline-flex items-center gap-2">
            <ConfigurationButton label={t("users.edit")} icon={<Pencil />} onClick={() => edit(item)} details={[
              `${t("storyHub.name")}: ${item.title}`, `${t("storyHub.genre")}: ${item.genre || "—"}`,
              `${t("storyHub.sort")}: ${item.sort_order}`, `${t("storyHub.enabled")}: ${t(item.enabled ? "content.enabled" : "content.disabled")}`,
              `${t("storyHub.cover")}: ${item.cover_url || "—"}`, `${t("storyHub.synopsis")}: ${item.synopsis || "—"}`,
              `${t("storyHub.world")}: ${item.world_setting}`, `${t("storyHub.opening")}: ${item.opening}`,
              `${t("storyHub.constraints")}: ${item.character_constraints || "—"}`, `${t("storyHub.goal")}: ${item.story_goal || "—"}`,
            ]} />
            <Button size="sm" variant="destructive" disabled={remove.isPending} onClick={() => setDeleteTarget(item)}><Trash2 />{t("storyHub.delete")}</Button>
          </div></TableCell>
        </TableRow>)}</TableBody></Table>}
    </CardContent></Card>
    <Dialog open={rulesOpen} onOpenChange={(next) => { if (!next) { setRulesOpen(false); setRules(savedRules ?? null); } }}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader><DialogTitle>{t("storyHub.rules")}</DialogTitle><DialogDescription>{t("storyHub.customLimitHint")}</DialogDescription></DialogHeader>
        {rules && <div className="grid gap-4 md:grid-cols-2">{ruleKeys.map((key) => <Field key={key} label={t(`storyHub.${ruleLabels[key]}`)}>
          <Input type="number" min={key === "free_chapter_limit" || key === "custom_background_limit" ? 0 : 1} value={rules[key]} onChange={(e) => setRules({ ...rules, [key]: Number(e.target.value) })} />
        </Field>)}</div>}
        <DialogFooter><Button variant="outline" onClick={() => { setRulesOpen(false); setRules(savedRules ?? null); }}>{t("users.cancel")}</Button><Button disabled={!rules || saveRules.isPending} onClick={() => saveRules.mutate()}><Save />{t("storyHub.saveRules")}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
    <Dialog open={backgroundOpen} onOpenChange={(next) => { if (!next) closeBackground(); }}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader><DialogTitle>{editing ? t("storyHub.edit") : t("storyHub.create")}</DialogTitle><DialogDescription>{t("storyHub.backgrounds")}</DialogDescription></DialogHeader>
        <div className="grid gap-4 md:grid-cols-2">
          <Field label={t("storyHub.name")}><Input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
          <Field label={t("storyHub.cover")}><Input value={form.cover_url} onChange={(e) => setForm({ ...form, cover_url: e.target.value })} /></Field>
          <Field label={t("storyHub.genre")}><Input value={form.genre} onChange={(e) => setForm({ ...form, genre: e.target.value })} /></Field>
          <Field label={t("storyHub.sort")}><Input type="number" value={form.sort_order} onChange={(e) => setForm({ ...form, sort_order: Number(e.target.value) })} /></Field>
          <Field wide label={t("storyHub.synopsis")}><textarea className={area} value={form.synopsis} onChange={(e) => setForm({ ...form, synopsis: e.target.value })} /></Field>
          <Field wide label={t("storyHub.world")}><textarea className={area} value={form.world_setting} onChange={(e) => setForm({ ...form, world_setting: e.target.value })} /></Field>
          <Field wide label={t("storyHub.opening")}><textarea className={area} value={form.opening} onChange={(e) => setForm({ ...form, opening: e.target.value })} /></Field>
          <Field label={t("storyHub.constraints")}><textarea className={area} value={form.character_constraints} onChange={(e) => setForm({ ...form, character_constraints: e.target.value })} /></Field>
          <Field label={t("storyHub.goal")}><textarea className={area} value={form.story_goal} onChange={(e) => setForm({ ...form, story_goal: e.target.value })} /></Field>
        </div>
        <label className="flex gap-2 text-sm"><input type="checkbox" checked={form.enabled} onChange={(e) => setForm({ ...form, enabled: e.target.checked })} />{t("storyHub.enabled")}</label>
        <DialogFooter><Button variant="outline" onClick={closeBackground}>{t("users.cancel")}</Button><Button disabled={!form.title.trim() || !form.world_setting.trim() || !form.opening.trim() || save.isPending} onClick={() => save.mutate()}>{editing ? <Save /> : <Plus />}{t("storyHub.saveBackground")}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
    <AlertDialog open={Boolean(deleteTarget)} onOpenChange={(next) => { if (!next) setDeleteTarget(null); }}>
      <AlertDialogContent>
        <AlertDialogHeader><AlertDialogTitle>{t("storyHub.deleteTitle")}</AlertDialogTitle><AlertDialogDescription>{t("storyHub.deleteDesc", { name: deleteTarget?.title ?? "" })}</AlertDialogDescription></AlertDialogHeader>
        <AlertDialogFooter><AlertDialogCancel disabled={remove.isPending}>{t("users.cancel")}</AlertDialogCancel><AlertDialogAction asChild><Button variant="destructive" disabled={remove.isPending} onClick={(event) => { event.preventDefault(); if (deleteTarget) remove.mutate(deleteTarget.id); }}>{t("storyHub.deleteConfirm")}</Button></AlertDialogAction></AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>;
}
