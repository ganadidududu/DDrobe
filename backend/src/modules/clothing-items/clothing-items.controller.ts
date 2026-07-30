import type { NextFunction, Response } from "express";
import type { AuthenticatedRequest } from "../../shared/types/http";
import { asRequiredString, requireUser, sendCreated } from "../../shared/utils/request";
import {
  createClothingItemForUser,
  createClothingItemWithSizeForUser,
  deleteClothingItemForUser,
  getClothingItemForUser,
  listClothingItemsForUser,
  updateClothingItemForUser
} from "./clothing-items.service";

export const createClothingItem = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    sendCreated(res, await createClothingItemForUser(requireUser(req).id, req.body));
  } catch (error) {
    next(error);
  }
};

export const createClothingItemWithSize = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    sendCreated(res, await createClothingItemWithSizeForUser(requireUser(req).id, req.body));
  } catch (error) {
    next(error);
  }
};

export const listClothingItems = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await listClothingItemsForUser(requireUser(req).id));
  } catch (error) {
    next(error);
  }
};

export const getClothingItem = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await getClothingItemForUser(requireUser(req).id, asRequiredString(req.params.id, "id")));
  } catch (error) {
    next(error);
  }
};

export const updateClothingItem = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    res.json(await updateClothingItemForUser(requireUser(req).id, asRequiredString(req.params.id, "id"), req.body));
  } catch (error) {
    next(error);
  }
};

export const deleteClothingItem = async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    await deleteClothingItemForUser(requireUser(req).id, asRequiredString(req.params.id, "id"));
    res.status(204).send();
  } catch (error) {
    next(error);
  }
};
