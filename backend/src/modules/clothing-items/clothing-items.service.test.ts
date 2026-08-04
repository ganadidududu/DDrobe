import { describe, expect, it, vi } from "vitest";

const insertClothingItemWithSize = vi.fn();

vi.mock("./clothing-items.repository", () => ({
  insertClothingItem: vi.fn(),
  insertClothingItemWithSize,
  patchClothingItem: vi.fn(),
  removeClothingItem: vi.fn(),
  selectClothingItemById: vi.fn(),
  selectClothingItems: vi.fn()
}));

describe("createClothingItemWithSizeForUser", () => {
  it("requires and forwards one retry-safe idempotency key", async () => {
    const { createClothingItemWithSizeForUser } = await import("./clothing-items.service");
    const key = "11111111-1111-4111-8111-111111111111";
    insertClothingItemWithSize.mockResolvedValue({ clothingItem: {}, clothingSize: {} });

    await createClothingItemWithSizeForUser("user-1", {
      idempotencyKey: key,
      item: {
        name: "Oxford Shirt",
        category: "shirt",
        fitType: "regular"
      },
      size: { sizeLabel: "M", shoulder_width: 45, chest_width: 56 }
    });

    expect(insertClothingItemWithSize).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({ name: "Oxford Shirt", category: "shirt" }),
      expect.objectContaining({ size_label: "M" }),
      key
    );
  });

  it("rejects a missing or malformed retry key before persisting", async () => {
    const { createClothingItemWithSizeForUser } = await import("./clothing-items.service");

    expect(() =>
      createClothingItemWithSizeForUser("user-1", {
        item: { name: "Oxford Shirt", category: "shirt" },
        size: { sizeLabel: "M" }
      })
    ).toThrow("idempotencyKey is required");

    expect(insertClothingItemWithSize).toHaveBeenCalledTimes(1);
  });
});
