import { useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Bot, Eye, RefreshCw, Search } from "lucide-react";
import { useTranslation } from "react-i18next";

import { companionsApi } from "@/api/admin";
import { ENVIRONMENTS, type Environment } from "@/api/types";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatDate } from "@/lib/format";
import { EnvBadge } from "./UsersPage";

const PAGE_SIZE = 20;

export function CompanionsPage() {
  const { t } = useTranslation();
  const [params] = useSearchParams();
  const userID = params.get("user_id") ?? "";
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState("");
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [environment, setEnvironment] = useState("");

  useEffect(() => {
    const timer = setTimeout(() => setQ(searchInput.trim()), 300);
    return () => clearTimeout(timer);
  }, [searchInput]);
  useEffect(() => setPage(1), [q, status, environment, userID]);

  const list = useQuery({
    queryKey: ["managed-companions", { page, q, status, environment, userID }],
    queryFn: ({ signal }) => companionsApi.list({
      page,
      page_size: PAGE_SIZE,
      q: q || undefined,
      user_id: userID || undefined,
      status: (status || undefined) as "active" | "inactive" | undefined,
      environment: (environment || undefined) as Environment | undefined,
    }, signal),
  });

  const data = list.data;
  return (
    <div className="space-y-6">
      <PageHeader
        title={t("companions.title")}
        description={t("companions.desc")}
        actions={
          <Button variant="outline" size="sm" onClick={() => void list.refetch()} disabled={list.isFetching}>
            <RefreshCw className={list.isFetching ? "animate-spin" : undefined} />
            {t("common.refresh")}
          </Button>
        }
      />
      <Card>
        <CardContent className="space-y-4 p-4">
          <div className="flex flex-col gap-3 lg:flex-row">
            <div className="relative min-w-64 flex-1">
              <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={searchInput} onChange={(e) => setSearchInput(e.target.value)} placeholder={t("companions.searchPlaceholder")} className="ps-9" />
            </div>
            <Select value={status || "all"} onValueChange={(value) => setStatus(value === "all" ? "" : value)}>
              <SelectTrigger className="lg:w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("companions.allStatus")}</SelectItem>
                <SelectItem value="active">{t("companions.active")}</SelectItem>
                <SelectItem value="inactive">{t("companions.inactive")}</SelectItem>
              </SelectContent>
            </Select>
            <Select value={environment || "all"} onValueChange={(value) => setEnvironment(value === "all" ? "" : value)}>
              <SelectTrigger className="lg:w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("users.allEnvironments")}</SelectItem>
                {ENVIRONMENTS.map((env) => <SelectItem key={env} value={env}>{t(`users.env${env[0].toUpperCase()}${env.slice(1)}`)}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {list.isError ? (
            <p className="py-10 text-center text-sm text-destructive">{t("common.failedToLoad")}</p>
          ) : list.isLoading ? (
            <div className="space-y-3">{Array.from({ length: 7 }, (_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
          ) : !data || data.items.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">{t("companions.empty")}</p>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>{t("companions.companion")}</TableHead>
                <TableHead>{t("companions.owner")}</TableHead>
                <TableHead>{t("users.environment")}</TableHead>
                <TableHead>{t("companions.status")}</TableHead>
                <TableHead>{t("companions.chats")}</TableHead>
                <TableHead className="hidden xl:table-cell">{t("users.createdAt")}</TableHead>
                <TableHead className="text-end">{t("users.actions")}</TableHead>
              </TableRow></TableHeader>
              <TableBody>{data.items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      {item.portrait_url && !item.portrait_url.startsWith("asset://")
                        ? <img src={item.portrait_url} alt="" className="size-9 rounded-full object-cover" />
                        : <span className="grid size-9 place-items-center rounded-full bg-muted"><Bot className="size-4" /></span>}
                      <div><Link to={`/companions/${item.id}`} className="font-medium hover:text-primary hover:underline">{item.name}</Link><div className="text-xs text-muted-foreground">{[item.city, item.occupation].filter(Boolean).join(" · ") || "—"}</div></div>
                    </div>
                  </TableCell>
                  <TableCell><Link to={`/users/${item.user_id}`} className="hover:text-primary hover:underline">{item.user_email}</Link></TableCell>
                  <TableCell><EnvBadge env={item.environment} /></TableCell>
                  <TableCell><div className="flex flex-wrap gap-1"><Badge variant={item.active ? "success" : "muted"}>{t(item.active ? "companions.active" : "companions.inactive")}</Badge>{item.proactive_enabled && <Badge variant="outline">{t("companions.proactive")}</Badge>}</div></TableCell>
                  <TableCell>{item.conversations} / {item.messages}</TableCell>
                  <TableCell className="hidden text-muted-foreground xl:table-cell">{formatDate(item.created_at)}</TableCell>
                  <TableCell className="text-end"><Button variant="ghost" size="sm" asChild><Link to={`/companions/${item.id}`}><Eye />{t("users.view")}</Link></Button></TableCell>
                </TableRow>
              ))}</TableBody>
            </Table>
          )}

          {data && data.total_pages > 1 && <div className="flex items-center justify-between gap-3 border-t pt-4 text-sm text-muted-foreground">
            <span>{t("companions.total", { total: data.total })}</span>
            <div className="flex gap-2"><Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((v) => v - 1)}>{t("users.previous")}</Button><span className="self-center">{page} / {data.total_pages}</span><Button variant="outline" size="sm" disabled={page >= data.total_pages} onClick={() => setPage((v) => v + 1)}>{t("users.next")}</Button></div>
          </div>}
        </CardContent>
      </Card>
    </div>
  );
}
