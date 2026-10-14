import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListName } from "@/components/list-actions";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { agentApi } from "@/api/admin";
import type { AIModel, ModelRates } from "@/api/types";
import { errorMessage } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Pagination } from "@/components/pagination";
import { toast } from "@/components/ui/sonner";
import { formatDate } from "@/lib/format";

const rateKeys = ["input", "output", "cache_read", "cache_write", "call"] as const;
const money = (value: number | null | undefined) => value == null ? "—" : `$${value.toFixed(6)}`;

export function ModelUsagePage() {
  const { id } = useParams();
  const { t } = useTranslation();
  const config = useQuery({ queryKey: ["agent-config", "prod"], queryFn: ({ signal }) => agentApi.config("prod", signal) });
  const model = config.data?.models.find((item) => item.id === id);
  if (config.isPending) return <p>{t("common.loading")}</p>;
  if (config.isError) return <div className="space-y-3"><p className="text-destructive">{errorMessage(config.error)}</p><Button onClick={() => void config.refetch()}>{t("common.refresh")}</Button></div>;
  if (!model) return <div className="space-y-3"><p>{t("common.failedToLoad")}</p><Button asChild variant="outline"><Link to="/model-services">{t("modelServices.title")}</Link></Button></div>;
  return <ModelUsageContent key={model.id} model={model} />;
}

function ModelUsageContent({ model }: { model: AIModel }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [legacyPage, setLegacyPage] = useState(1);
  const [legacySelected, setLegacySelected] = useState<number | null>(null);
  const [draft, setDraft] = useState<ModelRates | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const usage = useQuery({ queryKey: ["model-usage", model.id, page], queryFn: ({ signal }) => agentApi.modelUsage(model.id, page, signal) });
  const rates = draft ?? usage.data?.rates;
  const save = useMutation({
    mutationFn: () => {
      if (!rates || rateKeys.some((key) => rates[key] != null && (!Number.isFinite(rates[key]) || rates[key]! < 0))) throw new Error(t("modelUsage.invalidRate"));
      return agentApi.saveModelRates(model.id, rates);
    },
    onSuccess: () => { setDraft(null); void queryClient.invalidateQueries({ queryKey: ["model-usage", model.id] }); toast.success(t("modelServices.saved")); },
    onError: (err) => toast.error(errorMessage(err)),
  });
  const call = usage.data?.items.find((item) => item.id === selected);
  const legacyCall = legacySelected == null ? null : usage.data?.legacy_runs[legacySelected];
  return <div className="space-y-5">
      <PageHeader title={`${model.display_name} · ${t("modelUsage.details")}`} description={t("modelUsage.scope")} actions={<Button asChild variant="outline"><Link to="/model-services">{t("modelServices.title")}</Link></Button>} />
        {usage.isPending && <p>{t("common.loading")}</p>}
        {usage.isError && <div className="text-destructive">{errorMessage(usage.error)} <Button onClick={() => void usage.refetch()}>{t("common.refresh")}</Button></div>}
        {usage.data && rates && <>
          <div className="grid grid-cols-2 gap-4 rounded border p-4">
            <p>{t("modelUsage.today")}<strong className="block">{money(usage.data.totals.today_usd)}</strong></p>
            <p>{t("modelUsage.total")}<strong className="block">{money(usage.data.totals.total_usd)}</strong></p>
            <p className="col-span-2 text-xs text-muted-foreground">{t("modelUsage.unpricedCount", { count: usage.data.totals.unpriced_calls })} · {t("modelUsage.currency")}</p>
          </div>
          <div className="space-y-3 rounded border p-4">
            <h3 className="font-semibold">{t("modelUsage.rates")}</h3>
            <p className="text-xs text-muted-foreground">{t("modelUsage.rateHelp")}</p>
            <Label className="flex items-center gap-3">{t("modelUsage.unit")}
              <Select value={rates.unit} onValueChange={(unit) => setDraft({ ...rates, unit: unit as ModelRates["unit"] })}>
                <SelectTrigger className="w-64"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="tokens">{t("modelUsage.tokensUnit")}</SelectItem><SelectItem value="call">{t("modelUsage.callUnit")}</SelectItem></SelectContent>
              </Select>
            </Label>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              {rateKeys.filter((key) => rates.unit === "call" ? key === "call" : key !== "call").map((key) => <Label key={key} className="space-y-2">{t(`modelUsage.${key}`)}
                <Input type="number" min="0" max="1000000000" step="any" value={rates[key] ?? ""} onChange={(e) => setDraft({ ...rates, [key]: e.target.value === "" ? null : Number(e.target.value) })} />
              </Label>)}
            </div>
            <Button onClick={() => save.mutate()} disabled={!draft || save.isPending}>{t("common.save")}</Button>
          </div>
          <h3 className="font-semibold">{t("modelUsage.history")}</h3>
          <div className="rounded-md border">
            <Table>
              <TableHeader><TableRow>
                <TableHead>{t("modelUsage.time")}</TableHead><TableHead>{t("modelUsage.kind")}</TableHead><TableHead>{t("modelUsage.status")}</TableHead><TableHead className="text-end">{t("modelCallTokens")}</TableHead><TableHead className="text-end">{t("modelUsage.cost")}</TableHead><TableHead className="text-end">{t("users.actions")}</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {!usage.data.items.length && <TableRow><TableCell colSpan={6} className="h-16 text-center text-muted-foreground">{t("modelUsage.empty")}</TableCell></TableRow>}
                {usage.data.items.map((item) => <TableRow key={item.id} className="h-14">
                  <TableCell className="whitespace-nowrap">{formatDate(item.started_at)}</TableCell><TableCell><ListName onClick={() => setSelected(item.id)}>{item.kind}</ListName></TableCell><TableCell>{item.status === "succeeded" ? t("modelServices.ok") : t("modelServices.failed")}</TableCell>
                  <TableCell className="text-end whitespace-nowrap tabular-nums" title={item.usage_known ? t("modelCallTokenBreakdown", { input: item.input_tokens.toLocaleString(), output: item.output_tokens.toLocaleString(), read: item.cache_read_tokens.toLocaleString(), write: item.cache_write_tokens.toLocaleString() }) : t("modelUsage.unknown")}>
                    {item.usage_known ? (item.input_tokens + item.output_tokens + item.cache_read_tokens + item.cache_write_tokens).toLocaleString() : <span className="text-muted-foreground">{t("modelCallTokenUnknown")}</span>}
                  </TableCell>
                  <TableCell className="text-end whitespace-nowrap">{item.estimated_cost_usd == null ? t("modelUsage.unpriced") : money(item.estimated_cost_usd)}</TableCell><TableCell className="text-end"><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setSelected(item.id) }]} /></TableCell>
                </TableRow>)}
              </TableBody>
            </Table>
          </div>
          <Pagination page={page} totalPages={Math.max(1, Math.ceil(usage.data.totals.calls / 10))} total={usage.data.totals.calls} onChange={(next) => { setSelected(null); setPage(next); }} />
          {!!usage.data.legacy_runs.length && <>
            <h3 className="font-semibold">{t("modelUsage.legacy")}</h3>
            <div className="rounded-md border"><Table>
              <TableHeader><TableRow><TableHead>{t("modelUsage.time")}</TableHead><TableHead>{t("modelUsage.kind")}</TableHead><TableHead>{t("modelUsage.status")}</TableHead><TableHead className="text-end">{t("modelCallTokens")}</TableHead><TableHead className="text-end">{t("users.actions")}</TableHead></TableRow></TableHeader>
              <TableBody>{usage.data.legacy_runs.slice((legacyPage - 1) * 10, legacyPage * 10).map((run, index) => <TableRow key={`${run.finished_at}-${(legacyPage - 1) * 10 + index}`} className="h-14">
                <TableCell className="whitespace-nowrap">{formatDate(run.finished_at)}</TableCell><TableCell><ListName onClick={() => setLegacySelected((legacyPage - 1) * 10 + index)}>{run.kind}</ListName></TableCell><TableCell>{run.status === "succeeded" ? t("modelServices.ok") : t("modelServices.failed")}</TableCell><TableCell className="text-end text-muted-foreground" title={t("modelUsage.legacy")}>{t("modelCallTokenUnknown")}</TableCell><TableCell className="text-end"><ListActions actions={[{ label: t("listActions.details"), onSelect: () => setLegacySelected((legacyPage - 1) * 10 + index) }]} /></TableCell>
              </TableRow>)}</TableBody>
            </Table></div>
            <Pagination page={legacyPage} totalPages={Math.ceil(usage.data.legacy_runs.length / 10)} total={usage.data.legacy_runs.length} onChange={(next) => { setLegacySelected(null); setLegacyPage(next); }} />
          </>}
        </>}
          {call && <Dialog open onOpenChange={(open) => { if (!open) setSelected(null); }}>
            <DialogContent className="max-h-[85vh] overflow-auto sm:max-w-3xl"><DialogHeader><DialogTitle>{t("modelUsage.details")}</DialogTitle><DialogDescription>{formatDate(call.started_at)} · {call.kind}</DialogDescription></DialogHeader>
            <div className="space-y-2">
            <p>{t("modelUsage.usage")}: {call.usage_known ? `${call.input_tokens} / ${call.output_tokens} / ${call.cache_read_tokens} / ${call.cache_write_tokens}` : t("modelUsage.unknown")}</p>
            <p>{t("modelUsage.ratesSnapshot")}: {JSON.stringify(call.rates)}</p>
            <p>{t("modelUsage.total")}: {money(call.estimated_cost_usd)}</p>
            {call.error && <pre className="max-h-40 overflow-auto whitespace-pre-wrap break-words text-xs text-destructive">{call.error}</pre>}
            <h4>{t("modelServices.testRequest")}</h4><pre className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-3 text-xs">{call.request}</pre>
            <h4>{t("modelServices.testResponse")}</h4><pre className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-3 text-xs">{call.response}</pre>
          </div></DialogContent></Dialog>}
      {legacyCall && <Dialog open onOpenChange={(open) => { if (!open) setLegacySelected(null); }}>
        <DialogContent className="max-h-[85vh] overflow-auto sm:max-w-3xl"><DialogHeader><DialogTitle>{t("modelUsage.details")}</DialogTitle><DialogDescription>{formatDate(legacyCall.finished_at)} · {legacyCall.kind}</DialogDescription></DialogHeader>
          {legacyCall.error && <pre className="whitespace-pre-wrap break-words text-xs text-destructive">{legacyCall.error}</pre>}
          <h4>{t("modelServices.testResponse")}</h4><pre className="whitespace-pre-wrap break-words rounded bg-muted p-3 text-xs">{legacyCall.response}</pre>
        </DialogContent>
      </Dialog>}
    </div>;
}
