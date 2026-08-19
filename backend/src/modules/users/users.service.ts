import { supabase, supabaseAdmin } from "../../config/supabase";
import type { UserRow } from "../../shared/types/database";
import { createHttpError } from "../../shared/utils/http-error";
import type { UpdateUserDto } from "./users.types";

type UserProfileUpsertRow = {
  readonly id: string;
  readonly email: string;
  readonly updated_at: string;
  readonly display_name?: string;
};

type UserProfileIdentity = {
  readonly id: string;
  readonly email: string;
  readonly displayName?: string;
};

export const toUserProfileUpsertRow = (user: UserProfileIdentity): UserProfileUpsertRow => {
  const row: UserProfileUpsertRow = {
    id: user.id,
    email: user.email,
    updated_at: new Date().toISOString()
  };
  if (user.displayName !== undefined) {
    return { ...row, display_name: user.displayName };
  }
  return row;
};

export const findUserById = async (userId: string): Promise<UserRow> => {
  const { data, error } = await supabase
    .from("users")
    .select("*")
    .eq("id", userId)
    .single<UserRow>();

  if (error || !data) throw createHttpError(404, "User was not found");
  return data;
};

export const upsertUserProfile = async (user: UserProfileIdentity): Promise<UserRow> => {
  const { data, error } = await supabase
    .from("users")
    .upsert(toUserProfileUpsertRow(user))
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
