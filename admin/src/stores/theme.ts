import { create } from "zustand";

type Theme = "dark" | "light";
const THEME_KEY = "vita_admin_theme";

function apply(theme: Theme) {
  const root = document.documentElement;
  root.classList.toggle("dark", theme === "dark");
  root.style.colorScheme = theme;
}

function initial(): Theme {
  const saved = localStorage.getItem(THEME_KEY);
  return saved === "light" || saved === "dark" ? saved : "dark";
}

interface ThemeState {
  theme: Theme;
  setTheme: (t: Theme) => void;
  toggle: () => void;
}

export const useTheme = create<ThemeState>((set, get) => ({
  theme: initial(),
  setTheme: (theme) => {
    localStorage.setItem(THEME_KEY, theme);
    apply(theme);
    set({ theme });
  },
  toggle: () => get().setTheme(get().theme === "dark" ? "light" : "dark"),
}));

/** Call once at startup to apply the persisted theme before first paint. */
export function initTheme() {
  apply(useTheme.getState().theme);
}
