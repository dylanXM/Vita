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

  it("tracks both the default and ordered fallback selections", () => {
    expect([...selectedMediaModelIDs(route)]).toEqual(["primary", "backup"]);
  });

  it("removes unfinished fallback rows before saving without mutating UI state", () => {
    const input = [{ ...route, primary_model_id: " primary ", fallback_model_ids: [" backup-1 ", "", " backup-2 ", "   "] }];
    const result = normalizeMediaRoutesForSave(input);
    expect(result[0]).toMatchObject({ primary_model_id: "primary", fallback_model_ids: ["backup-1", "backup-2"] });
    expect(input[0].fallback_model_ids).toEqual([" backup-1 ", "", " backup-2 ", "   "]);
  });
});
