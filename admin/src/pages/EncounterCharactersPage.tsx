import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { http, errorMessage, api } from "@/api/client";
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

type Character = { id: string; name: string; gender: string; personality: string; persona: string; description: string; cover_url: string; avatar_url: string; enabled: boolean; sort_order: number; image_urls?:string[] };
type VideoSettings = {coins:number; model_id:string; duration:number; enabled:boolean};
const empty = (): Character => ({ id: "", name: "", gender: "female", personality: "", persona: "", description: "", cover_url: "", avatar_url: "", enabled: true, sort_order: 0, image_urls:[] });
export function EncounterCharactersPage() {
 const { t } = useTranslation(); const cache = useQueryClient();
 const [form, setForm] = useState<Character | null>(null);
 const [detail, setDetail] = useState<Character | null>(null);
 const [uploading, setUploading] = useState(false);
 const [video,setVideo]=useState<VideoSettings|null>(null);
 const settings=useQuery({queryKey:["encounter-video"],queryFn:()=>http.get<VideoSettings>("/admin/encounter-video")});
 const models=useQuery({queryKey:["encounter-models"],queryFn:()=>http.get<{models:{id:string;model_name:string;display_name:string;enabled:boolean}[]}>("/admin/agent/config")});
 const saveVideo=useMutation({mutationFn:(value:VideoSettings)=>http.put("/admin/encounter-video",value),onSuccess:()=>{setVideo(null);void cache.invalidateQueries({queryKey:["encounter-video"]});},onError:err=>toast.error(errorMessage(err))});
 const list = useQuery({ queryKey: ["encounter-characters"], queryFn: () => http.get<{items: Character[]}>("/admin/encounter-characters") });
 const save = useMutation({ mutationFn: (value: Character) => {const body={...value,image_urls:[value.cover_url,...(value.image_urls??[]).slice(1)].map(url=>url.trim()).filter(Boolean)};return value.id ? http.put(`/admin/encounter-characters/${value.id}`,body) : http.post("/admin/encounter-characters",body);},
  onSuccess: () => { setForm(null); void cache.invalidateQueries({queryKey:["encounter-characters"]}); }, onError: (err) => toast.error(errorMessage(err)) });
 const edit = (value: Character) => { setDetail(null); setForm({...value}); };
 const fields = ["name", "personality", "description", "persona"] as const;
 return <div className="space-y-6"><PageHeader title={t("encounters.title")} description={t("encounters.description")} actions={<><Button variant="outline" disabled={!settings.data} onClick={()=>{if(settings.data)setVideo({...settings.data});}}>{t("encounters.videoSettings")}</Button><Button onClick={() => setForm(empty())}>{t("encounters.create")}</Button></>} />
 {list.isError && <Button variant="outline" onClick={() => void list.refetch()}>{t("common.refresh")}</Button>}
 <Table><TableHeader><TableRow>{["name", "gender", "personality", "enabled", "actions"].map(k=><TableHead key={k}>{t(`encounters.${k}`)}</TableHead>)}</TableRow></TableHeader><TableBody>
 {(list.data?.items??[]).map(value=><TableRow key={value.id}><TableCell><ListName onClick={()=>setDetail(value)}>{value.name}</ListName></TableCell><TableCell>{t(`encounters.${value.gender}`)}</TableCell><TableCell className="max-w-48 truncate">{value.personality}</TableCell><TableCell><Switch checked={value.enabled} disabled={save.isPending} onCheckedChange={enabled=>save.mutate({...value,enabled})} aria-label={t("encounters.enabled")} /></TableCell><TableCell><ListActions actions={[{label:t("listActions.details"),onSelect:()=>setDetail(value)},{label:t("common.edit"),onSelect:()=>edit(value)}]} /></TableCell></TableRow>)}
 </TableBody></Table>
 {detail && <ListDetails title={detail.name} onClose={()=>setDetail(null)} fields={[...fields.map(k=>({label:t(`encounters.${k}`),value:detail[k]})),{label:t("encounters.gender"),value:t(`encounters.${detail.gender}`)},{label:t("encounters.cover"),value:detail.cover_url},{label:t("encounters.imagesHint"),value:(detail.image_urls??[detail.cover_url]).join("\n")},{label:t("encounters.avatar"),value:detail.avatar_url},{label:t("encounters.sort"),value:detail.sort_order}]} actions={[{label:t("common.edit"),onSelect:()=>edit(detail)}]} />}
 <Dialog open={form!==null} onOpenChange={open=>{if(!open && !save.isPending && !uploading)setForm(null);}}><DialogContent className="max-h-[85vh] overflow-y-auto"><DialogHeader><DialogTitle>{t("encounters.title")}</DialogTitle><DialogDescription>{t("encounters.description")}</DialogDescription></DialogHeader>
 {form && <form className="space-y-4" onSubmit={event=>{event.preventDefault();save.mutate(form);}}>{fields.map(k=><div key={k}><Label>{t(`encounters.${k}`)}</Label><Input value={form[k]} maxLength={k==="name"?80:k==="persona"?4000:k==="personality"?200:500} required={k==="name"} onChange={event=>setForm({...form,[k]:event.target.value})}/></div>)}
 <Label>{t("encounters.gender")}</Label><Select value={form.gender} onValueChange={gender=>setForm({...form,gender})}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent>{["male","female","other"].map(k=><SelectItem key={k} value={k}>{t(`encounters.${k}`)}</SelectItem>)}</SelectContent></Select>
 <Label>{t("encounters.cover")}</Label><AdminImageInput allowExistingValue={form.cover_url.startsWith("/v1/encounter-art/")?form.cover_url:undefined} value={form.cover_url} onChange={cover_url=>setForm(current=>current?{...current,cover_url,image_urls:[cover_url,...(current.image_urls??[]).slice(1)]}:null)} onUploadingChange={setUploading}/>
 {form.cover_url.startsWith("/v1/encounter-art/") && <img src={new URL(api.defaults.baseURL||"/v1",window.location.origin).origin+form.cover_url} alt={form.name} className="h-44 rounded-lg object-cover"/>}
 <p className="text-xs text-muted-foreground">{t("encounters.imagesHint")}</p>{[1,2].map(index=><div key={index} className="space-y-2"><Label>{t("encounters.extraImage")}</Label><AdminImageInput allowExistingValue={form.image_urls?.[index]?.startsWith("/v1/encounter-art/")?(form.image_urls?.[index]??""):undefined} value={form.image_urls?.[index]??""} onChange={url=>setForm(current=>{if(!current)return null;const images=[current.cover_url,current.image_urls?.[1]??"",current.image_urls?.[2]??""];images[index]=url;return {...current,image_urls:images};})} onUploadingChange={setUploading}/></div>)}
 <Label>{t("encounters.avatar")}</Label><AdminImageInput allowExistingValue={form.avatar_url.startsWith("/v1/encounter-art/")?form.avatar_url:undefined} value={form.avatar_url} onChange={avatar_url=>setForm(current=>current?{...current,avatar_url}:null)} onUploadingChange={setUploading}/>
 <Label>{t("encounters.sort")}</Label><Input type="number" value={form.sort_order} onChange={event=>setForm({...form,sort_order:Number(event.target.value)})}/>
 <div className="flex items-center gap-3"><Switch checked={form.enabled} onCheckedChange={enabled=>setForm({...form,enabled})}/><Label>{t("encounters.enabled")}</Label></div>
 <Button type="submit" disabled={save.isPending||uploading||!form.cover_url}>{t("common.save")}</Button></form>}
 </DialogContent></Dialog>
 <Dialog open={video!==null} onOpenChange={open=>{if(!open&&!saveVideo.isPending)setVideo(null);}}><DialogContent><DialogHeader><DialogTitle>{t("encounters.videoSettings")}</DialogTitle><DialogDescription>{t("encounters.videoHint")}</DialogDescription></DialogHeader>
 {video && <form className="space-y-4" onSubmit={event=>{event.preventDefault();saveVideo.mutate(video);}}><Label>{t("encounters.coins")}</Label><Input type="number" min={1} max={100000} required value={video.coins} onChange={event=>setVideo({...video,coins:Number(event.target.value)})}/>
 <Label>{t("encounters.model")}</Label><Select value={video.model_id} onValueChange={model_id=>setVideo({...video,model_id})}><SelectTrigger><SelectValue placeholder={t("encounters.model")}/></SelectTrigger><SelectContent>{(models.data?.models??[]).filter(m=>m.enabled&&m.model_name==="kling/v2-1-master-image-to-video").map(m=><SelectItem key={m.id} value={m.id}>{m.display_name||m.model_name}</SelectItem>)}</SelectContent></Select>
 <Label>{t("encounters.duration")}</Label><Select value={String(video.duration)} onValueChange={duration=>setVideo({...video,duration:Number(duration)})}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent><SelectItem value="5">5s</SelectItem><SelectItem value="10">10s</SelectItem></SelectContent></Select>
 <div className="flex items-center gap-3"><Switch checked={video.enabled} onCheckedChange={enabled=>setVideo({...video,enabled})}/><Label>{t("encounters.enabled")}</Label></div><Button type="submit" disabled={saveVideo.isPending}>{t("common.save")}</Button></form>}
 </DialogContent></Dialog></div>;
}
