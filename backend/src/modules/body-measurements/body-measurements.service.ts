import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { asOptionalNumber, asOptionalRecord } from "../../shared/utils/request";

export const createBodyMeasurementForUser = async (userId: string, body: Record<string, unknown>) => {
  const { data, error } = await supabase
    .from("body_measurements")
    .insert({
      user_id: userId,
      height_cm: asOptionalNumber(body.heightCm ?? body.height_cm),
      weight_kg: asOptionalNumber(body.weightKg ?? body.weight_kg),
      shoulder_width: asOptionalNumber(body.shoulderWidth ?? body.shoulder_width),
      chest_circumference: asOptionalNumber(body.chestCircumference ?? body.chest_circumference),
      waist_circumference: asOptionalNumber(body.waistCircumference ?? body.waist_circumference),
      hip_circumference: asOptionalNumber(body.hipCircumference ?? body.hip_circumference),
      outseam: asOptionalNumber(body.outseam),
      raw_data: asOptionalRecord(body.rawData ?? body.raw_data)
    })
    .select("*")
    .single();
  if (error || !data) throw createHttpError(500, "Failed to save body measurement");
  return data;
};

export const listBodyMeasurementsForUser = async (userId: string) => {
  const { data, error } = await supabase
    .from("body_measurements")
    .select("*")
    .eq("user_id", userId)
    .order("updated_at", { ascending: false });
  if (error) throw createHttpError(500, "Failed to load body measurements");
  return data ?? [];
};
