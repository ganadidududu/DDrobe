import { Router } from "express";
import { env } from "./config/env";
import { signup, login, loginWithApple, loginWithGoogle } from "./modules/auth/auth.controller";
import { completeOnboardingController } from "./modules/auth/auth-onboarding.controller";
import { createBodyMeasurement, listBodyMeasurements } from "./modules/body-measurements/body-measurements.controller";
import {
  createClothingItem,
  createClothingItemWithSize,
  deleteClothingItem,
  getClothingItem,
  listClothingItems,
  updateClothingItem
} from "./modules/clothing-items/clothing-items.controller";
import {
  createClothingSize,
  deleteClothingSize,
  listClothingSizes,
  updateClothingSize
} from "./modules/clothing-sizes/clothing-sizes.controller";
import {
  createExternalProduct,
  createExternalProductFromUrl,
  getExternalProduct,
  listExternalProducts,
  updateExternalProduct
} from "./modules/external-products/external-products.controller";
import {
  createExternalProductSize,
  deleteExternalProductSize,
  listExternalProductSizes,
  updateExternalProductSize
} from "./modules/external-product-sizes/external-product-sizes.controller";
import { createFeedback, listFeedback } from "./modules/feedback/feedback.controller";
import {
  getClosetReferenceProfileController,
  getFitAnalysisResultController,
  recentFitAnalysisResultsController,
  recommendFitBatchController,
  recommendFitController
} from "./modules/fit/fit.controller";
import { generateFitReportController } from "./modules/fit-report/fit-report.controller";
import {
  createReferenceClothing,
  deactivateReferenceClothing,
  getReferenceClothing,
  getReferenceClothingByCategory,
  listReferenceClothing,
  updateReferenceClothing
} from "./modules/reference-clothing/reference-clothing.controller";
import {
  listRecommendationLogs,
  markRecommendationClicked,
  markRecommendationPurchased
} from "./modules/recommendation-logs/recommendation-logs.controller";
import { deleteMe, getMe, updateMe } from "./modules/users/users.controller";
import {
  appleIapPurchaseController,
  getThreadBalanceController
} from "./modules/thread-wallet/thread-wallet.controller";
import {
  generateStylingController,
  listSavedStylingController,
  saveStylingLookController,
} from "./modules/styling/styling.controller";
import { authMiddleware } from "./middleware/auth.middleware";
import { previewProductImportController } from "./modules/product-import/product-import.controller";

export const routes = Router();

routes.post("/auth/signup", signup);
routes.post("/auth/login", login);
routes.post("/auth/google", loginWithGoogle);
routes.post("/auth/apple", loginWithApple);

routes.use(authMiddleware);

routes.post("/auth/onboarding", completeOnboardingController);

routes.get("/users/me", getMe);
routes.patch("/users/me", updateMe);
routes.delete("/users/me", deleteMe);
routes.get("/thread-wallet/balance", getThreadBalanceController);
if (env.appleIapEnabled) {
  routes.post("/thread-wallet/iap/verify", appleIapPurchaseController);
}
routes.post("/body-measurements", createBodyMeasurement);
routes.get("/body-measurements", listBodyMeasurements);

routes.post("/clothing-items", createClothingItem);
routes.post("/clothing-items/with-size", createClothingItemWithSize);
routes.get("/clothing-items", listClothingItems);
routes.get("/clothing-items/:id", getClothingItem);
routes.patch("/clothing-items/:id", updateClothingItem);
routes.delete("/clothing-items/:id", deleteClothingItem);
routes.post("/clothing-items/:id/sizes", createClothingSize);
routes.get("/clothing-items/:id/sizes", listClothingSizes);
routes.patch("/clothing-sizes/:id", updateClothingSize);
routes.delete("/clothing-sizes/:id", deleteClothingSize);
routes.post("/reference-clothing", createReferenceClothing);
routes.get("/reference-clothing", listReferenceClothing);
routes.get("/reference-clothing/by-category/:category", getReferenceClothingByCategory);
routes.get("/reference-clothing/:id", getReferenceClothing);
routes.patch("/reference-clothing/:id", updateReferenceClothing);
routes.patch("/reference-clothing/:id/deactivate", deactivateReferenceClothing);

routes.post("/external-products", createExternalProduct);
routes.post("/external-products/from-url", createExternalProductFromUrl);
routes.post("/api/v1/products/import-url/preview", previewProductImportController);
routes.get("/external-products", listExternalProducts);
routes.get("/external-products/:id", getExternalProduct);
routes.patch("/external-products/:id", updateExternalProduct);
routes.post("/external-products/:id/sizes", createExternalProductSize);
routes.get("/external-products/:id/sizes", listExternalProductSizes);
routes.patch("/external-product-sizes/:id", updateExternalProductSize);
routes.delete("/external-product-sizes/:id", deleteExternalProductSize);

routes.post("/fit/recommend", recommendFitController);
routes.post("/fit/recommend/batch", recommendFitBatchController);
routes.get("/fit/reference-profile/:garmentKind", getClosetReferenceProfileController);
routes.get("/fit-analysis-results/recent", recentFitAnalysisResultsController);
routes.get("/fit-analysis-results", recentFitAnalysisResultsController);
routes.get("/fit-analysis-results/:id", getFitAnalysisResultController);
routes.post("/fit-analysis-results/:id/report", generateFitReportController);

routes.post("/fit-analysis-results/:id/feedback", createFeedback);

routes.get("/styling/saved", listSavedStylingController);
routes.post("/styling/generate", generateStylingController);
routes.post("/styling/:id/save", saveStylingLookController);
routes.get("/user-feedback", listFeedback);
routes.get("/recommendation-logs", listRecommendationLogs);
routes.patch("/recommendation-logs/:id/click", markRecommendationClicked);
routes.patch("/recommendation-logs/:id/purchase", markRecommendationPurchased);
