import { createBrowserRouter, Navigate, RouterProvider, useRouteError, Link } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { AdminLayout } from "@/layout/AdminLayout";
import { RequireAuth } from "@/routes/guards";
import { LoginPage } from "@/pages/LoginPage";
import { DashboardPage } from "@/pages/DashboardPage";
import { UsersPage } from "@/pages/UsersPage";
import { UserDetailPage } from "@/pages/UserDetailPage";
import { NotFoundPage } from "@/pages/NotFoundPage";
import { AgentPage } from "@/pages/AgentPage";
import { CoinPacksPage, SubscriptionPlansPage } from "@/pages/BillingProductsPage";
import { BillingActivityPage } from "@/pages/BillingActivityPage";
import { InvitationSettingsPage } from "@/pages/InvitationSettingsPage";
import { CompanionsPage } from "@/pages/CompanionsPage";
import { CompanionDetailPage } from "@/pages/CompanionDetailPage";
import { OnboardingPage } from "@/pages/OnboardingPage";
import { WhatsNewPage } from "@/pages/WhatsNewPage";
import { SocialLinksPage } from "@/pages/SocialLinksPage";
import { CreditProductsPage } from "@/pages/CreditProductsPage";
import { MediaModelsPage } from "@/pages/MediaModelsPage";
import { ModelServicesPage } from "@/pages/ModelServicesPage";
import { LegalDocumentsPage } from "@/pages/LegalDocumentsPage";
import { AIPetsPage } from "@/pages/AIPetsPage";
import { StoryHubPage } from "@/pages/StoryHubPage";
import { StoragePage } from "@/pages/StoragePage";
import { Button } from "@/components/ui/button";

function RouteError() {
  const { t } = useTranslation();
  const err = useRouteError() as { message?: string } | undefined;
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-8 text-center">
      <h1 className="text-2xl font-bold">{t("common.somethingWrong")}</h1>
      <p className="max-w-md text-sm text-muted-foreground">
        {err?.message ?? t("common.failedToLoad")}
      </p>
      <div className="flex gap-3">
        <Button asChild>
          <Link to="/dashboard">{t("common.backToDashboard")}</Link>
        </Button>
        <Button variant="outline" onClick={() => window.location.reload()}>
          {t("common.refresh")}
        </Button>
      </div>
    </div>
  );
}

const router = createBrowserRouter([
  { path: "/login", element: <LoginPage /> },
  {
    path: "/",
    element: (
      <RequireAuth>
        <AdminLayout />
      </RequireAuth>
    ),
    errorElement: <RouteError />,
    children: [
      { index: true, element: <Navigate to="/dashboard" replace /> },
      { path: "dashboard", element: <DashboardPage /> },
      { path: "users", element: <UsersPage /> },
      { path: "users/:id", element: <UserDetailPage /> },
      { path: "companions", element: <CompanionsPage /> },
      { path: "companions/:id", element: <CompanionDetailPage /> },
      { path: "agent", element: <AgentPage /> },
      { path: "media-models", element: <MediaModelsPage /> },
      { path: "model-services", element: <ModelServicesPage /> },
      { path: "storage", element: <StoragePage /> },
      { path: "subscription-plans", element: <SubscriptionPlansPage /> },
      { path: "coin-packs", element: <CoinPacksPage /> },
      { path: "billing-activity", element: <BillingActivityPage /> },
      { path: "credit-products", element: <CreditProductsPage /> },
      { path: "invitation-settings", element: <InvitationSettingsPage /> },
      { path: "onboarding", element: <OnboardingPage /> },
      { path: "whats-new", element: <WhatsNewPage /> },
      { path: "social-links", element: <SocialLinksPage /> },
      { path: "legal-documents", element: <LegalDocumentsPage /> },
      { path: "ai-pets", element: <AIPetsPage /> },
      { path: "story-hub", element: <StoryHubPage /> },
    ],
  },
  { path: "*", element: <NotFoundPage /> },
]);

export default function App() {
  return <RouterProvider router={router} />;
}
