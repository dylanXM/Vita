import type { AIModel, MediaModelRoute } from "@/api/types";

export function compatibleMediaModels(models: AIModel[], route: MediaModelRoute): AIModel[] {
  return models.filter((model) => model.enabled && (model.subscription_plan_ids ?? []).length === 0 && model.capabilities.includes(route.media_type) && (model.configured_scenarios ?? []).some((scenario) => scenario === route.route_key));
}

export function selectedMediaModelIDs(route: MediaModelRoute): Set<string> {
  return new Set([route.primary_model_id, ...route.fallback_model_ids].filter((id): id is string => Boolean(id)));
}

export function normalizeMediaRoutesForSave(routes: MediaModelRoute[]): MediaModelRoute[] {
  return routes.map((route) => ({
    ...route,
    primary_model_id: route.primary_model_id?.trim() || null,
    fallback_model_ids: route.fallback_model_ids.map((id) => id.trim()).filter(Boolean),
  }));
}

/** Send only changed settings; unrelated stale routes must not block a save. */
export function changedMediaRoutesForSave(routes: MediaModelRoute[], saved: MediaModelRoute[]): MediaModelRoute[] {
  const baseline = new Map(normalizeMediaRoutesForSave(saved).map((route) => [route.route_key, route]));
  return normalizeMediaRoutesForSave(routes).filter((route) => {
    const previous = baseline.get(route.route_key);
    return !previous || route.enabled !== previous.enabled ||
      route.primary_model_id !== previous.primary_model_id ||
      JSON.stringify(route.fallback_model_ids) !== JSON.stringify(previous.fallback_model_ids);
  });
}
