import type { Category, FitType, MeasurementKey } from "../../shared/types/database";
import type { FitReportInput } from "./fit-report.types";

type GarmentProfile = Pick<FitReportInput["targetProduct"], "category" | "fitType">;
type MeasurementRow = FitReportInput["measurements"][number];

const CATEGORY_LABELS: Record<Category, string> = {
  tshirt: "티셔츠",
  shirt: "셔츠",
  sweatshirt: "스웨트셔츠",
  hoodie: "후디",
  knit: "니트",
  jacket: "재킷",
  coat: "코트",
  pants: "팬츠",
  jeans: "데님 팬츠",
  shorts: "쇼츠",
  skirt: "스커트"
};

const FIT_TYPE_LABELS: Record<FitType, string> = {
  slim: "슬림 핏",
  regular: "레귤러 핏",
  relaxed: "릴랙스드 핏",
  oversized: "오버사이즈 핏"
};

const LOWER_BODY_CATEGORIES: ReadonlySet<Category> = new Set<Category>([
  "pants",
  "jeans",
  "shorts",
  "skirt"
]);

const assertNever = (value: never): never => {
  throw new Error(`Unsupported measurement key: ${value}`);
};

const isLowerBodyCategory = (category: Category): boolean => LOWER_BODY_CATEGORIES.has(category);

const directionText = (diff: number, larger: string, smaller: string, same: string): string => {
  if (diff > 0) return larger;
  if (diff < 0) return smaller;
  return same;
};

const buildUpperBodyImpact = (row: MeasurementRow): string => {
  switch (row.key) {
    case "total_length":
      return directionText(
        row.diff,
        "밑단이 평소보다 더 내려와 허리와 골반 윗부분을 덮는 비율로 보일 수 있고, 팔을 들거나 앉을 때도 밑단이 따라 올라가는 느낌은 줄어듭니다.",
        "밑단이 평소보다 빨리 끝나는 쪽이라 팔을 들거나 앉았을 때 허리선이 드러나는 연출이 나올 수 있습니다.",
        "밑단 위치가 익숙한 기준과 가까워 평소 상의와 비슷한 상하 비율을 유지하기 쉽습니다."
      );
    case "shoulder_width":
      return directionText(
        row.diff,
        "어깨선이 바깥쪽으로 이동해 상체가 한 단계 더 편안해 보일 수 있고, 팔을 앞으로 뻗거나 가방을 멜 때도 어깨 주변 공간이 남기 쉽습니다.",
        "어깨선이 몸에 더 가깝게 자리해 단정한 인상은 나지만, 팔을 올리거나 앞으로 모을 때 당김을 먼저 느낄 수 있습니다.",
        "어깨선 위치가 익숙한 기준과 비슷해 상체 실루엣과 팔 움직임의 시작점이 크게 달라지지 않습니다."
      );
    case "chest_width":
      return directionText(
        row.diff,
        "몸통 앞뒤에 공기가 더 남아 얇은 이너를 단독으로 입을 때는 달라붙지 않는 볼륨이 보이고, 도톰한 이너를 겹쳐 입으면 그 여유가 먼저 사용됩니다.",
        "가슴과 등 쪽 공간이 줄어들어 팔을 앞으로 뻗거나 오래 앉아 있을 때 몸통에서 타이트함을 느낄 가능성이 있습니다.",
        "몸통 폭이 평소 기준과 가까워 단독 착용과 가벼운 이너 레이어드 모두에서 익숙한 여유를 기대하기 쉽습니다."
      );
    case "sleeve_length":
      return directionText(
        row.diff,
        "소매 끝이 손목을 지나 손등 일부를 덮는 연출이 나올 수 있어, 팔을 내렸을 때 루즈한 인상이 더해집니다.",
        "손목선이 더 드러나는 길이라 시계나 액세서리는 잘 보이지만, 팔을 뻗으면 소매가 더 위로 올라간 느낌이 날 수 있습니다.",
        "소매 끝이 평소와 비슷한 손목 위치에 머물러 손을 덮거나 손목이 드러나는 정도가 크게 바뀌지 않습니다."
      );
    case "waist_width":
      return directionText(
        row.diff,
        "허리와 밑단 주변의 공간이 늘어 상의를 넣어 입지 않을 때도 몸통이 직선적으로 떨어질 수 있습니다.",
        "허리와 밑단이 몸에 더 가까워져 움직일 때 상의가 말려 올라가거나 복부 주변의 밀착감을 느낄 수 있습니다.",
        "허리와 밑단 주변의 여유가 평소 기준과 가까워 상의의 떨어지는 선이 익숙하게 유지됩니다."
      );
    case "hip_width":
      return directionText(
        row.diff,
        "골반을 덮는 밑단 주변에 공간이 더 생겨 상의를 밖으로 빼 입었을 때 실루엣이 부드럽게 떨어질 수 있습니다.",
        "골반을 지나는 밑단이 더 가까워져 앉거나 걸을 때 상의가 위로 말리는 느낌이 평소보다 빨리 생길 수 있습니다.",
        "골반을 지나는 밑단의 여유가 비슷해 상의를 밖으로 빼 입었을 때의 마무리감이 익숙합니다."
      );
    case "rise":
      return "상의에서 라이즈는 일반적인 핵심 비교 부위가 아니므로, 이 값은 단독 결론보다 실제 착용 사진의 허리선 위치와 함께 확인하는 편이 좋습니다.";
    case "outseam":
      return "상의에서 아웃심은 일반적인 핵심 비교 부위가 아니므로, 이 값은 단독 결론보다 실제 착용 사진의 전체 길이와 함께 확인하는 편이 좋습니다.";
    default:
      return assertNever(row.key);
  }
};

const buildLowerBodyImpact = (row: MeasurementRow): string => {
  switch (row.key) {
    case "waist_width":
      return directionText(
        row.diff,
        "허리 밴드나 버튼을 잠근 뒤 남는 공간이 늘어 벨트 없이 입을 때는 흘러내림 여부를 확인할 필요가 있습니다.",
        "허리선이 몸에 더 가깝게 잡혀 서 있을 때보다 앉거나 식사 뒤에 압박감이 먼저 느껴질 수 있습니다.",
        "허리선의 여유가 평소 기준과 가까워 벨트 사용 여부와 착용 위치를 크게 바꾸지 않아도 됩니다."
      );
    case "hip_width":
      return directionText(
        row.diff,
        "힙과 허벅지 윗부분에 공간이 남아 걸을 때 하의가 몸을 따라 흐르는 느낌이 더해질 수 있습니다.",
        "힙과 허벅지 윗부분의 공간이 줄어 앉거나 계단을 오를 때 원단 당김이 평소보다 먼저 느껴질 수 있습니다.",
        "힙과 허벅지 윗부분의 여유가 비슷해 걷고 앉을 때의 볼륨감이 익숙한 수준에 가깝습니다."
      );
    case "rise":
      return directionText(
        row.diff,
        "앞뒤 밑위가 더 길어 허리선이 상대적으로 높거나 여유 있게 자리할 수 있고, 앉을 때 허리 뒤가 끌리는 느낌은 줄어들 수 있습니다.",
        "앞뒤 밑위가 더 짧아 허리선이 낮게 자리하거나 앉을 때 허리와 골반 사이의 당김을 더 빨리 느낄 수 있습니다.",
        "밑위 깊이가 평소 기준과 가까워 허리선 위치와 앉았을 때의 착용감이 크게 달라지지 않습니다."
      );
    case "outseam":
      return directionText(
        row.diff,
        "밑단이 신발 위에서 더 길게 머물 수 있어 스니커즈나 부츠와 맞출 때 밑단이 쌓이는 정도를 확인하는 편이 좋습니다.",
        "밑단이 발목 쪽에서 더 빨리 끝날 수 있어 앉거나 걸을 때 양말과 신발 윗부분이 평소보다 더 드러날 수 있습니다.",
        "밑단이 신발 위에서 머무는 길이가 평소와 가까워 즐겨 신는 신발과의 비율을 유지하기 쉽습니다."
      );
    case "total_length":
      return directionText(
        row.diff,
        "하의의 세로 비율이 더 길어져 쇼츠나 스커트라면 다리 노출이 줄고, 긴 하의라면 신발 위에서의 마무리 길이가 길어질 수 있습니다.",
        "하의의 세로 비율이 더 짧아져 쇼츠나 스커트라면 다리 노출이 늘고, 긴 하의라면 발목 쪽이 더 드러날 수 있습니다.",
        "하의의 세로 비율이 평소 기준과 가까워 다리 노출과 신발 위 마무리의 균형이 익숙합니다."
      );
    case "shoulder_width":
    case "chest_width":
    case "sleeve_length":
      return "하의에서 이 부위는 일반적인 핵심 비교 항목이 아니므로, 이 값만으로 착용감을 단정하지 말고 허리·힙·밑위·기장 수치를 우선 확인하는 편이 좋습니다.";
    default:
      return assertNever(row.key);
  }
};

export const getGarmentCategoryLabel = (category: Category): string => CATEGORY_LABELS[category];

export const getFitTypeLabel = (fitType: FitType): string => FIT_TYPE_LABELS[fitType];

export const buildGarmentNarrativeContext = (profile: GarmentProfile) => ({
  category: profile.category,
  categoryLabel: getGarmentCategoryLabel(profile.category),
  fitType: profile.fitType,
  fitTypeLabel: getFitTypeLabel(profile.fitType),
  bodyArea: isLowerBodyCategory(profile.category) ? "하체" : "상체"
});

export const buildMeasurementWearerImpact = (
  row: MeasurementRow,
  profile: GarmentProfile
): string => isLowerBodyCategory(profile.category)
  ? buildLowerBodyImpact(row)
  : buildUpperBodyImpact(row);

export const buildMaterialAndLayeringCaution = (profile: GarmentProfile): string =>
  isLowerBodyCategory(profile.category)
    ? "같은 실측이라도 원단의 두께와 신축성에 따라 앉고 걸을 때의 체감 여유가 달라질 수 있으니, 상품 소재 정보를 함께 확인하세요."
    : "같은 실측이라도 원단의 두께와 단독·레이어드 착용 여부에 따라 실제로 남는 여유가 달라질 수 있으니, 상품 소재와 착용 계획을 함께 확인하세요.";

export const buildEverydayFitLens = (profile: GarmentProfile): string =>
  isLowerBodyCategory(profile.category)
    ? "하의는 거울 앞의 정면 실루엣뿐 아니라 앉기와 보폭에서의 여유까지 함께 맞아야 일상에서 편하게 입을 수 있습니다."
    : "상의는 서 있을 때의 폭뿐 아니라 팔을 들고 앞으로 뻗을 때 어깨·가슴·소매가 어떻게 따라오는지까지 함께 봐야 합니다.";

export const buildFitTradeoffLens = (profile: GarmentProfile): string =>
  isLowerBodyCategory(profile.category)
    ? "하의에서는 허리선에 남는 여유와 밑단 길이 중 무엇을 더 중요하게 보는지에 따라 다음 후보를 다시 비교할 수 있습니다."
    : "상의에서는 어깨선의 여유와 밑단·소매 길이 중 무엇을 더 중요하게 보는지에 따라 다음 후보를 다시 비교할 수 있습니다.";
