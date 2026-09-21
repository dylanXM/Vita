import { describe, expect, it } from "vitest";

import type { AIModel, MediaModelRoute } from "@/api/types";
import { compatibleMediaModels, normalizeMediaRoutesForSave, selectedMediaModelIDs } from "./media-model-routes";

const route: MediaModelRoute = {
  route_key: "image_life_photo",
  media_type: "image",
  enabled: true,
  primary_model_id: "primary",
  fallback_model_ids: ["backup"],
};

function model(id: string, enabled: boolean, capabilities: AIModel["capabilities"]): AIModel {
  return {
    id,
    provider_id: "provider",
    provider_name: "Provider",
    model_name: id,
    display_name: id,
    capabilities,
    configured_scenarios: [...(capabilities.includes("text") ? ["text_chat" as const, "text_character_profile" as const] : []), ...(capabilities.includes("image") ? ["image_life_photo" as const] : [])],
    subscription_plan_ids: [],
    enabled,
    created_at: "2026-09-20T00:00:00Z",
    updated_at: "2026-09-20T00:00:00Z",
  };
}

describe("media model route helpers", () => {
  it("only offers enabled models with the route capability", () => {
    const result = compatibleMediaModels([
      model("image", true, ["image"]),
      model("disabled", false, ["image"]),
      model("audio", true, ["audio"]),
      model("multi", true, ["text", "image"]),
    ], route);
    expect(result.map((item) => item.id)).toEqual(["image", "multi"]);
  });

  it("does not require an optional availability test for routing", () => {
    const requestedPhotoRoute: MediaModelRoute = { ...route, route_key: "image_requested_photo" };
    const untested = model("untested-image", true, ["image"]);
    untested.configured_scenarios = ["image_requested_photo"];
    expect(compatibleMediaModels([untested], requestedPhotoRoute).map((item) => item.id)).toEqual(["untested-image"]);
  });

  it("does not offer a model for a scene it was not configured to serve", () => {
    const requestedPhotoRoute: MediaModelRoute = { ...route, route_key: "image_requested_photo" };
    expect(compatibleMediaModels([model("life-only", true, ["image"])], requestedPhotoRoute)).toEqual([]);
  });

  it("keeps subscription-only models out of the standard route", () => {
    const dedicated = model("dedicated", true, ["image"]);
    dedicated.subscription_plan_ids = ["plus-plan"];
    expect(compatibleMediaModels([dedicated], route)).toEqual([]);
  });

  it("tracks both the default and ordered fallback selections", () => {
    expect([...selectedMediaModelIDs(route)]).toEqual(["primary", "backup"]);
  });

  it("offers only enabled text models for text routes", () => {
    const textRoute: MediaModelRoute = { route_key: "text_chat", media_type: "text", enabled: true, primary_model_id: null, fallback_model_ids: [] };
    const result = compatibleMediaModels([model("text", true, ["text"]), model("image", true, ["image"]), model("disabled", false, ["text"])], textRoute);
    expect(result.map((item) => item.id)).toEqual(["text"]);
  });

  it("removes unfinished fallback rows before saving without mutating UI state", () => {
    const input = [{ ...route, primary_model_id: " primary ", fallback_model_ids: [" backup-1 ", "", " backup-2 ", "   "] }];
    const result = normalizeMediaRoutesForSave(input);
    expect(result[0]).toMatchObject({ primary_model_id: "primary", fallback_model_ids: ["backup-1", "backup-2"] });
    expect(input[0].fallback_model_ids).toEqual([" backup-1 ", "", " backup-2 ", "   "]);
  });
});
