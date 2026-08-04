import { supabase, supabaseAdmin } from "../../config/supabase";
import type { UserRow } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import type { UpdateUserDto } from "./users.types";

export const findUserById = async (userId: string): Promise<UserRow> => {
  const { data, error } = await supabase
    .from("users")
    .select("*")
    .eq("id", userId)
    .single<UserRow>();

  if (error || !data) throw createHttpError(404, "User was not found");
  return data;
};

export const upsertUserProfile = async (user: {
  id: string;
  email: string;
  displayName?: string | null;
}): Promise<UserRow> => {
  const { data, error } = await supabase
    .from("users")
    .upsert({
      id: user.id,
      email: user.email,
      display_name: user.displayName ?? null,
      updated_at: new Date().toISOString()
    })
    .select("*")
    .single<UserRow>();

  if (error || !data) {
    console.error("ERROR:", error);
    console.error("DATA:", data);

    throw createHttpError(500, "Failed to save user profile");
  }  
  return data;
};

export const updateUserProfile = async (
  userId: string,
  dto: UpdateUserDto
): Promise<UserRow> => {
  const { data, error } = await supabase
    .from("users")
    .update({ ...dto, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .select("*")
    .single<UserRow>();

  if (error || !data) throw createHttpError(500, "Failed to update user profile");
  return data;
};

export const deleteUserAccount = async (userId: string): Promise<void> => {
  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
  if (error) throw createHttpError(500, "Failed to delete user account");
};
