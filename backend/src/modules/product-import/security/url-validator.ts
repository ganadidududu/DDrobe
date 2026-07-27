import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { ProductImportError } from "../product-import.error";

const isPrivateIpv4 = (address: string): boolean => {
  const octets = address.split(".").map(Number);
  if (octets.length !== 4 || octets.some((octet) => !Number.isInteger(octet) || octet < 0 || octet > 255)) {
    return true;
  }
  const [first = 0, second = 0] = octets;
  return first === 0
    || first === 10
    || first === 127
    || (first === 169 && second === 254)
    || (first === 172 && second >= 16 && second <= 31)
    || (first === 192 && second === 168)
    || (first === 100 && second >= 64 && second <= 127)
    || first >= 224;
};

const isPrivateIpv6 = (address: string): boolean => {
  const value = address.toLowerCase().split("%")[0] ?? "";
  if (value === "::" || value === "::1") return true;
  if (value.startsWith("fc") || value.startsWith("fd")) return true;
  if (/^fe[89ab]/.test(value)) return true;
  if (value.startsWith("::ffff:")) return isPrivateIpv4(value.slice(7));
  return false;
};

export const isPrivateIpAddress = (address: string): boolean => {
  const version = isIP(address);
  if (version === 4) return isPrivateIpv4(address);
  if (version === 6) return isPrivateIpv6(address);
  return true;
};

export const parseProductUrl = (rawUrl: string): URL => {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new ProductImportError("INVALID_URL", "유효한 상품 URL을 입력해주세요.", false, 400);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new ProductImportError("UNSUPPORTED_PROTOCOL", "http 또는 https URL만 지원합니다.", false, 400);
  }
  if (url.username || url.password) {
    throw new ProductImportError("INVALID_URL", "인증 정보가 포함된 URL은 지원하지 않습니다.", false, 400);
  }
  return url;
};

export const assertPublicUrl = async (url: URL): Promise<void> => {
  const hostname = url.hostname.toLowerCase().replace(/\.$/, "");
  if (hostname === "localhost" || hostname.endsWith(".localhost") || hostname.endsWith(".local")) {
    throw new ProductImportError("BLOCKED_PRIVATE_NETWORK", "내부 네트워크 주소는 사용할 수 없습니다.", false, 400);
  }
  if (isIP(hostname) !== 0) {
    if (isPrivateIpAddress(hostname)) {
      throw new ProductImportError("BLOCKED_PRIVATE_NETWORK", "내부 네트워크 주소는 사용할 수 없습니다.", false, 400);
    }
    return;
  }
  let addresses: readonly { readonly address: string }[];
  try {
    addresses = await lookup(hostname, { all: true, verbatim: true });
  } catch {
    throw new ProductImportError("PRODUCT_PAGE_NOT_ACCESSIBLE", "상품 페이지의 주소를 확인할 수 없습니다.", true, 502);
  }
  if (addresses.length === 0 || addresses.some(({ address }) => isPrivateIpAddress(address))) {
    throw new ProductImportError("BLOCKED_PRIVATE_NETWORK", "내부 네트워크 주소는 사용할 수 없습니다.", false, 400);
  }
};

export const normalizeProductUrl = (url: URL): string => {
  const normalized = new URL(url.href);
  normalized.hash = "";
  for (const key of [...normalized.searchParams.keys()]) {
    if (key.toLowerCase().startsWith("utm_") || ["fbclid", "gclid"].includes(key.toLowerCase())) {
      normalized.searchParams.delete(key);
    }
  }
  return normalized.href;
};
