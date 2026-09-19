import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import {
  ArrowLeft,
  Ban,
  Brain,
  Heart,
  MessagesSquare,
  MessageSquare,
  Pencil,
  RefreshCw,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
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
import { usersApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { AdminUser } from "@/api/types";
import { formatDate } from "@/lib/format";
import { RoleBadge, StatusBadge, UserFormDialog } from "./UsersPage";

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
