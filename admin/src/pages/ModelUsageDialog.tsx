import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { agentApi } from "@/api/admin";
import type { AIModel, ModelRates } from "@/api/types";
import { errorMessage } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/components/ui/sonner";
import { formatDate } from "@/lib/format";

const rateKeys = ["input", "output", "cache_read", "cache_write", "call"] as const;
const money = (value: number | null | undefined) => value == null ? "—" : `$${value.toFixed(6)}`;

export function ModelUsageDialog({ model, onClose }: { model: AIModel; onClose: () => void }) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
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
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
    <DialogContent className="flex h-[85vh] max-h-[900px] w-[95vw] max-w-5xl sm:max-w-5xl flex-col overflow-hidden">
      <DialogHeader><DialogTitle>{model.display_name} · {t("modelUsage.details")}</DialogTitle><DialogDescription>{t("modelUsage.scope")}</DialogDescription></DialogHeader>
      <div className="min-h-0 flex-1 space-y-5 overflow-auto">
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
              <select className="rounded border bg-background p-2" value={rates.unit} onChange={(e) => setDraft({ ...rates, unit: e.target.value as ModelRates["unit"] })}>
                <option value="tokens">{t("modelUsage.tokensUnit")}</option><option value="call">{t("modelUsage.callUnit")}</option>
              </select>
            </Label>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              {rateKeys.filter((key) => rates.unit === "call" ? key === "call" : key !== "call").map((key) => <Label key={key} className="space-y-2">{t(`modelUsage.${key}`)}
                <Input type="number" min="0" max="1000000000" step="any" value={rates[key] ?? ""} onChange={(e) => setDraft({ ...rates, [key]: e.target.value === "" ? null : Number(e.target.value) })} />
              </Label>)}
            </div>
            <Button onClick={() => save.mutate()} disabled={!draft || save.isPending}>{t("common.save")}</Button>
          </div>
          {call && <div className="space-y-2 rounded border p-4">
            <p>{t("modelUsage.usage")}: {call.usage_known ? `${call.input_tokens} / ${call.output_tokens} / ${call.cache_read_tokens} / ${call.cache_write_tokens}` : t("modelUsage.unknown")}</p>
            <p>{t("modelUsage.ratesSnapshot")}: {JSON.stringify(call.rates)}</p>
            <p>{t("modelUsage.total")}: {money(call.estimated_cost_usd)}</p>
            {call.error && <pre className="max-h-40 overflow-auto whitespace-pre-wrap break-words text-xs text-destructive">{call.error}</pre>}
            <h4>{t("modelServices.testRequest")}</h4><pre className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-3 text-xs">{call.request}</pre>
            <h4>{t("modelServices.testResponse")}</h4><pre className="max-h-64 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-3 text-xs">{call.response}</pre>
          </div>}
          <h3 className="font-semibold">{t("modelUsage.history")}</h3>
          {!usage.data.items.length && <p className="text-sm text-muted-foreground">{t("modelUsage.empty")}</p>}
          <div className="space-y-2">{usage.data.items.map((item) => <button key={item.id} className="grid h-16 w-full grid-cols-[1fr_1fr_1fr] items-center gap-2 rounded border px-3 text-left text-sm" onClick={() => setSelected(item.id)}>
            <span className="truncate">{formatDate(item.started_at)} · {item.kind}</span><span className="truncate">{item.status === "succeeded" ? t("modelServices.ok") : t("modelServices.failed")}</span><span className="text-right">{item.estimated_cost_usd == null ? t("modelUsage.unpriced") : money(item.estimated_cost_usd)}</span>
          </button>)}</div>
          <div className="flex items-center justify-between"><Button variant="outline" disabled={page === 1} onClick={() => { setSelected(null); setPage(page - 1); }}>{t("modelUsage.previous")}</Button><span>{page}</span><Button variant="outline" disabled={!usage.data.has_more || usage.isFetching} onClick={() => { setSelected(null); setPage(page + 1); }}>{t("modelUsage.next")}</Button></div>
          {!!usage.data.legacy_runs.length && <><h3>{t("modelUsage.legacy")}</h3>{usage.data.legacy_runs.map((run, index) => <details key={index} className="rounded border p-3 text-sm"><summary>{formatDate(run.finished_at)} · {run.kind} · {run.status}</summary><pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words text-xs">{run.error || run.response}</pre></details>)}</>}
        </>}
      </div>
    </DialogContent>
  </Dialog>;
}
