import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import {
  Bot, Brain, CircleDot, CloudUpload, HeartPulse, Moon, Pause, Play,
  Radio, RefreshCw, Send, Trash2, Users,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";

import { lifeEngineApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { LifeEngineCompanion, LifeEngineEvent } from "@/api/types";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatDate } from "@/lib/format";
import { EnvBadge } from "./UsersPage";

export function LifeEnginePage() {
  const { t } = useTranslation();

  const overview = useQuery({ queryKey: ["life-engine-overview"], queryFn: ({ signal }) => lifeEngineApi.overview(signal) });
  const list = useQuery({ queryKey: ["life-engine-companions"], queryFn: ({ signal }) => lifeEngineApi.companions(signal) });

  const refresh = () => { void overview.refetch(); void list.refetch(); };

  const runPlan = useMutation({
    mutationFn: (force: boolean) => lifeEngineApi.triggerPlan(force),
    onMutate: () => toast.info(t("lifeEngine.runningPlan")),
    onSuccess: (r) => {
      toast.success(t("lifeEngine.planDoneStats", { scanned: r.scanned, done: r.newly_completed, failed: r.failed_after }));
      for (const d of r.diagnostics ?? []) {
        const blockers: string[] = [];
        if (!d.active) blockers.push(t("lifeEngine.blockedInactive"));
        if (!d.life_enabled) blockers.push(t("lifeEngine.blockedLifeOff"));
        if (d.admin_takeover) blockers.push(t("lifeEngine.blockedTakeover"));
        if (!d.active_subscription) blockers.push(t("lifeEngine.blockedNoSubscription"));
        const note = d.last_error ? ` — ${d.last_error}` : "";
        if (blockers.length > 0) {
          toast.warning(`${d.name}: ${blockers.join(", ")}${note}`);
        } else if (d.today_status !== "completed") {
          toast.info(`${d.name}: ${d.today_status}${note}`);
        }
      }
      refresh();
    },
    onError: (e) => toast.error(errorMessage(e, t("lifeEngine.runFailed"))),
  });
  const runProactive = useMutation({
    mutationFn: () => lifeEngineApi.triggerProactive(),
    onMutate: () => toast.info(t("lifeEngine.runningProactive")),
    onSuccess: (r) => {
      toast.success(t("lifeEngine.proactiveDoneStats", { due: r.due_before, sent: r.dispatched }));
      refresh();
    },
    onError: (e) => toast.error(errorMessage(e, t("lifeEngine.runFailed"))),
  });

  const [eventsFor, setEventsFor] = useState<LifeEngineCompanion | null>(null);
  const [broadcastFor, setBroadcastFor] = useState<LifeEngineCompanion | null>(null);

  const counters = overview.data?.counters;

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("lifeEngine.title")}
        description={t("lifeEngine.desc")}
        actions={
          <>
            <Button variant="outline" size="sm" onClick={() => runPlan.mutate(false)} disabled={runPlan.isPending}>
              <Play />{t("lifeEngine.runPlan")}
            </Button>
            <Button variant="outline" size="sm" onClick={() => runPlan.mutate(true)} disabled={runPlan.isPending} title={t("lifeEngine.runPlanForceHint")}>
              <RefreshCw />{t("lifeEngine.runPlanForce")}
            </Button>
            <Button variant="outline" size="sm" onClick={() => runProactive.mutate()} disabled={runProactive.isPending}>
              <Radio />{t("lifeEngine.runProactive")}
            </Button>
            <Button variant="outline" size="sm" onClick={refresh} disabled={overview.isFetching || list.isFetching}>
              <RefreshCw className={(overview.isFetching || list.isFetching) ? "animate-spin" : undefined} />
              {t("common.refresh")}
            </Button>
          </>
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label={t("lifeEngine.activeCompanions")} value={counters?.active_companions ?? "—"} icon={Users}
          sub={t("lifeEngine.takeoverSub", { n: counters?.takeover_companions ?? 0 })} loading={overview.isLoading} />
        <StatCard label={t("lifeEngine.eventsToday")}
          value={overview.isLoading ? "—" : `${counters?.events_shared_today}/${counters?.events_today}`}
          icon={Brain} sub={t("lifeEngine.eventsSharedHint")} loading={overview.isLoading} />
        <StatCard label={t("lifeEngine.proactiveToday")} value={counters?.proactive_messages_today ?? "—"} icon={Send}
          sub={t("lifeEngine.outboxHint", { ready: counters?.outbox_ready ?? 0, retrying: counters?.outbox_retrying ?? 0, failed: counters?.outbox_failed ?? 0 })}
          loading={overview.isLoading}
          badge={(counters && counters.outbox_failed > 0) ? <Badge variant="destructive">{counters.outbox_failed}</Badge> : undefined} />
        <StatCard label={t("lifeEngine.runsFailedToday")} value={counters?.runs_failed_today ?? "—"} icon={CircleDot}
          sub={overview.data?.last_run_at ? t("lifeEngine.lastRun", { at: formatDate(overview.data.last_run_at) }) : t("lifeEngine.neverRan")}
          loading={overview.isLoading} />
      </div>

      <Card>
        <CardContent className="p-0">
          {list.isLoading ? (
            <div className="space-y-3 p-4">{Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
          ) : list.isError ? (
            <p className="py-10 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
          ) : !list.data || list.data.items.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">{t("lifeEngine.empty")}</p>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>{t("lifeEngine.companion")}</TableHead>
                <TableHead>{t("lifeEngine.state")}</TableHead>
                <TableHead>{t("lifeEngine.todayEvents")}</TableHead>
                <TableHead>{t("lifeEngine.dueUnshared")}</TableHead>
                <TableHead className="hidden md:table-cell">{t("lifeEngine.mood")}</TableHead>
                <TableHead className="hidden lg:table-cell">{t("lifeEngine.lastRunCol")}</TableHead>
                <TableHead className="text-end">{t("users.actions")}</TableHead>
              </TableRow></TableHeader>
              <TableBody>{list.data.items.map((c) => (
                <CompanionRow
                  key={c.id}
                  companion={c}
                  onOpenEvents={() => setEventsFor(c)}
                  onBroadcast={() => setBroadcastFor(c)}
                  onChanged={() => { void overview.refetch(); void list.refetch(); }}
                />
              ))}</TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {eventsFor && (
        <EventsDialog companion={eventsFor} onClose={() => setEventsFor(null)} onChanged={() => { void overview.refetch(); void list.refetch(); }} />
      )}
      {broadcastFor && (
        <BroadcastDialog companion={broadcastFor} onClose={() => setBroadcastFor(null)} onChanged={() => { void overview.refetch(); void list.refetch(); }} />
      )}
    </div>
  );
}

function CompanionRow({ companion, onOpenEvents, onBroadcast, onChanged }: {
  companion: LifeEngineCompanion;
  onOpenEvents: () => void;
  onBroadcast: () => void;
  onChanged: () => void;
}) {
  const { t } = useTranslation();
  const takeover = useMutation({
    mutationFn: () => companion.admin_takeover ? lifeEngineApi.exitTakeover(companion.id) : lifeEngineApi.enterTakeover(companion.id),
    onSuccess: () => { toast.success(t(companion.admin_takeover ? "lifeEngine.takeoverEnded" : "lifeEngine.takeoverStarted")); onChanged(); },
    onError: (e) => toast.error(errorMessage(e)),
  });
  const resend = useMutation({
    mutationFn: () => lifeEngineApi.resendOutbox(companion.id),
    onSuccess: (r) => toast.success(t("lifeEngine.outboxReset", { n: r.reset })),
    onError: (e) => toast.error(errorMessage(e)),
  });

  return (
    <TableRow>
      <TableCell>
        <div className="flex items-center gap-3">
          <span className={`grid size-9 place-items-center rounded-full ${companion.admin_takeover ? "bg-amber-500/15 text-amber-600" : "bg-muted"}`}>
            {companion.admin_takeover ? <Pause className="size-4" /> : <Bot className="size-4" />}
          </span>
          <div>
            <div className="font-medium">{companion.name}</div>
            <div className="text-xs text-muted-foreground">{companion.user_email} · {companion.city || "—"}</div>
          </div>
        </div>
      </TableCell>
      <TableCell>
        <div className="flex flex-wrap gap-1">
          <EnvBadge env={companion.environment} />
          {companion.admin_takeover
            ? <Badge variant="warning">{t("lifeEngine.inTakeover")}</Badge>
            : <Badge variant="success">{t("lifeEngine.automatic")}</Badge>}
          {!companion.life_enabled && <Badge variant="muted">{t("lifeEngine.lifeOff")}</Badge>}
          {!companion.proactive_enabled && <Badge variant="muted">{t("lifeEngine.proactiveOff")}</Badge>}
        </div>
      </TableCell>
      <TableCell>
        <span className="tabular-nums">{companion.today_shared}/{companion.today_events}</span>
        {companion.last_error && (
                    <div className="mt-1 max-w-60 space-y-0.5" title={companion.last_model_output || companion.last_error}>
                      <div className="text-xs text-destructive line-clamp-2">{companion.last_error}</div>
                      {companion.last_model_output && <div className="text-[10px] text-muted-foreground line-clamp-2 font-mono">{companion.last_model_output}</div>}
                    </div>)
                  }
      </TableCell>
      <TableCell className="tabular-nums">{companion.due_unshared}</TableCell>
      <TableCell className="hidden md:table-cell">
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <HeartPulse className="size-3.5" />
          <span>{t("lifeEngine.moodValue", { mood: companion.mood, energy: companion.energy })}</span>
          <span>·</span>
          <span>{t("lifeEngine.intimacyValue", { n: companion.intimacy })}</span>
        </div>
      </TableCell>
      <TableCell className="hidden text-xs text-muted-foreground lg:table-cell">
        {companion.last_run_at ? formatDate(companion.last_run_at) : "—"}
        {companion.last_run_status && <Badge variant={companion.last_run_status === "succeeded" ? "outline" : "destructive"} className="ml-2">{companion.last_run_status}</Badge>}
      </TableCell>
      <TableCell className="text-end">
        <div className="flex justify-end gap-1">
          <Button size="sm" variant="ghost" onClick={onOpenEvents}><Moon />{t("lifeEngine.events")}</Button>
          <Button size="sm" variant="ghost" onClick={onBroadcast}><Send />{t("lifeEngine.broadcast")}</Button>
          <Button size="sm" variant="ghost" onClick={() => resend.mutate()} disabled={resend.isPending}><CloudUpload />{t("lifeEngine.resend")}</Button>
          <Button size="sm" variant={companion.admin_takeover ? "outline" : "ghost"} onClick={() => takeover.mutate()} disabled={takeover.isPending}>
            {companion.admin_takeover ? <Play /> : <Pause />}
            {companion.admin_takeover ? t("lifeEngine.resume") : t("lifeEngine.takeover")}
          </Button>
        </div>
      </TableCell>
    </TableRow>
  );
}

function EventsDialog({ companion, onClose, onChanged }: {
  companion: LifeEngineCompanion;
  onClose: () => void;
  onChanged: () => void;
}) {
  const { t } = useTranslation();
  const events = useQuery({ queryKey: ["life-engine-events", companion.id], queryFn: ({ signal }) => lifeEngineApi.events(companion.id, signal) });
  const [draft, setDraft] = useState({ title: "", description: "", location: "", importance: 50, shareability: true });

  const create = useMutation({
    mutationFn: () => lifeEngineApi.createEvent(companion.id, {
      title: draft.title,
      description: draft.description,
      location: draft.location,
      importance: draft.importance,
      shareability: draft.shareability,
      start_time: new Date().toISOString(),
      end_time: new Date(Date.now() + 3600_000).toISOString(),
    }),
    onSuccess: () => { toast.success(t("lifeEngine.eventAdded")); setDraft({ title: "", description: "", location: "", importance: 50, shareability: true }); void events.refetch(); onChanged(); },
    onError: (e) => toast.error(errorMessage(e)),
  });
  const remove = useMutation({
    mutationFn: (id: string) => lifeEngineApi.deleteEvent(id),
    onSuccess: () => { toast.success(t("lifeEngine.eventDeleted")); void events.refetch(); onChanged(); },
    onError: (e) => toast.error(errorMessage(e)),
  });

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{t("lifeEngine.eventsTitle", { name: companion.name })}</DialogTitle>
          <DialogDescription>{t("lifeEngine.eventsDesc")}</DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          {events.isLoading ? <Skeleton className="h-20 w-full" /> :
            events.data?.items.map((e: LifeEngineEvent) => (
              <div key={e.id} className="flex items-start justify-between gap-3 rounded-lg border p-3 text-sm">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{e.title}</span>
                    {e.shared_at ? <Badge variant="success">{t("lifeEngine.shared")}</Badge>
                      : e.shareability ? <Badge variant="outline">{t("lifeEngine.shareable")}</Badge> : null}
                    <Badge variant="muted">{e.generation_source}</Badge>
                  </div>
                  {e.description && <p className="mt-1 text-xs text-muted-foreground">{e.description}</p>}
                  <p className="mt-1 text-xs text-muted-foreground">
                    {formatDate(e.start_time)} · {e.emotion || "—"} · {t("lifeEngine.importance", { n: e.importance })}
                  </p>
                </div>
                {!e.shared_at && (
                  <Button size="sm" variant="ghost" onClick={() => remove.mutate(e.id)}><Trash2 /></Button>
                )}
              </div>
            ))}
        </div>

        <div className="mt-2 space-y-2 border-t pt-4">
          <Label>{t("lifeEngine.addEventTitle")}</Label>
          <Input value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} placeholder={t("lifeEngine.titlePlaceholder")} />
          <Input value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} placeholder={t("lifeEngine.descriptionPlaceholder")} />
          <div className="grid grid-cols-2 gap-2">
            <Input value={draft.location} onChange={(e) => setDraft({ ...draft, location: e.target.value })} placeholder={t("lifeEngine.locationPlaceholder")} />
            <Input type="number" value={draft.importance} onChange={(e) => setDraft({ ...draft, importance: Number(e.target.value) })} />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={draft.shareability} onChange={(e) => setDraft({ ...draft, shareability: e.target.checked })} />
            {t("lifeEngine.shareableHint")}
          </label>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{t("common.refresh") /* reuse close */}</Button>
          <Button onClick={() => create.mutate()} disabled={!draft.title.trim() || create.isPending}>
            {t("lifeEngine.addEvent")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function BroadcastDialog({ companion, onClose, onChanged }: {
  companion: LifeEngineCompanion;
  onClose: () => void;
  onChanged: () => void;
}) {
  const { t } = useTranslation();
  const [content, setContent] = useState("");
  const [conversationID, setConversationID] = useState("");
  const send = useMutation({
    mutationFn: () => lifeEngineApi.broadcast(companion.id, { content, conversation_id: conversationID || undefined }),
    onSuccess: () => { toast.success(t("lifeEngine.broadcastSent")); onChanged(); onClose(); },
    onError: (e) => toast.error(errorMessage(e)),
  });

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("lifeEngine.broadcastTitle", { name: companion.name })}</DialogTitle>
          <DialogDescription>{t("lifeEngine.broadcastDesc", { email: companion.user_email })}</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <Label>{t("lifeEngine.message")}</Label>
          <textarea
            className="min-h-28 w-full rounded-md border bg-background p-3 text-sm"
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={t("lifeEngine.messagePlaceholder")}
          />
          <div>
            <Label>{t("lifeEngine.conversationIdOptional")}</Label>
            <Input value={conversationID} onChange={(e) => setConversationID(e.target.value)} placeholder={t("lifeEngine.conversationIdPlaceholder")} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{t("lifeEngine.cancel")}</Button>
          <Button onClick={() => send.mutate()} disabled={!content.trim() || send.isPending}><Send />{t("lifeEngine.send")}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
