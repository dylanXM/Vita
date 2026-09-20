import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, MessageSquare, RefreshCw, Save, Trash2, Volume2 } from "lucide-react";
import { useTranslation } from "react-i18next";

import { agentApi, companionsApi } from "@/api/admin";
import type { AdminCompanionInput } from "@/api/types";
import { errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { toast } from "@/components/ui/sonner";
import { formatDate } from "@/lib/format";
import { EnvBadge } from "./UsersPage";

const textareaClass = "min-h-24 w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-1.5"><Label>{label}</Label>{children}</div>;
}

export function CompanionDetailPage() {
  const { id = "" } = useParams();
  const { t } = useTranslation();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [deleteOpen, setDeleteOpen] = useState(false);
  const detail = useQuery({ queryKey: ["managed-companion", id], queryFn: ({ signal }) => companionsApi.get(id, signal), retry: false });
  const config = useQuery({ queryKey: ["agent-config"], queryFn: ({ signal }) => agentApi.config(signal) });
  const [form, setForm] = useState<AdminCompanionInput | null>(null);
  const [voiceJSON, setVoiceJSON] = useState("{}");
  useEffect(() => {
    if (!detail.data) return;
    const value = detail.data;
    setForm({
      user_id: value.user_id, name: value.name, gender: value.gender, persona: value.persona,
      city: value.city, occupation: value.occupation, interests: value.interests,
      relationship_stage: value.relationship_stage, personality_tags: value.personality_tags,
      speaking_style: value.speaking_style, likes: value.likes, dislikes: value.dislikes,
      life_habits: value.life_habits, life_goal: value.life_goal, backstory: value.backstory,
      model_id: value.model_id, portrait_id: value.portrait_id, proactive_enabled: value.proactive_enabled,
      active: value.active, voice_enabled: value.voice_enabled, voice_config: value.voice_config ?? {},
    });
    setVoiceJSON(JSON.stringify(value.voice_config ?? {}, null, 2));
  }, [detail.data]);

  const save = useMutation({
    mutationFn: () => {
      if (!form) throw new Error("missing form");
      let voiceConfig: Record<string, unknown>;
      try { voiceConfig = JSON.parse(voiceJSON) as Record<string, unknown>; }
      catch { throw new Error(t("companions.voiceJSONInvalid")); }
      return companionsApi.update(id, { ...form, voice_config: voiceConfig });
    },
    onSuccess: () => {
      toast.success(t("companions.saved"));
      void queryClient.invalidateQueries({ queryKey: ["managed-companion", id] });
      void queryClient.invalidateQueries({ queryKey: ["managed-companions"] });
    },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });
  const remove = useMutation({
    mutationFn: () => companionsApi.remove(id),
    onSuccess: () => { toast.success(t("companions.deleted")); navigate("/companions"); },
    onError: (error) => toast.error(errorMessage(error, t("common.failedToLoad"))),
  });

  if (detail.isLoading) return <div className="space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-72 w-full" /></div>;
  if (detail.isError || !detail.data) return <PageHeader title={t("companions.notFound")} actions={<Button variant="outline" asChild><Link to="/companions"><ArrowLeft />{t("companions.back")}</Link></Button>} />;
  if (!form) return <div className="space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-72 w-full" /></div>;
  const companion = detail.data;
  const tags = form.personality_tags.join(", ");

  return <div className="space-y-6">
    <PageHeader
      title={<span className="flex flex-wrap items-center gap-2">{companion.name}<EnvBadge env={companion.environment} /><Badge variant={companion.active ? "success" : "muted"}>{t(companion.active ? "companions.active" : "companions.inactive")}</Badge></span>}
      description={`${companion.user_email} · ${companion.id}`}
      actions={<><Button variant="outline" asChild><Link to="/companions"><ArrowLeft />{t("companions.back")}</Link></Button><Button variant="outline" onClick={() => void detail.refetch()}><RefreshCw />{t("common.refresh")}</Button><Button variant="destructive" onClick={() => setDeleteOpen(true)}><Trash2 />{t("users.delete")}</Button></>}
    />

    <div className="grid gap-6 xl:grid-cols-3">
      <Card className="xl:col-span-2"><CardHeader><CardTitle>{t("companions.profile")}</CardTitle><CardDescription>{t("companions.profileDesc")}</CardDescription></CardHeader><CardContent className="space-y-5">
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <Field label={t("agent.name")}><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} /></Field>
          <Field label={t("agent.gender")}><Input value={form.gender} onChange={(e) => setForm({ ...form, gender: e.target.value })} /></Field>
          <Field label={t("agent.city")}><Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} /></Field>
          <Field label={t("agent.occupation")}><Input value={form.occupation} onChange={(e) => setForm({ ...form, occupation: e.target.value })} /></Field>
          <Field label={t("companions.relationshipStage")}><Input value={form.relationship_stage} onChange={(e) => setForm({ ...form, relationship_stage: e.target.value })} /></Field>
          <Field label={t("agent.tags")}><Input value={tags} onChange={(e) => setForm({ ...form, personality_tags: e.target.value.split(",").map((tag) => tag.trim()).filter(Boolean) })} /></Field>
          <Field label={t("agent.model")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.model_id ?? ""} onChange={(e) => setForm({ ...form, model_id: e.target.value || null })}><option value="">{t("agent.useDefault")}</option>{config.data?.models.map((model) => <option key={model.id} value={model.id}>{model.display_name}</option>)}</select></Field>
          <Field label={t("agent.portrait")}><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={form.portrait_id ?? ""} onChange={(e) => setForm({ ...form, portrait_id: e.target.value || null })}><option value="">{t("agent.noPortrait")}</option>{config.data?.portraits.map((portrait) => <option key={portrait.id} value={portrait.id}>{portrait.name}</option>)}</select></Field>
          <Field label={t("companions.interests")}><Input value={form.interests} onChange={(e) => setForm({ ...form, interests: e.target.value })} /></Field>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <Field label={t("agent.persona")}><textarea className={textareaClass} value={form.persona} onChange={(e) => setForm({ ...form, persona: e.target.value })} /></Field>
          <Field label={t("agent.backstory")}><textarea className={textareaClass} value={form.backstory} onChange={(e) => setForm({ ...form, backstory: e.target.value })} /></Field>
          <Field label={t("agent.speakingStyle")}><textarea className={textareaClass} value={form.speaking_style} onChange={(e) => setForm({ ...form, speaking_style: e.target.value })} /></Field>
          <Field label={t("companions.lifeHabitsGoal")}><textarea className={textareaClass} value={`${form.life_habits}\n${form.life_goal}`} onChange={(e) => { const [life_habits, ...goal] = e.target.value.split("\n"); setForm({ ...form, life_habits, life_goal: goal.join("\n") }); }} /></Field>
          <Field label={t("companions.likes")}><textarea className={textareaClass} value={form.likes} onChange={(e) => setForm({ ...form, likes: e.target.value })} /></Field>
          <Field label={t("companions.dislikes")}><textarea className={textareaClass} value={form.dislikes} onChange={(e) => setForm({ ...form, dislikes: e.target.value })} /></Field>
        </div>
        <div className="flex flex-wrap gap-6 text-sm"><label className="flex items-center gap-2"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} />{t("companions.roleEnabled")}</label><label className="flex items-center gap-2"><input type="checkbox" checked={form.proactive_enabled} onChange={(e) => setForm({ ...form, proactive_enabled: e.target.checked })} />{t("agent.proactiveEnabled")}</label></div>
        <Button disabled={!form.name.trim() || save.isPending} onClick={() => save.mutate()}><Save />{t("users.save")}</Button>
      </CardContent></Card>

      <div className="space-y-6">
        <Card><CardHeader><CardTitle>{t("companions.runtime")}</CardTitle></CardHeader><CardContent className="grid grid-cols-2 gap-4 text-sm">
          <Metric label={t("companions.conversations")} value={companion.conversations} /><Metric label={t("companions.messages")} value={companion.messages} /><Metric label={t("companions.memories")} value={companion.memories} /><Metric label={t("companions.lifeEvents")} value={companion.life_events} />
          <Metric label={t("companions.intimacy")} value={companion.relationship.intimacy} /><Metric label={t("companions.enthusiasm")} value={companion.relationship.enthusiasm} /><Metric label={t("companions.mood")} value={companion.state.mood} /><Metric label={t("companions.energy")} value={companion.state.energy} />
          <div className="col-span-2 border-t pt-3 text-xs text-muted-foreground">{t("companions.createdUpdated", { created: formatDate(companion.created_at), updated: formatDate(companion.updated_at) })}</div>
        </CardContent></Card>
        <Card><CardHeader><CardTitle className="flex items-center gap-2"><Volume2 className="size-5" />{t("companions.voice")}</CardTitle><CardDescription>{t("companions.voiceDesc")}</CardDescription></CardHeader><CardContent className="space-y-4"><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.voice_enabled} onChange={(e) => setForm({ ...form, voice_enabled: e.target.checked })} />{t("companions.voiceEnabled")}</label><Field label={t("companions.voiceConfig")}><textarea className={`${textareaClass} font-mono text-xs`} value={voiceJSON} onChange={(e) => setVoiceJSON(e.target.value)} /></Field><p className="text-xs text-muted-foreground">{t("companions.voiceNotice")}</p></CardContent></Card>
      </div>
    </div>

    <ConversationPanel companionID={id} companionName={companion.name} />

    <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>{t("companions.deleteTitle")}</AlertDialogTitle><AlertDialogDescription>{t("companions.deleteDesc", { name: companion.name })}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>{t("users.cancel")}</AlertDialogCancel><AlertDialogAction asChild><Button variant="destructive" disabled={remove.isPending} onClick={(event) => { event.preventDefault(); remove.mutate(); }}>{t("companions.deleteConfirm")}</Button></AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </div>;
}

function Metric({ label, value }: { label: string; value: number }) { return <div><div className="text-xs text-muted-foreground">{label}</div><div className="mt-1 text-xl font-semibold">{value}</div></div>; }

function ConversationPanel({ companionID, companionName }: { companionID: string; companionName: string }) {
  const { t } = useTranslation();
  const conversations = useQuery({ queryKey: ["companion-conversations", companionID], queryFn: ({ signal }) => companionsApi.conversations(companionID, signal) });
  const [selectedID, setSelectedID] = useState("");
  const selected = useMemo(() => conversations.data?.items.find((item) => item.id === selectedID) ?? conversations.data?.items[0], [conversations.data, selectedID]);
  const [page, setPage] = useState(1);
  useEffect(() => setPage(1), [selected?.id]);
  const messages = useQuery({ queryKey: ["companion-messages", companionID, selected?.id, page], queryFn: ({ signal }) => companionsApi.messages(companionID, selected!.id, page, signal), enabled: Boolean(selected?.id) });
  const ordered = [...(messages.data?.items ?? [])].reverse();
  return <Card><CardHeader><CardTitle className="flex items-center gap-2"><MessageSquare className="size-5" />{t("companions.chatHistory")}</CardTitle><CardDescription>{t("companions.chatHistoryDesc")}</CardDescription></CardHeader><CardContent>
    {conversations.isLoading ? <Skeleton className="h-64 w-full" /> : !selected ? <p className="py-10 text-center text-sm text-muted-foreground">{t("companions.noConversations")}</p> : <div className="grid min-h-96 gap-4 lg:grid-cols-[280px_1fr]">
      <div className="divide-y rounded-md border">{conversations.data?.items.map((conversation) => <button key={conversation.id} type="button" onClick={() => setSelectedID(conversation.id)} className={`block w-full p-3 text-start text-sm hover:bg-muted/60 ${conversation.id === selected.id ? "bg-muted" : ""}`}><div className="font-medium">{t("companions.conversation")}</div><div className="mt-1 truncate text-xs text-muted-foreground">{conversation.last_message || t("companions.noMessages")}</div><div className="mt-1 text-xs text-muted-foreground">{conversation.message_count} · {conversation.last_message_at ? formatDate(conversation.last_message_at) : "—"}</div></button>)}</div>
      <div className="flex min-h-96 flex-col rounded-md border bg-muted/30">
        <div className="border-b px-4 py-3 text-sm font-medium">{t("companions.userAndRole", { name: companionName })}</div>
        <div className="flex-1 space-y-3 overflow-y-auto p-4">{messages.isLoading ? <Skeleton className="h-40 w-full" /> : ordered.length === 0 ? <p className="py-10 text-center text-sm text-muted-foreground">{t("companions.noMessages")}</p> : ordered.map((message) => { const fromUser = message.sender_type === "user"; const proactive = isProactiveMessage(message.source, message.life_event_id); return <div key={message.id} className={`flex ${fromUser ? "justify-end" : "justify-start"}`}><div className={`max-w-[80%] rounded-md px-3 py-2 text-sm ${fromUser ? "bg-primary text-primary-foreground" : "border bg-background"}`}><div className="mb-1 flex flex-wrap items-center gap-1.5 text-[11px] opacity-80"><span>{fromUser ? t("companions.user") : companionName} · {message.message_type}</span>{!fromUser && <Badge variant={proactive ? "warning" : "secondary"}>{t(proactive ? "companions.proactiveMessage" : "companions.replyToUser")}</Badge>}</div>{message.content && <div className="whitespace-pre-wrap break-words">{message.content}</div>}{message.media_url && <a href={message.media_url} target="_blank" rel="noreferrer" className="mt-1 block underline">{t("companions.media")}</a>}<div className="mt-1 text-[10px] opacity-60">{formatDate(message.created_at)} · {message.delivery_status}</div></div></div>; })}</div>
        {messages.data && messages.data.total_pages > 1 && <div className="flex items-center justify-end gap-2 border-t p-3"><Button variant="outline" size="sm" disabled={page >= messages.data.total_pages} onClick={() => setPage((value) => value + 1)}>{t("companions.older")}</Button><Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((value) => value - 1)}>{t("companions.newer")}</Button></div>}
      </div>
    </div>}
  </CardContent></Card>;
}

function isProactiveMessage(source: string, lifeEventID: string): boolean {
  if (source === "reply") return false;
  return source === "proactive" || source === "subscription_resume" || Boolean(lifeEventID);
}
