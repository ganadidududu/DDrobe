import assert from "node:assert/strict";
import test from "node:test";
import { rowToMeasurements, toLegacyMeasurementStorage } from "./measurements";

test("rowToMeasurements normalizes a legacy inseam column to outseam", () => {
  const legacyRow = {
    waist_width: 40,
    hip_width: 53,
    rise: 30,
    inseam: 101
  };

  assert.deepEqual(rowToMeasurements(legacyRow), {
    waist_width: 40,
    hip_width: 53,
    rise: 30,
    outseam: 101
  });
});

test("toLegacyMeasurementStorage renames outseam without dropping metadata", () => {
  assert.deepEqual(
    toLegacyMeasurementStorage({
      size_label: "M",
      waist_width: 40,
      outseam: 101
    }),
    {
      size_label: "M",
      waist_width: 40,
      inseam: 101
    }
  );
});
