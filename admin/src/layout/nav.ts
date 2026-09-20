import { Bot, Coins, CreditCard, LayoutDashboard, ReceiptText, UserPlus, Users, type LucideIcon } from "lucide-react";

export interface NavItem {
  to: string;
  /** i18n key under `nav.*`, resolved at render time. */
  labelKey: string;
  icon: LucideIcon;
}
export interface NavGroup {
  /** i18n key under `nav.*`, resolved at render time. */
  titleKey?: string;
  items: NavItem[];
}

/**
 * Sidebar structure. Groups render only when they have items, so adding a page
 * means adding one entry here plus its route in App.tsx.
 */
export const NAV: NavGroup[] = [
  {
    titleKey: "nav.overview",
    items: [{ to: "/dashboard", labelKey: "nav.dashboard", icon: LayoutDashboard }],
  },
  {
    titleKey: "nav.management",
    items: [
      { to: "/users", labelKey: "nav.users", icon: Users },
      { to: "/agent", labelKey: "nav.agent", icon: Bot },
      { to: "/invitation-settings", labelKey: "nav.invitationSettings", icon: UserPlus },
    ],
  },
  {
    titleKey: "nav.billing",
    items: [
      { to: "/subscription-plans", labelKey: "nav.subscriptionPlans", icon: CreditCard },
      { to: "/coin-packs", labelKey: "nav.coinPacks", icon: Coins },
      { to: "/billing-activity", labelKey: "nav.billingActivity", icon: ReceiptText },
    ],
  },
];
