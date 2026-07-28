import { describe, expect, it } from "vitest";
import { authenticateBearer } from "./auth.middleware";

describe("authenticateBearer", () => {
  it("returns unauthorized instead of invalid algorithm when Supabase rejects an ES256 token", async () => {
    const verifyBearer = async () => null;

    await expect(
      authenticateBearer(
        "Bearer eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEifQ.signature",
        verifyBearer
      )
    ).rejects.toMatchObject({
      statusCode: 401,
      message: "로그인이 만료됐어요. 다시 로그인해 주세요."
    });
  });
});
