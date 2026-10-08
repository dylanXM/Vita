import { useRef, useState } from "react";
import { Upload } from "lucide-react";
import { useTranslation } from "react-i18next";

import { adminImagesApi } from "@/api/admin";
import { errorMessage } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/components/ui/sonner";

export function isAdminImageURL(value: string) {
  if (value.startsWith("asset://assets/")) return true;
  try {
    const url = new URL(value);
    return (url.protocol === "http:" || url.protocol === "https:") && Boolean(url.hostname) && !url.username && !url.password;
  } catch {
    return false;
  }
}

export function AdminImageInput({ value, onChange, onUploadingChange, allowExistingValue }: {
  value: string;
  onChange: (url: string) => void;
  onUploadingChange?: (uploading: boolean) => void;
  allowExistingValue?: string;
}) {
  const { t } = useTranslation();
  const fileInput = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  async function upload(file: File) {
    if (!["image/png", "image/jpeg", "image/webp", "image/gif"].includes(file.type) || file.size > 10 * 1024 * 1024) {
      toast.error(t("adminImages.invalidFile"));
      return;
    }
    setUploading(true);
    onUploadingChange?.(true);
    try {
      const result = await adminImagesApi.upload(file);
      onChange(result.url);
    } catch (error) {
      toast.error(errorMessage(error, t("adminImages.uploadFailed")));
    } finally {
      setUploading(false);
      onUploadingChange?.(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }

  return <div className="space-y-2">
    <div className="flex gap-2">
      <Input value={value} onChange={(event) => onChange(event.target.value)} placeholder="https://…" />
      <input ref={fileInput} type="file" accept="image/png,image/jpeg,image/webp,image/gif" className="hidden"
        onChange={(event) => { const file = event.target.files?.[0]; if (file) void upload(file); }} />
      <Button type="button" variant="outline" disabled={uploading} onClick={() => fileInput.current?.click()}>
        <Upload />{uploading ? t("adminImages.uploading") : t("adminImages.upload")}
      </Button>
    </div>
    {isAdminImageURL(value.trim()) && !value.startsWith("asset://") && <img src={value.trim()} alt="" className="max-h-32 max-w-full rounded-md border object-contain" />}
    {value.startsWith("asset://") && <p className="text-xs text-muted-foreground">{t("adminImages.bundledAsset")}</p>}
    {value.trim() && value !== allowExistingValue && !isAdminImageURL(value.trim()) && <p className="text-xs text-destructive">{t("adminImages.invalidUrl")}</p>}
  </div>;
}
