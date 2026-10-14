import type { ReactNode } from "react";
import { MoreHorizontal } from "lucide-react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

export interface ListAction {
  icon?: ReactNode;
  label: string;
  onSelect: () => void;
  disabled?: boolean;
  destructive?: boolean;
}

export function ListActions({ actions }: { actions: ListAction[] }) {
  const { t } = useTranslation();
  return <DropdownMenu><DropdownMenuTrigger asChild><Button type="button" variant="ghost" size="sm"><MoreHorizontal className="size-4" />{t("listActions.more")}</Button></DropdownMenuTrigger><DropdownMenuContent align="end">{actions.map((action) => <DropdownMenuItem key={action.label} disabled={action.disabled} variant={action.destructive ? "destructive" : "default"} onSelect={action.onSelect}>{action.icon}{action.label}</DropdownMenuItem>)}</DropdownMenuContent></DropdownMenu>;
}

export function ListName({ children, onClick }: { children: ReactNode; onClick: () => void }) {
  return <button type="button" onClick={onClick} className="max-w-full truncate text-start font-medium underline-offset-4 hover:text-primary hover:underline focus-visible:rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">{children}</button>;
}

export function ListDetails({ title, fields, onClose, actions = [] }: { title: string; fields: Array<{ label: string; value: ReactNode }>; onClose: () => void; actions?: ListAction[] }) {
  const { t } = useTranslation();
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-2xl"><DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{t("listActions.details")}</DialogDescription></DialogHeader><dl className="space-y-4">{fields.map((field, index) => <div key={`${field.label}-${index}`}><dt className="text-xs text-muted-foreground">{field.label}</dt><dd className="mt-1 whitespace-pre-wrap break-words text-sm">{field.value ?? "—"}</dd></div>)}</dl><DialogFooter><Button variant="outline" onClick={onClose}>{t("listActions.close")}</Button>{actions.length > 0 && <ListActions actions={actions} />}</DialogFooter></DialogContent></Dialog>;
}
