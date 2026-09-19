import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import {
  Users,
  UserPlus,
  Heart,
  MessagesSquare,
  MessageSquare,
  Brain,
  CalendarClock,
  RefreshCw,
} from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { envApi, statsApi, healthApi } from "@/api/admin";
import { EnvBadge } from "@/pages/UsersPage";
import { formatDate, formatNumber, relativeTime } from "@/lib/format";

export function DashboardPage() {
  const { t } = useTranslation();

  const stats = useQuery({
    queryKey: ["admin-stats"],
    queryFn: ({ signal }) => statsApi.get(signal),
    refetchInterval: 60_000,
  });

  const health = useQuery({
    queryKey: ["api-health"],
    queryFn: ({ signal }) => healthApi.get(signal),
    refetchInterval: 60_000,
  });

  const environment = useQuery({
    queryKey: ["admin-environment"],
    queryFn: ({ signal }) => envApi.get(signal),
  });

  const data = stats.data;
  const loading = stats.isLoading;

  return (
    <div className="space-y-6">
      <PageHeader
        title={t("dashboard.title")}
        description={t("dashboard.desc")}
        actions={
          <>
            <Badge variant="muted" className="hidden font-normal sm:inline-flex">
              {t("dashboard.generatedAt")}: {data ? relativeTime(data.generated_at) : "—"}
            </Badge>
            <Button
              variant="outline"
              size="sm"
              onClick={() => void stats.refetch()}
              disabled={stats.isFetching}
            >
              <RefreshCw className={stats.isFetching ? "animate-spin" : undefined} />
              {t("common.refresh")}
            </Button>
          </>
        }
      />

      {stats.isError && (
        <Card className="border-destructive/40 bg-destructive/5">
          <CardContent className="p-5 text-sm text-destructive">
            {t("common.failedToLoad")}
          </CardContent>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <StatCard
          label={t("dashboard.users")}
          value={formatNumber(data?.total_users)}
          sub={t("dashboard.usersSub", { admins: formatNumber(data?.admin_users) })}
          icon={Users}
          loading={loading}
        />
        <StatCard
          label={t("dashboard.newUsers7d")}
          value={formatNumber(data?.new_users_7d)}
          sub={t("dashboard.newUsers7dSub")}
          icon={UserPlus}
          loading={loading}
          accent
        />
        <StatCard
          label={t("dashboard.companions")}
          value={formatNumber(data?.total_companions)}
          sub={t("dashboard.companionsSub", { n: formatNumber(data?.new_companions_7d) })}
          icon={Heart}
          loading={loading}
        />
        <StatCard
          label={t("dashboard.conversations")}
          value={formatNumber(data?.total_conversations)}
          sub={t("dashboard.conversationsSub", { n: formatNumber(data?.new_conversations_7d) })}
          icon={MessagesSquare}
          loading={loading}
        />
        <StatCard
          label={t("dashboard.messages")}
          value={formatNumber(data?.total_messages)}
          sub={t("dashboard.messagesSub", { n: formatNumber(data?.new_messages_7d) })}
          icon={MessageSquare}
          loading={loading}
        />
        <StatCard
          label={t("dashboard.memories")}
          value={formatNumber(data?.total_memories)}
          sub={t("dashboard.memoriesSub")}
          icon={Brain}
          loading={loading}
        />
        <StatCard
          label={t("dashboard.lifeEvents")}
          value={formatNumber(data?.total_life_events)}
          sub={t("dashboard.lifeEventsSub", { n: formatNumber(data?.today_life_events) })}
          icon={CalendarClock}
          loading={loading}
        />
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{t("dashboard.systemInfo")}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">{t("dashboard.apiVersion")}</p>
              {health.isLoading ? (
                <Skeleton className="h-5 w-20" />
              ) : (
                <p className="font-medium tabular-nums">{health.data?.version ?? "—"}</p>
              )}
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">{t("dashboard.environment")}</p>
              {environment.isLoading ? (
                <Skeleton className="h-5 w-20" />
              ) : (
                environment.data ? (
                  <EnvBadge env={environment.data.environment} />
                ) : (
                  <Badge variant="muted">—</Badge>
                )
              )}
            </div>
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">{t("dashboard.generatedAt")}</p>
              {loading ? (
                <Skeleton className="h-5 w-40" />
              ) : (
                <p className="font-medium">{formatDate(data?.generated_at)}</p>
              )}
            </div>
          </div>
          <p className="text-xs text-muted-foreground">{t("dashboard.dataNote")}</p>
        </CardContent>
      </Card>
    </div>
  );
}
