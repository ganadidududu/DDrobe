import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { asOptionalNumber, asOptionalString, requireUser } from "../../shared/utils/request";
import { deleteUserAccount, findUserById, updateUserProfile } from "./users.service";

export const getMe = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const user = requireUser(req);
    res.json(await findUserById(user.id));
  } catch (error) {
    next(error);
  }
};

export const updateMe = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const user = requireUser(req);
    res.json(
      await updateUserProfile(user.id, {
        display_name: asOptionalString(req.body.displayName ?? req.body.display_name),
        gender: asOptionalString(req.body.gender),
        birth_date: asOptionalString(req.body.birthDate ?? req.body.birth_date),
        birth_year: asOptionalNumber(req.body.birthYear ?? req.body.birth_year)
      })
    );
  } catch (error) {
    next(error);
  }
};

export const deleteMe = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    await deleteUserAccount(requireUser(req).id);
    res.status(204).send();
  } catch (error) {
    next(error);
  }
};
