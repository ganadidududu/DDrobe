import type { UserRow } from "../../shared/types/database";

export type UpdateUserDto = Partial<
  Pick<UserRow, "display_name" | "gender" | "birth_date" | "birth_year">
>;
