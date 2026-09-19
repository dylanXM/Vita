import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useTranslation } from "react-i18next";
import {
  Ban,
  Eye,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { Pagination } from "@/components/pagination";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/components/ui/sonner";
import { envApi, usersApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import { ENVIRONMENTS, type AdminUser, type AdminUserInput, type Environment } from "@/api/types";
import { formatDate } from "@/lib/format";

const PAGE_SIZE = 10;

type Filters = { q: string; role: string; status: "" | "active" | "banned"; env: string };

/** Role + status badges, reused between the table and the detail page. */
export function RoleBadge({ role }: { role: string }) {
  const { t } = useTranslation();
  return (
    <Badge variant={role === "admin" ? "default" : "muted"}>
      {role === "admin" ? t("users.roleAdmin") : t("users.roleUser")}
    </Badge>
  );
}

export function StatusBadge({ banned }: { banned: boolean }) {
  const { t } = useTranslation();
  return (
    <Badge variant={banned ? "destructive" : "success"}>
      {banned ? t("users.statusBanned") : t("users.statusActive")}
    </Badge>
  );
}

// --- Environment badge (dev | beta | prod) -------------------------------

const ENV_VARIANT: Record<Environment, "muted" | "warning" | "success"> = {
  dev: "muted",
  beta: "warning",
  prod: "success",
};

export function EnvBadge({ env }: { env: string }) {
  const variant = ENV_VARIANT[env as Environment] ?? "muted";
  return <Badge variant={variant}>{env}</Badge>;
}

// --- Create / edit dialog -------------------------------------------------

// --- Create / edit dialog -------------------------------------------------

type FormValues = {
  email: string;
  password: string;
  role: "user" | "admin";
  timezone: string;
  environment: Environment;
};

export function UserFormDialog({
  open,
  onOpenChange,
  user,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** null = create mode; an AdminUser = edit mode. */
  user: AdminUser | null;
  onSaved: () => void;
}) {
  const { t } = useTranslation();
  const editing = user !== null;
  const queryClient = useQueryClient();

  const schema = useMemo(
    () =>
      z.object({
        email: z.string().email(t("login.emailInvalid")),
        password: z.string().optional(),
        role: z.enum(["user", "admin"]),
        timezone: z.string(),
      }),
    [t],
  );

  const {
    control,
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: "", password: "", role: "user", timezone: "UTC", environment: "prod" },
  });

  // New accounts default to the environment the dashboard's API runs in
  // (beta admin → beta accounts, prod admin → prod accounts).
  const serverEnv = useQuery({
    queryKey: ["admin-environment"],
    queryFn: ({ signal }) => envApi.get(signal),
  });

  // Re-seed the form whenever the dialog targets a different user.
  useEffect(() => {
    if (open) {
      const fallback = serverEnv.data?.environment ?? "prod";
      const env = ENVIRONMENTS.includes(user?.environment as Environment)
        ? (user!.environment as Environment)
        : fallback;
      reset({
        email: user?.email ?? "",
        password: "",
        role: (user?.role as FormValues["role"]) ?? "user",
        timezone: user?.timezone ?? "UTC",
        environment: user ? env : fallback,
      });
    }
  }, [open, user, reset, serverEnv.data]);

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      const body: AdminUserInput = {
        email: values.email,
        role: values.role,
        timezone: values.timezone || "UTC",
        environment: values.environment,
      };
      if (values.password) body.password = values.password;
      return editing ? usersApi.update(user!.id, body) : usersApi.create(body);
    },
    onSuccess: () => {
      toast.success(t(editing ? "users.updated" : "users.created"));
      onOpenChange(false);
      void queryClient.invalidateQueries({ queryKey: ["admin-users"] });
      onSaved();
    },
    onError: (err) => toast.error(errorMessage(err, t("common.failedToLoad"))),
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t(editing ? "users.editUser" : "users.createUser")}</DialogTitle>
          <DialogDescription>{t("users.desc")}</DialogDescription>
        </DialogHeader>
        <form
          onSubmit={handleSubmit((v) => mutation.mutate(v))}
          className="space-y-4"
        >
          <div className="space-y-1.5">
            <Label htmlFor="user-email">{t("users.email")}</Label>
            <Input id="user-email" type="email" autoComplete="off" {...register("email")} />
            {errors.email && <p className="text-xs text-destructive">{errors.email.message}</p>}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="user-password">{t("users.password")}</Label>
            <Input
              id="user-password"
              type="password"
              autoComplete="new-password"
              placeholder={editing ? t("users.passwordHint") : undefined}
              {...register("password")}
            />
            {errors.password && (
              <p className="text-xs text-destructive">{errors.password.message}</p>
            )}
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>{t("users.role")}</Label>
              <Controller
                control={control}
                name="role"
                render={({ field }) => (
                  <Select value={field.value} onValueChange={field.onChange}>
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="user">{t("users.roleUser")}</SelectItem>
                      <SelectItem value="admin">{t("users.roleAdmin")}</SelectItem>
                    </SelectContent>
                  </Select>
                )}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("users.timezone")}</Label>
              <Input placeholder="UTC" {...register("timezone")} />
            </div>
            <div className="space-y-1.5">
              <Label>{t("users.environment")}</Label>
              <Controller
                control={control}
                name="environment"
                render={({ field }) => (
                  <Select value={field.value} onValueChange={field.onChange}>
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {ENVIRONMENTS.map((env) => (
                        <SelectItem key={env} value={env}>
                          {t(`users.env${env[0].toUpperCase()}${env.slice(1)}`)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t("users.cancel")}
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isSubmitting ? t(editing ? "users.saving" : "users.creating") : t(editing ? "users.save" : "users.create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// --- List page ------------------------------------------------------------

export function UsersPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState("");
  const [role, setRole] = useState("");
  const [status, setStatus] = useState<Filters["status"]>("");
  const [env, setEnv] = useState("");

  // Debounce the search box so typing doesn't fire a request per keystroke.
  const [q, setQ] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setQ(searchInput.trim()), 300);
    return () => clearTimeout(timer);
  }, [searchInput]);

  // Any filter change restarts from page 1.
  useEffect(() => {
    setPage(1);
  }, [q, role, status]);

  const list = useQuery({
    queryKey: ["admin-users", { page, q, role, status, env }],
    queryFn: ({ signal }) =>
      usersApi.list(
        {
          page, page_size: PAGE_SIZE,
          q: q || undefined,
          role: role || undefined,
          status: status || undefined,
          environment: (env || undefined) as Environment | undefined,
        },
        signal,
      ),
  });

  const [dialogUser, setDialogUser] = useState<AdminUser | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [confirmTarget, setConfirmTarget] = useState<{
    user: AdminUser;
    action: "ban" | "unban" | "delete";
  } | null>(null);

  const runMutation = useMutation<
    AdminUser | { message: string },
    Error,
    { user: AdminUser; action: "ban" | "unban" | "delete" }
  >({
    mutationFn: ({ user, action }) => {
      if (action === "ban") return usersApi.ban(user.id);
      if (action === "unban") return usersApi.unban(user.id);
      return usersApi.remove(user.id);
    },
    onSuccess: (_data, vars) => {
      toast.success(
        t(
          vars.action === "delete"
            ? "users.deleted"
            : vars.action === "ban"
              ? "users.banned"
              : "users.unbanned",
        ),
      );
      setConfirmTarget(null);
      void queryClient.invalidateQueries({ queryKey: ["admin-users"] });
    },
    onError: (err) => {
      setConfirmTarget(null);
      toast.error(errorMessage(err, t("common.failedToLoad")));
    },
  });

  const target = confirmTarget;
  const confirmText = !target
    ? ""
    : target.action === "delete"
      ? "users.deleteTitle"
      : target.action === "ban"
        ? "users.banTitle"
        : "users.unbanTitle";
  const confirmDesc = !target
    ? ""
    : target.action === "delete"
      ? t("users.deleteDesc", { email: target.user.email })
      : target.action === "ban"
        ? t("users.banDesc", { email: target.user.email })
        : t("users.unbanDesc", { email: target.user.email });

  const data = list.data;

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("users.title")}
        description={t("users.desc")}
        actions={
          <>
            <Button
              variant="outline"
              size="sm"
              onClick={() => void list.refetch()}
              disabled={list.isFetching}
            >
              <RefreshCw className={list.isFetching ? "animate-spin" : undefined} />
              {t("common.refresh")}
            </Button>
            <Button size="sm" onClick={() => { setDialogUser(null); setDialogOpen(true); }}>
              <Plus />
              {t("users.createUser")}
            </Button>
          </>
        }
      />

      <Card>
        <CardContent className="space-y-4 p-4">
          {/* Filters */}
          <div className="flex flex-col gap-3 sm:flex-row">
            <div className="relative sm:max-w-xs sm:flex-1">
              <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                placeholder={t("users.searchPlaceholder")}
                className="ps-9"
              />
            </div>
            <div className="flex gap-3">
              <Select
                value={role === "" ? "all" : role}
                onValueChange={(v) => setRole(v === "all" ? "" : v)}
              >
                <SelectTrigger className="sm:w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("users.allRoles")}</SelectItem>
                  <SelectItem value="user">{t("users.roleUser")}</SelectItem>
                  <SelectItem value="admin">{t("users.roleAdmin")}</SelectItem>
                </SelectContent>
              </Select>
              <Select
                value={status === "" ? "all" : status}
                onValueChange={(v) => setStatus(v === "all" ? "" : (v as Filters["status"]))}
              >
                <SelectTrigger className="sm:w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("users.allStatus")}</SelectItem>
                  <SelectItem value="active">{t("users.statusActive")}</SelectItem>
                  <SelectItem value="banned">{t("users.statusBanned")}</SelectItem>
                </SelectContent>
              </Select>
              <Select value={env === "" ? "all" : env} onValueChange={(v) => setEnv(v === "all" ? "" : v)}>
                <SelectTrigger className="sm:w-36">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("users.allEnvironments")}</SelectItem>
                  {ENVIRONMENTS.map((e) => (
                    <SelectItem key={e} value={e}>
                      {t(`users.env${e[0].toUpperCase()}${e.slice(1)}`)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Table */}
          {list.isError ? (
            <p className="py-8 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
          ) : list.isLoading ? (
            <div className="space-y-3 py-2">
              {Array.from({ length: 6 }, (_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          ) : !data || data.items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              {q || role || status || env ? t("users.noResults") : t("users.empty")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("users.email")}</TableHead>
                  <TableHead>{t("users.role")}</TableHead>
                  <TableHead>{t("users.environment")}</TableHead>
                  <TableHead>{t("users.status")}</TableHead>
                  <TableHead className="hidden lg:table-cell">{t("users.createdAt")}</TableHead>
                  <TableHead className="text-end">{t("users.actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.items.map((u) => (
                  <TableRow key={u.id}>
                    <TableCell className="font-medium">
                      <Link
                        to={`/users/${u.id}`}
                        className="hover:text-primary hover:underline"
                      >
                        {u.email}
                      </Link>
                      {u.role === "admin" && (
                        <Badge variant="outline" className="ms-2 hidden font-normal sm:inline-flex">
                          {t("common.admin")}
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell><RoleBadge role={u.role} /></TableCell>
                    <TableCell><EnvBadge env={u.environment} /></TableCell>
                    <TableCell><StatusBadge banned={u.banned} /></TableCell>
                    <TableCell className="hidden text-muted-foreground lg:table-cell">{formatDate(u.created_at)}</TableCell>
                    <TableCell className="text-end">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon" aria-label={t("users.actions")}>
                            <MoreHorizontal className="size-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onClick={() => navigate(`/users/${u.id}`)}>
                            <Eye />
                            {t("users.view")}
                          </DropdownMenuItem>
                          {u.role !== "admin" && (
                            <>
                              <DropdownMenuItem
                                onClick={() => { setDialogUser(u); setDialogOpen(true); }}
                              >
                                <Pencil />
                                {t("users.edit")}
                              </DropdownMenuItem>
                              <DropdownMenuSeparator />
                              <DropdownMenuItem
                                variant={u.banned ? "default" : "destructive"}
                                onClick={() => setConfirmTarget({ user: u, action: u.banned ? "unban" : "ban" })}
                              >
                                {u.banned ? <ShieldCheck /> : <Ban />}
                                {u.banned ? t("users.unban") : t("users.ban")}
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                variant="destructive"
                                onClick={() => setConfirmTarget({ user: u, action: "delete" })}
                              >
                                <Trash2 />
                                {t("users.delete")}
                              </DropdownMenuItem>
                            </>
                          )}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}

          {data && data.total_pages > 1 && (
            <Pagination
              page={data.page}
              totalPages={data.total_pages}
              total={data.total}
              onChange={setPage}
            />
          )}
        </CardContent>
      </Card>

      <UserFormDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        user={dialogUser}
        onSaved={() => {}}
      />

      <AlertDialog
        open={confirmTarget !== null}
        onOpenChange={(open) => { if (!open) setConfirmTarget(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmTarget ? t(confirmText) : ""}
            </AlertDialogTitle>
            <AlertDialogDescription>{confirmDesc}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("users.cancel")}</AlertDialogCancel>
            <AlertDialogAction asChild>
              <Button
                variant="destructive"
                disabled={runMutation.isPending}
                onClick={(e) => {
                  e.preventDefault();
                  if (confirmTarget) runMutation.mutate(confirmTarget);
                }}
              >
                {runMutation.isPending
                  ? t("common.loading")
                  : confirmTarget?.action === "delete"
                    ? t("users.deleteConfirm")
                    : confirmTarget?.action === "ban"
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
