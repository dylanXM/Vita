import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import {
  ArrowLeft,
  Ban,
  Brain,
  Coins,
  CreditCard,
  Heart,
  MessagesSquare,
  MessageSquare,
  Pencil,
  RefreshCw,
  ShieldCheck,
  Trash2,
  Activity,
} from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { toast } from "@/components/ui/sonner";
import { subscriptionPlansApi, usersApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { AdminGrantOperation, AdminUser, AdminUserDetail, UserBehaviorCategory, UserBehaviorEvent } from "@/api/types";
import { formatDate } from "@/lib/format";
import { EnvBadge, RoleBadge, StatusBadge, UserFormDialog } from "./UsersPage";

export function UserDetailPage() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const { t } = useTranslation();
  const queryClient = useQueryClient();

  const detail = useQuery({
    queryKey: ["admin-user", id],
    queryFn: ({ signal }) => usersApi.get(id, signal),
    retry: false,
  });

  const [editOpen, setEditOpen] = useState(false);
  const [confirmAction, setConfirmAction] = useState<"ban" | "unban" | "delete" | null>(null);
  const [behaviorCategory, setBehaviorCategory] = useState<"all" | UserBehaviorCategory>("all");
  const [behaviorOffset, setBehaviorOffset] = useState(0);
  const behavior = useQuery({
    queryKey: ["admin-user-behavior", id, behaviorCategory, behaviorOffset],
    queryFn: ({ signal }) => usersApi.timeline(id, {
      category: behaviorCategory === "all" ? undefined : behaviorCategory,
      limit: 30,
      offset: behaviorOffset,
    }, signal),
    enabled: Boolean(id),
  });
  useEffect(() => setBehaviorOffset(0), [behaviorCategory]);

  const mutation = useMutation<AdminUser | { message: string }, Error, "ban" | "unban" | "delete">({
    mutationFn: (action) => {
      if (action === "ban") return usersApi.ban(id);
      if (action === "unban") return usersApi.unban(id);
      return usersApi.remove(id);
    },
    onSuccess: (_data, action) => {
      if (action === "delete") {
        toast.success(t("users.deleted"));
        navigate("/users");
        return;
      }
      toast.success(t(action === "ban" ? "users.banned" : "users.unbanned"));
      setConfirmAction(null);
      void queryClient.invalidateQueries({ queryKey: ["admin-user", id] });
      void queryClient.invalidateQueries({ queryKey: ["admin-users"] });
    },
    onError: (err) => {
      setConfirmAction(null);
      toast.error(errorMessage(err, t("common.failedToLoad")));
    },
  });

  if (detail.isLoading) {
    return (
      <div className="space-y-6">
        <PageHeader title={<Skeleton className="h-7 w-56" />} />
        <div className="space-y-3">
          <Skeleton className="h-32 w-full" />
          <Skeleton className="h-28 w-full" />
        </div>
      </div>
    );
  }

  const u = detail.data;
  if (detail.isError || !u) {
    return (
      <div className="space-y-6">
        <PageHeader
          title={t("users.notFound")}
          actions={
            <Button variant="outline" asChild>
              <Link to="/users">
                <ArrowLeft />
                {t("users.back")}
              </Link>
            </Button>
          }
        />
      </div>
    );
  }

  const isAdmin = u.role === "admin";
  const confirmDesc =
    confirmAction === "delete"
      ? t("users.deleteDesc", { email: u.email })
      : confirmAction === "ban"
        ? t("users.banDesc", { email: u.email })
        : t("users.unbanDesc", { email: u.email });

  return (
    <div className="space-y-6">
      <PageHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            {u.email}
            <RoleBadge role={u.role} />
            <EnvBadge env={u.environment} />
          </span>
        }
        description={t("users.detailDesc")}
        actions={
          <>
            <Button variant="outline" asChild>
              <Link to="/users">
                <ArrowLeft />
                {t("users.back")}
              </Link>
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => void detail.refetch()}
              disabled={detail.isFetching}
            >
              <RefreshCw className={detail.isFetching ? "animate-spin" : undefined} />
              {t("common.refresh")}
            </Button>
            <Button size="sm" onClick={() => setEditOpen(true)}>
              <Pencil />
              {t("users.edit")}
            </Button>
            {!isAdmin && (
              <>
                <Button
                  variant={u.banned ? "secondary" : "destructive"}
                  size="sm"
                  onClick={() => setConfirmAction(u.banned ? "unban" : "ban")}
                >
                  {u.banned ? <ShieldCheck /> : <Ban />}
                  {u.banned ? t("users.unban") : t("users.ban")}
                </Button>
                <Button
                  variant="destructive"
                  size="sm"
                  onClick={() => setConfirmAction("delete")}
                >
                  <Trash2 />
                  {t("users.delete")}
                </Button>
              </>
            )}
          </>
        }
      />

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-3">
        {/* Account */}
        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle>{t("users.overview")}</CardTitle>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-1 gap-x-6 gap-y-4 sm:grid-cols-2">
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.email")}</dt>
                <dd className="font-medium">{u.email}</dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.role")}</dt>
                <dd><RoleBadge role={u.role} /></dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.status")}</dt>
                <dd><StatusBadge banned={u.banned} /></dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.environment")}</dt>
                <dd><EnvBadge env={u.environment} /></dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.timezone")}</dt>
                <dd className="font-medium">{u.timezone || "UTC"}</dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.createdAt")}</dt>
                <dd className="font-medium">{formatDate(u.created_at)}</dd>
              </div>
              <div className="space-y-1">
                <dt className="text-xs text-muted-foreground">{t("users.updatedAt")}</dt>
                <dd className="font-medium">{formatDate(u.updated_at)}</dd>
              </div>
              <div className="space-y-1 sm:col-span-2">
                <dt className="text-xs text-muted-foreground">ID</dt>
                <dd className="truncate font-mono text-xs text-muted-foreground" title={u.id}>
                  {u.id}
                </dd>
              </div>
            </dl>
          </CardContent>
        </Card>

        {/* Usage */}
        <div className="grid grid-cols-2 gap-4">
          <StatCard label={t("users.companions")} value={u.companions} icon={Heart} />
          <StatCard label={t("users.conversations")} value={u.conversations} icon={MessagesSquare} />
          <StatCard label={t("users.messages")} value={u.messages} icon={MessageSquare} />
          <StatCard label={t("users.memories")} value={u.memories} icon={Brain} />
        </div>
      </div>

      <UserGrants user={u} />

      <UserBehaviorTimeline
        items={behavior.data?.items ?? []}
        total={behavior.data?.total ?? 0}
        offset={behaviorOffset}
        loading={behavior.isLoading}
        error={behavior.isError}
        category={behaviorCategory}
        onCategoryChange={setBehaviorCategory}
        onOffsetChange={setBehaviorOffset}
      />

      <Card>
        <CardHeader><CardTitle>{t("companions.title")}</CardTitle></CardHeader>
        <CardContent>
          <Button variant="outline" asChild>
            <Link to={`/companions?user_id=${encodeURIComponent(u.id)}`}>
              <Heart />
              {t("companions.viewUserCompanions")}
            </Link>
          </Button>
        </CardContent>
      </Card>

      <UserFormDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        user={u}
        onSaved={() => void detail.refetch()}
      />

      <AlertDialog
        open={confirmAction !== null}
        onOpenChange={(open) => { if (!open) setConfirmAction(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmAction === "delete"
                ? t("users.deleteTitle")
                : confirmAction === "ban"
                  ? t("users.banTitle")
                  : t("users.unbanTitle")}
            </AlertDialogTitle>
            <AlertDialogDescription>{confirmDesc}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("users.cancel")}</AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                variant="destructive"
                disabled={mutation.isPending}
                onClick={(e) => {
                  e.preventDefault();
                  if (confirmAction) mutation.mutate(confirmAction);
                }}
              >
                {mutation.isPending
                  ? t("common.loading")
                  : confirmAction === "delete"
                    ? t("users.deleteConfirm")
                    : confirmAction === "ban"
                      ? t("users.confirmBan")
                      : t("users.confirmUnban")}
              </Button>
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

const behaviorCategories: Array<"all" | UserBehaviorCategory> = [
  "all", "navigation", "auth", "onboarding", "chat", "companion", "billing", "life", "profile", "updates", "system", "general",
];

function UserBehaviorTimeline({ items, total, offset, loading, error, category, onCategoryChange, onOffsetChange }: {
  items: UserBehaviorEvent[];
  total: number;
  offset: number;
  loading: boolean;
  error: boolean;
  category: "all" | UserBehaviorCategory;
  onCategoryChange: (value: "all" | UserBehaviorCategory) => void;
  onOffsetChange: (value: number) => void;
}) {
  const { t } = useTranslation();
  const end = Math.min(total, offset + items.length);
  return <Card>
    <CardHeader className="gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div className="space-y-1"><CardTitle className="flex items-center gap-2"><Activity />{t("users.behaviorTimeline")}</CardTitle><p className="text-sm text-muted-foreground">{t("users.behaviorTimelineDesc", { total })}</p></div>
      <select className="h-9 rounded-md border bg-background px-3 text-sm" value={category} onChange={(e) => onCategoryChange(e.target.value as "all" | UserBehaviorCategory)}>{behaviorCategories.map((value) => <option key={value} value={value}>{t(`users.behaviorCategories.${value}`)}</option>)}</select>
    </CardHeader>
    <CardContent className="p-0">
      {loading ? <div className="p-5"><Skeleton className="h-40 w-full" /></div> : error ? <p className="p-5 text-sm text-destructive">{t("common.failedToLoad")}</p> : items.length === 0 ? <p className="p-5 text-sm text-muted-foreground">{t("users.behaviorEmpty")}</p> : <Table><TableHeader><TableRow><TableHead>{t("users.behaviorTime")}</TableHead><TableHead>{t("users.behaviorEvent")}</TableHead><TableHead>{t("users.behaviorDetails")}</TableHead><TableHead>{t("users.behaviorContext")}</TableHead></TableRow></TableHeader><TableBody>{items.map((item) => <TableRow key={item.id} className="align-top"><TableCell className="whitespace-nowrap text-xs">{formatDate(item.occurred_at)}</TableCell><TableCell><div className="font-medium">{humanizeEvent(item.event_name)}</div><div className="mt-1 text-xs text-muted-foreground">{t(`users.behaviorCategories.${item.category}`)} · {item.source}</div></TableCell><TableCell className="max-w-xl"><pre className="whitespace-pre-wrap break-words font-sans text-xs text-muted-foreground">{formatProperties(item.properties)}</pre></TableCell><TableCell className="whitespace-nowrap text-xs text-muted-foreground">{item.platform || "—"}{item.app_version ? ` · v${item.app_version}` : ""}{item.session_id ? <><br /><span className="font-mono" title={item.session_id}>{item.session_id.slice(0, 16)}…</span></> : null}</TableCell></TableRow>)}</TableBody></Table>}
      <div className="flex items-center justify-between border-t px-5 py-3 text-xs text-muted-foreground"><span>{t("users.behaviorRange", { from: total === 0 ? 0 : offset + 1, to: end, total })}</span><div className="flex gap-2"><Button size="sm" variant="outline" disabled={offset === 0} onClick={() => onOffsetChange(Math.max(0, offset - 30))}>{t("users.previous")}</Button><Button size="sm" variant="outline" disabled={end >= total} onClick={() => onOffsetChange(offset + 30)}>{t("users.next")}</Button></div></div>
    </CardContent>
  </Card>;
}

function humanizeEvent(value: string): string {
  return value.split("_").filter(Boolean).map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(" ");
}

function formatProperties(properties: Record<string, unknown>): string {
  const entries = Object.entries(properties ?? {}).filter(([, value]) => value !== "" && value != null);
  if (entries.length === 0) return "—";
  return entries.map(([key, value]) => `${key}: ${typeof value === "object" ? JSON.stringify(value) : String(value)}`).join("\n");
}

function defaultGrantEnd(): string {
  const date = new Date();
  date.setMonth(date.getMonth() + 1);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function UserGrants({ user }: { user: AdminUserDetail }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [coins, setCoins] = useState(100);
  const [coinNote, setCoinNote] = useState("");
  const [planID, setPlanID] = useState("");
  const [endsAt, setEndsAt] = useState(defaultGrantEnd);
  const [subscriptionNote, setSubscriptionNote] = useState("");

  const plans = useQuery({
    queryKey: ["subscription-plans", user.environment, "grant"],
    queryFn: ({ signal }) => subscriptionPlansApi.list({ environment: user.environment }, signal),
  });
  const operations = useQuery({
    queryKey: ["admin-grant-operations", user.id],
    queryFn: ({ signal }) => usersApi.grantOperations(user.id, signal),
  });
  const refreshOperations = () => {
    void queryClient.invalidateQueries({ queryKey: ["admin-grant-operations", user.id] });
    void queryClient.invalidateQueries({ queryKey: ["credit-ledger"] });
  };
  const grantCoins = useMutation({
    mutationFn: () => usersApi.grantCoins(user.id, { coins, note: coinNote.trim() }),
    onSuccess: (result) => {
      toast.success(t("users.grantCoinsSuccess", { coins: result.coins }));
      setCoinNote("");
      refreshOperations();
    },
    onError: (err) => toast.error(errorMessage(err, t("users.grantFailed"))),
  });
  const grantSubscription = useMutation({
    mutationFn: () => usersApi.grantSubscription(user.id, {
      plan_id: planID,
      ends_at: new Date(endsAt).toISOString(),
      note: subscriptionNote.trim(),
    }),
    onSuccess: (result) => {
      toast.success(t("users.grantSubscriptionSuccess", { plan: result.plan_name, coins: result.coins }));
      setSubscriptionNote("");
      refreshOperations();
    },
    onError: (err) => toast.error(errorMessage(err, t("users.grantFailed"))),
  });
  const enabledPlans = (plans.data?.items ?? []).filter((plan) => plan.enabled);
  const minimumEnd = new Date(Date.now() - new Date().getTimezoneOffset() * 60_000).toISOString().slice(0, 16);

  return (
    <div className="space-y-6">
      <div className="grid gap-6 xl:grid-cols-2">
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Coins />{t("users.grantCoins")}</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <label className="space-y-2 text-sm"><span>{t("users.coinAmount")}</span><Input type="number" min={1} max={10_000_000} value={coins} onChange={(event) => setCoins(Number(event.target.value))} /></label>
            <label className="space-y-2 text-sm"><span>{t("users.grantNote")}</span><Input maxLength={500} value={coinNote} onChange={(event) => setCoinNote(event.target.value)} /></label>
            <Button disabled={coins < 1 || grantCoins.isPending} onClick={() => grantCoins.mutate()}><Coins />{t("users.confirmGrant")}</Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><CreditCard />{t("users.grantSubscription")}</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            <label className="space-y-2 text-sm"><span>{t("users.subscriptionPlan")}</span><select className="h-9 w-full rounded-md border bg-background px-3 text-sm" value={planID} onChange={(event) => setPlanID(event.target.value)}><option value="">{t("users.selectPlan")}</option>{enabledPlans.map((plan) => <option key={plan.id} value={plan.id}>{plan.name} · {plan.platform} · {plan.coins.toLocaleString()} {t("users.coins")}</option>)}</select></label>
            <label className="space-y-2 text-sm"><span>{t("users.subscriptionEndsAt")}</span><Input type="datetime-local" min={minimumEnd} value={endsAt} onChange={(event) => setEndsAt(event.target.value)} /></label>
            <label className="space-y-2 text-sm"><span>{t("users.grantNote")}</span><Input maxLength={500} value={subscriptionNote} onChange={(event) => setSubscriptionNote(event.target.value)} /></label>
            <Button disabled={!planID || !endsAt || grantSubscription.isPending} onClick={() => grantSubscription.mutate()}><CreditCard />{t("users.confirmGrant")}</Button>
          </CardContent>
        </Card>
      </div>
      <Card>
        <CardHeader><CardTitle>{t("users.grantOperations")}</CardTitle></CardHeader>
        <CardContent>
          {operations.isLoading ? <Skeleton className="h-28 w-full" /> : operations.data?.items.length ? <GrantOperationsTable rows={operations.data.items} /> : <p className="text-sm text-muted-foreground">{t("users.noGrantOperations")}</p>}
        </CardContent>
      </Card>
    </div>
  );
}

function GrantOperationsTable({ rows }: { rows: AdminGrantOperation[] }) {
  const { t } = useTranslation();
  return <Table><TableHeader><TableRow><TableHead>{t("users.operationType")}</TableHead><TableHead>{t("users.grantDetails")}</TableHead><TableHead>{t("users.subscriptionEndsAt")}</TableHead><TableHead>{t("users.operator")}</TableHead><TableHead>{t("users.grantNote")}</TableHead><TableHead>{t("users.operationTime")}</TableHead></TableRow></TableHeader><TableBody>{rows.map((row) => <TableRow key={row.id}><TableCell>{t(row.operation_type === "coins" ? "users.grantCoins" : "users.grantSubscription")}</TableCell><TableCell>{row.operation_type === "subscription" ? `${row.plan_name} · ${row.platform} · ${row.coins.toLocaleString()} ${t("users.coins")}` : `${row.coins.toLocaleString()} ${t("users.coins")}`}</TableCell><TableCell>{formatDate(row.expires_at)}</TableCell><TableCell>{row.operator_email}</TableCell><TableCell className="max-w-64 truncate" title={row.note}>{row.note || "—"}</TableCell><TableCell>{formatDate(row.created_at)}</TableCell></TableRow>)}</TableBody></Table>;
}
