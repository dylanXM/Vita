import { Toaster as Sonner } from "sonner";
import { useTheme } from "@/stores/theme";

export { toast } from "sonner";

/** App-themed toast host. Mounted once near the app root. */
export function Toaster() {
  const theme = useTheme((s) => s.theme);
  return (
    <Sonner
      theme={theme}
      position="top-right"
      richColors
      closeButton
      toastOptions={{
        classNames: {
          toast: "rounded-lg border bg-card text-card-foreground",
        },
      }}
    />
  );
}
