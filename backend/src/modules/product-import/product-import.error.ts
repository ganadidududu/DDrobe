import type { ProductImportErrorCode, ProductImportFailure } from "./product-import.types";

export class ProductImportError extends Error {
  public constructor(
    public readonly code: ProductImportErrorCode,
    message: string,
    public readonly retryable: boolean,
    public readonly statusCode: number
  ) {
    super(message);
    this.name = "ProductImportError";
  }

  public toResponse(): ProductImportFailure {
    return {
      success: false,
      error: { code: this.code, message: this.message, retryable: this.retryable },
      partialData: null
    };
  }
}
