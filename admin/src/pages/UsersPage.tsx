import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
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
import { Select } from "@/components/ui/select";
import { toast } from "@/components/ui/sonner";
import { usersApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import type { AdminUser, AdminUserInput } from "@/api/types";
import { formatDate } from "@/lib/format";

const PAGE_SIZE = 10;

type Filters = { q: string; role: string; status: "" | "active" | "banned" };

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

// --- Create / edit dialog -------------------------------------------------

type FormValues = { email: string; password: string; role: "user" | "admin"; timezone: string };

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
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: "", password: "", role: "user", timezone: "UTC" },
  });

  // Re-seed the form whenever the dialog targets a different user.
  useEffect(() => {
    if (open) {
      reset({
        email: user?.email ?? "",
        password: "",
        role: (user?.role as FormValues["role"]) ?? "user",
        timezone: user?.timezone ?? "UTC",
      });
    }
  }, [open, user, reset]);

  const mutation = useMutation({
    mutationFn: (values: FormValues) => {
      const body: AdminUserInput = {
        email: values.email,
        role: values.role,
        timezone: values.timezone || "UTC",
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
              <Select {...register("role")}>
                <option value="user">{t("users.roleUser")}</option>
                <option value="admin">{t("users.roleAdmin")}</option>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>{t("users.timezone")}</Label>
              <Input placeholder="UTC" {...register("timezone")} />
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
    queryKey: ["admin-users", { page, q, role, status }],
    queryFn: ({ signal }) =>
      usersApi.list(
        { page, page_size: PAGE_SIZE, q: q || undefined, role: role || undefined, status: status || undefined },
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
              <Select value={role} onChange={(e) => setRole(e.target.value)} className="sm:w-36">
                <option value="">{t("users.allRoles")}</option>
                <option value="user">{t("users.roleUser")}</option>
                <option value="admin">{t("users.roleAdmin")}</option>
              </Select>
              <Select value={status} onChange={(e) => setStatus(e.target.value as Filters["status"])} className="sm:w-36">
                <option value="">{t("users.allStatus")}</option>
                <option value="active">{t("users.statusActive")}</option>
                <option value="banned">{t("users.statusBanned")}</option>
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
              {q || role || status ? t("users.noResults") : t("users.empty")}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("users.email")}</TableHead>
                  <TableHead>{t("users.role")}</TableHead>
                  <TableHead>{t("users.status")}</TableHead>
                  <TableHead>{t("users.createdAt")}</TableHead>
                  <TableHead className="text-end">{t("users.actions")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.items.map((u) => (
                  <TableRow key={u.id}>
                    <TableCell className="font-medium">
                      {u.email}
                      {u.role === "admin" && (
                        <Badge variant="outline" className="ms-2 hidden font-normal sm:inline-flex">
                          {t("common.admin")}
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell><RoleBadge role={u.role} /></TableCell>
                    <TableCell><StatusBadge banned={u.banned} /></TableCell>
                    <TableCell className="text-muted-foreground">{formatDate(u.created_at)}</TableCell>
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
