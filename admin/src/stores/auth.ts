import axios from "axios";
import { create } from "zustand";
import { authApi } from "@/api/admin";
import { getToken, setToken, setSession, errorMessage } from "@/api/client";
import type { Profile } from "@/api/types";

interface AuthState {
  user: Profile | null;
  /** "loading" until the initial /me check resolves. */
  status: "loading" | "authed" | "anon" | "error";
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

let authEpoch = 0;

export const useAuth = create<AuthState>((set) => ({
  user: null,
  status: "loading",

  login: async (email, password) => {
    const epoch = ++authEpoch;
    const res = await authApi.login(email, password);
    if (epoch !== authEpoch) return;
    setSession(res);
    try {
      const me = await authApi.me();
      if (epoch !== authEpoch) return;
      if (me.role !== "admin") {
        setToken(null);
        throw new NotAdminError();
      }
      set({ user: me, status: "authed" });
    } catch (err) {
      if (epoch !== authEpoch) return;
      if (err instanceof NotAdminError ||
          (axios.isAxiosError(err) && err.response?.status === 401)) setToken(null);
      set({ user: null, status: "anon" });
      if (err instanceof NotAdminError) throw err;
      throw new Error(errorMessage(err, "Sign-in failed"));
    }
  },

  logout: () => {
    ++authEpoch;
    setToken(null);
    set({ user: null, status: "anon" });
  },

  bootstrap: async () => {
    const epoch = ++authEpoch;
    set({ status: "loading" });
    const initialToken = getToken();
    if (!initialToken) {
      set({ status: "anon" });
      return;
    }
    try {
      const me = await authApi.me();
      if (epoch !== authEpoch || !getToken()) return;
      if (me.role === "admin") set({ user: me, status: "authed" });
      else {
        setToken(null);
        set({ user: null, status: "anon" });
      }
    } catch {
      if (epoch !== authEpoch) return;
      // A network/5xx failure is not evidence that saved credentials expired.
      set({ user: null, status: getToken() ? "error" : "anon" });
    }
  },
}));
