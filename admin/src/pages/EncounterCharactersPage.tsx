import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { http, errorMessage } from "@/api/client";
import { PageHeader } from "@/components/page-header";
import { ListActions, ListDetails, ListName } from "@/components/list-actions";
import { AdminImageInput } from "@/components/admin-image-input";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select";
import { Table, TableHeader, TableBody, TableHead, TableRow, TableCell } from "@/components/ui/table";

type Character = { id: string; name: string; gender: string; personality: string; persona: string; description: string; cover_url: string; avatar_url: string; enabled: boolean; sort_order: number };
const empty = (): Character => ({ id: "", name: "", gender: "female", personality: "", persona: "", description: "", cover_url: "", avatar_url: "", enabled: true, sort_order: 0 });
export function EncounterCharactersPage() {
 const { t } = useTranslation(); const cache = useQueryClient();
 const [form, setForm] = useState<Character | null>(null);
 const [detail, setDetail] = useState<Character | null>(null);
 const [uploading, setUploading] = useState(false);
 const list = useQuery({ queryKey: ["encounter-characters"], queryFn: () => http.get<{items: Character[]}>("/admin/encounter-characters") });
 const save = useMutation({ mutationFn: (value: Character) => value.id ? http.put(`/admin/encounter-characters/${value.id}`, value) : http.post("/admin/encounter-characters", value),
  onSuccess: () => { setForm(null); void cache.invalidateQueries({queryKey:["encounter-characters"]}); }, onError: (err) => toast.error(errorMessage(err)) });
 const edit = (value: Character) => { setDetail(null); setForm({...value}); };
 const fields = ["name", "personality", "description", "persona"] as const;
 return <div className="space-y-6"><PageHeader title={t("encounters.title")} description={t("encounters.description")} actions={<Button onClick={() => setForm(empty())}>{t("encounters.create")}</Button>} />
 {list.isError && <Button variant="outline" onClick={() => void list.refetch()}>{t("common.refresh")}</Button>}
 <Table><TableHeader><TableRow>{["name", "gender", "personality", "enabled", "actions"].map(k=><TableHead key={k}>{t(`encounters.${k}`)}</TableHead>)}</TableRow></TableHeader><TableBody>
 {(list.data?.items??[]).map(value=><TableRow key={value.id}><TableCell><ListName onClick={()=>setDetail(value)}>{value.name}</ListName></TableCell><TableCell>{t(`encounters.${value.gender}`)}</TableCell><TableCell className="max-w-48 truncate">{value.personality}</TableCell><TableCell><Switch checked={value.enabled} disabled={save.isPending} onCheckedChange={enabled=>save.mutate({...value,enabled})} aria-label={t("encounters.enabled")} /></TableCell><TableCell><ListActions actions={[{label:t("listActions.details"),onSelect:()=>setDetail(value)},{label:t("common.edit"),onSelect:()=>edit(value)}]} /></TableCell></TableRow>)}
 </TableBody></Table>
 {detail && <ListDetails title={detail.name} onClose={()=>setDetail(null)} fields={[...fields.map(k=>({label:t(`encounters.${k}`),value:detail[k]})),{label:t("encounters.gender"),value:t(`encounters.${detail.gender}`)},{label:t("encounters.cover"),value:detail.cover_url},{label:t("encounters.avatar"),value:detail.avatar_url},{label:t("encounters.sort"),value:detail.sort_order}]} actions={[{label:t("common.edit"),onSelect:()=>edit(detail)}]} />}
 <Dialog open={form!==null} onOpenChange={open=>{if(!open && !save.isPending && !uploading)setForm(null);}}><DialogContent className="max-h-[85vh] overflow-y-auto"><DialogHeader><DialogTitle>{t("encounters.title")}</DialogTitle><DialogDescription>{t("encounters.description")}</DialogDescription></DialogHeader>
 {form && <form className="space-y-4" onSubmit={event=>{event.preventDefault();save.mutate(form);}}>{fields.map(k=><div key={k}><Label>{t(`encounters.${k}`)}</Label><Input value={form[k]} maxLength={k==="name"?80:k==="persona"?4000:k==="personality"?200:500} required={k==="name"} onChange={event=>setForm({...form,[k]:event.target.value})}/></div>)}
 <Label>{t("encounters.gender")}</Label><Select value={form.gender} onValueChange={gender=>setForm({...form,gender})}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent>{["male","female","other"].map(k=><SelectItem key={k} value={k}>{t(`encounters.${k}`)}</SelectItem>)}</SelectContent></Select>
 <Label>{t("encounters.cover")}</Label><AdminImageInput value={form.cover_url} onChange={cover_url=>setForm(current=>current?{...current,cover_url}:null)} onUploadingChange={setUploading}/>
 <Label>{t("encounters.avatar")}</Label><AdminImageInput value={form.avatar_url} onChange={avatar_url=>setForm(current=>current?{...current,avatar_url}:null)} onUploadingChange={setUploading}/>
 <Label>{t("encounters.sort")}</Label><Input type="number" value={form.sort_order} onChange={event=>setForm({...form,sort_order:Number(event.target.value)})}/>
 <div className="flex items-center gap-3"><Switch checked={form.enabled} onCheckedChange={enabled=>setForm({...form,enabled})}/><Label>{t("encounters.enabled")}</Label></div>
 <Button type="submit" disabled={save.isPending||uploading||!form.cover_url}>{t("common.save")}</Button></form>}
 </DialogContent></Dialog></div>;
}
