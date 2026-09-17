import { create } from "zustand";
import { authApi } from "@/api/admin";
import { getToken, setToken, errorMessage } from "@/api/client";
import type { Profile } from "@/api/types";

interface AuthState {
  user: Profile | null;
  /** "loading" until the initial /me check resolves. */
  status: "loading" | "authed" | "anon";
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  /** Rehydrate the session from a stored token at startup. */
  bootstrap: () => Promise<void>;
}

/** Raised when valid credentials belong to a non-admin account. */
export class NotAdminError extends Error {
  constructor() {
    super("This account is not an administrator.");
    this.name = "NotAdminError";
  }
}

export const useAuth = create<AuthState>((set) => ({
  user: null,
  status: "loading",

  login: async (email, password) => {
    const res = await authApi.login(email, password);
    setToken(res.token);
    try {
      const me = await authApi.me();
      if (me.role !== "admin") {
        setToken(null);
        throw new NotAdminError();
      }
      set({ user: me, status: "authed" });
    } catch (err) {
      setToken(null);
      set({ user: null, status: "anon" });
      if (err instanceof NotAdminError) throw err;
      throw new Error(errorMessage(err, "Sign-in failed"));
    }
  },

  logout: () => {
    setToken(null);
    set({ user: null, status: "anon" });
  },

  bootstrap: async () => {
    if (!getToken()) {
      set({ status: "anon" });
      return;
    }
    try {
      const me = await authApi.me();
      if (me.role === "admin") set({ user: me, status: "authed" });
      else {
        setToken(null);
        set({ user: null, status: "anon" });
      }
    } catch {
      setToken(null);
      set({ user: null, status: "anon" });
    }
  },
}));
