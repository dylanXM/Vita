import { describe, expect, it } from "vitest";

import ar from "./ar";
import en from "./en";
import es from "./es";
import ja from "./ja";
import ko from "./ko";
import pt from "./pt";
import zhHans from "./zh-Hans";
import zhHant from "./zh-Hant";

function leafKeys(value: unknown, prefix = ""): string[] {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return [prefix];
  return Object.entries(value).flatMap(([key, child]) => leafKeys(child, prefix ? prefix + "." + key : key));
}

describe("admin translations", () => {
  it("keeps every locale aligned with the English key set", () => {
    const expected = leafKeys(en).sort();
    for (const [locale, translations] of Object.entries({ ar, es, ja, ko, pt, "zh-Hans": zhHans, "zh-Hant": zhHant })) {
      expect(leafKeys(translations).sort(), locale + " translation keys").toEqual(expected);
    }
  });

  it("contains labels for every media route", () => {
    for (const key of [
      "route.image_life_photo",
      "route.image_requested_photo",
      "route.audio_transcription",
      "route.audio_speech",
      "route.video_life_clip",
      "route.video_realtime_avatar",
    ] as const) {
      expect(en.mediaModels[key]).not.toBe("");
      expect(zhHans.mediaModels[key]).not.toBe("");
    }
  });
});
