import { Bot, Coins, CreditCard, HeartHandshake, ImagePlay, LayoutDashboard, Megaphone, PanelsTopLeft, ReceiptText, ScrollText, Share2, ShoppingBag, UserPlus, Users, type LucideIcon } from "lucide-react";

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
    titleKey: "nav.appContent",
    items: [
      { to: "/onboarding", labelKey: "nav.onboarding", icon: PanelsTopLeft },
      { to: "/whats-new", labelKey: "nav.whatsNew", icon: Megaphone },
      { to: "/social-links", labelKey: "nav.socialLinks", icon: Share2 },
      { to: "/legal-documents", labelKey: "nav.legalDocuments", icon: ScrollText },
    ],
  },
  {
    titleKey: "nav.management",
    items: [
      { to: "/users", labelKey: "nav.users", icon: Users },
      { to: "/companions", labelKey: "nav.companions", icon: HeartHandshake },
      { to: "/agent", labelKey: "nav.agent", icon: Bot },
      { to: "/media-models", labelKey: "nav.mediaModels", icon: ImagePlay },
      { to: "/invitation-settings", labelKey: "nav.invitationSettings", icon: UserPlus },
    ],
  },
  {
    titleKey: "nav.billing",
    items: [
      { to: "/subscription-plans", labelKey: "nav.subscriptionPlans", icon: CreditCard },
      { to: "/coin-packs", labelKey: "nav.coinPacks", icon: Coins },
      { to: "/credit-products", labelKey: "nav.creditProducts", icon: ShoppingBag },
      { to: "/billing-activity", labelKey: "nav.billingActivity", icon: ReceiptText },
    ],
  },
];
