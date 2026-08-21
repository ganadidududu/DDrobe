export const appleIapThreadProductIDs = {
  pack5: "com.inseong.coordit.thread.5",
  pack10: "com.inseong.coordit.thread.10",
  pack20: "com.inseong.coordit.thread.20"
} as const;

export type AppleIapThreadProductID =
  (typeof appleIapThreadProductIDs)[keyof typeof appleIapThreadProductIDs];

const assertNever = (value: never): never => {
  throw new TypeError(`Unsupported Apple IAP product: ${String(value)}`);
};

export const threadAmountForAppleProduct = (productId: AppleIapThreadProductID): number => {
  switch (productId) {
    case appleIapThreadProductIDs.pack5:
      return 5;
    case appleIapThreadProductIDs.pack10:
      return 10;
    case appleIapThreadProductIDs.pack20:
      return 20;
    default:
      return assertNever(productId);
  }
};
