import { z } from "zod";
import { supabase } from "../../config/supabase";
import { createHttpError } from "../../shared/utils/http-error";
import { verifyAppleNotification } from "./apple-iap-verifier";
import { threadAmountForAppleProduct } from "./apple-iap-products";
import type { AppleIapVerifiedNotification } from "./apple-iap-policy";

export type AppleAppStoreNotificationRequest = {
  readonly signedPayload: string;
};

export type AppleAppStoreNotificationResult =
  | {
      readonly kind: "record";
      readonly status: "processed" | "already_processed";
    }
  | {
      readonly kind: "reconcile";
      readonly availableThreads: number;
      readonly status: "credited" | "already_credited" | "already_processed";
    };

type AppleAppStoreNotificationDependencies = {
  readonly verifyAppleNotification: (
    signedPayload: string
  ) => Promise<AppleIapVerifiedNotification>;
  readonly processVerifiedNotification: (
    notification: AppleIapVerifiedNotification
  ) => Promise<AppleAppStoreNotificationResult>;
};

const recordRowSchema = z.object({
  status: z.enum(["processed", "already_processed"])
});
const reconciliationRowSchema = z.object({
  available_threads: z.number().int().nonnegative(),
  status: z.enum(["credited", "already_credited", "already_processed"])
});

export const processVerifiedAppleNotification = async (
  notification: AppleIapVerifiedNotification
): Promise<AppleAppStoreNotificationResult> => {
  switch (notification.kind) {
    case "record": {
      const { data, error } = await supabase
        .rpc("record_apple_iap_notification", {
          p_notification_uuid: notification.notificationUUID,
          p_notification_type: notification.notificationType,
          p_subtype: notification.subtype,
          p_environment: notification.environment
        })
        .single();
      const parsed = recordRowSchema.safeParse(data);
      if (error || !parsed.success) {
        throw createHttpError(500, "Failed to record Apple server notification");
      }
      return { kind: "record", status: parsed.data.status };
    }
    case "reconcile": {
      const transaction = notification.transaction;
      const { data, error } = await supabase
        .rpc("reconcile_apple_iap_notification", {
          p_notification_uuid: notification.notificationUUID,
          p_notification_type: notification.notificationType,
          p_subtype: notification.subtype,
          p_environment: notification.environment,
          p_user_id: transaction.appAccountToken,
          p_transaction_id: transaction.transactionId,
          p_original_transaction_id: transaction.originalTransactionId,
          p_product_id: transaction.productId,
          p_app_account_token: transaction.appAccountToken,
          p_purchased_at: transaction.purchasedAt,
          p_transaction_environment: transaction.environment,
          p_thread_amount: threadAmountForAppleProduct(transaction.productId)
        })
        .single();
      const parsed = reconciliationRowSchema.safeParse(data);
      if (error || !parsed.success) {
        throw createHttpError(500, "Failed to reconcile Apple server notification");
      }
      return {
        kind: "reconcile",
        availableThreads: parsed.data.available_threads,
        status: parsed.data.status
      };
    }
    default: {
      const unreachable: never = notification;
      throw new TypeError(`Unsupported Apple notification variant: ${String(unreachable)}`);
    }
  }
};

export const settleAppleAppStoreNotification = async (
  request: AppleAppStoreNotificationRequest,
  dependencies: AppleAppStoreNotificationDependencies
): Promise<AppleAppStoreNotificationResult> => {
  const notification = await dependencies.verifyAppleNotification(request.signedPayload);
  return dependencies.processVerifiedNotification(notification);
};

export const submitAppleAppStoreNotification = async (
  request: AppleAppStoreNotificationRequest
): Promise<AppleAppStoreNotificationResult> => {
  return settleAppleAppStoreNotification(request, {
    verifyAppleNotification,
    processVerifiedNotification: processVerifiedAppleNotification
  });
};
