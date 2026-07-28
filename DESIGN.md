# Coordit iOS Design System

## 1. Atmosphere & Identity

Coordit is a precise, calm fashion-fit tool. Its signature is deep navy chrome framing bright, lightly textured work surfaces. Gmarket Sans carries navigation, readable interface copy, and primary actions; expressive display type is reserved for non-interactive branding, selected data-display moments, and the Home `MY CLOSET` branded entry.

## 2. Color

The executable source of truth is `coordit/CoorditDesignTokens.swift` and `coordit/Main01DesignTokens.swift`.

| Role | Swift token | Value | Usage |
| --- | --- | --- | --- |
| App surface | `CoorditDesignTokens.ColorToken.appBackground` | RGB 247, 248, 248 | Screen background |
| Chrome / ink | `CoorditDesignTokens.ColorToken.ink` | RGB 0, 12, 64 | Navigation, primary actions, key text |
| Panel | `CoorditDesignTokens.ColorToken.panel` | RGB 252, 253, 254 | Cards and title bars |
| Field | `CoorditDesignTokens.ColorToken.field` | RGB 245, 247, 252 | FitLab controls |
| Closet field | `CoorditDesignTokens.ColorToken.closetField` | RGB 242, 244, 248 | Closet controls |
| Muted text | `CoorditDesignTokens.ColorToken.muted` | RGB 126, 132, 146 | Secondary copy |
| Loading sparkle | `CoorditDesignTokens.ColorToken.loadingSparkle` | RGB 246, 215, 122 | Orbit loading indicator sparkle |
| Positive / negative | `green`, `red`, `danger` | Token-defined | Fit direction and destructive states |

Fit-report comparison semantics are fixed: `red` means smaller/tighter than the reference profile, `blue` means larger/roomier, and `green` means aligned with the reference. These colors never represent recommendation quality.

New shared UI must reference these tokens. Feature-specific gradients already present in the app may retain their local stops until a separate consolidation is approved.

## 3. Typography

All text uses `CoorditTypography`; bundled PostScript names are registered by the app.

| Level | Font | Design size | Tracking | Usage |
| --- | --- | ---: | ---: | --- |
| Feature title | Gmarket Sans Bold | 22 pt | +1.5 pt | FitLab, Closet, and their child-page title bars |
| Section title | Gmarket Sans Bold | 18–20 pt | 0 | Major content sections |
| Body | Gmarket Sans Medium | 12–15 pt | 0 | Controls and explanatory copy |
| Caption | Gmarket Sans Light/Medium | 9–12 pt | 0 | Hints and metadata |
| Display | Climate Crisis KR | 17–23 pt | Screen-specific | Non-interactive branding, section labels, and selected data displays |
| Measurement | Mona12 | 10–17 pt | 0 | Numeric fashion measurements |

Text scales through SwiftUI relative text styles. Feature titles use `.headline` as their Dynamic Type reference.

## 4. Spacing & Layout

- Baseline canvas: 402 pt wide, scaled by `CoorditResponsiveMetrics`.
- Shared feature content top: 115 design pt inside `CoorditScreenScaffold`.
- Feature horizontal inset: 16 design pt.
- Feature title bar: 60 design pt tall, 29 design pt internal horizontal padding, 18 design pt icon-to-title spacing, 7 design pt corner radius.
- General spacing follows 4 pt intent where practical; image-derived legacy layouts may use measured design values through `metrics.value(_:)`.
- Bottom navigation remains owned by `CoorditScreenScaffold` and `Main01DesignTokens`.

## 5. Components

### Feature title bar

- **Structure**: full-width plain `Button` containing a leading bold `chevron.left`, the uppercase title, and a trailing spacer.
- **Variants**: title text and back action only; visual metrics are shared across FitLab and Closet.
- **Spacing**: 25 pt icon, 18 pt gap, 29 pt horizontal padding, 60 pt height, 7 pt radius.
- **States**: default and native pressed state from `Button`; no loading or disabled state.
- **Accessibility**: the entire bar is tappable and Dynamic Type is relative to `.headline`. Feature wrappers supply stable labels: FitLab uses “{title} 뒤로가기”, while Closet retains its existing visible-title label.
- **Motion**: none; navigation feedback is the destination screen change.
- **Layout**: full-width cluster within the feature's 16 pt page inset.

### Screen scaffold

- **Structure**: shared background, top chrome/header, feature content, and bottom navigation.
- **Variants**: selected tab follows `CoorditFrameRoute.selectedTab`.
- **Accessibility**: each routed screen exposes a stable `coordit-screen-*` identifier.

### Primary feature button

- **Structure**: full-width Gmarket Sans Bold label over the shared solid ink surface. Existing feature-specific height, width, and corner radius remain unchanged.
- **States**: default and native pressed state; feature flows separately define disabled/loading behavior where applicable.
- **Accessibility**: visible text supplies the label and Dynamic Type remains readable.
- **Styling**: no Climate Crisis type, gradient fill, or decorative shadow. This applies to FitLab primary actions and Closet primary actions including the total-score action.

### Home Closet branded entry

- **Structure**: left-aligned `MY CLOSET` Climate Crisis label on the original pale vertical gradient.
- **Geometry**: fixed 361 × 43 design-pt frame, 10 pt corner radius, 12 pt leading label inset, and the original restrained shadow.
- **Scope**: this is a Home feature-entry brand surface, not part of the solid primary-action button family.

### Content action buttons

- **Structure**: Gmarket Sans Bold label on either the solid ink primary surface or the solid placeholder secondary surface.
- **Geometry**: 48 pt minimum height and 7 pt corner radius. Buttons sharing one horizontal row divide the available width equally; vertically adjacent decision buttons both occupy the full content width.
- **States**: primary, secondary, pressed, and disabled. Pressed feedback uses opacity only; disabled actions remain visible at reduced opacity.
- **Accessibility**: labels may wrap to two lines, retain a 48 pt touch target, and scale relative to `.headline`.
- **Scope**: replaces content-area `.bordered` and `.borderedProminent` controls. Native alert, sheet-toolbar, keyboard-toolbar, and other system-owned controls retain platform styling.

### Global fit analysis notice

- **Structure**: top-aligned overlay banner over the current route, using the shared ink surface and `GlobalNoticeMetrics`.
- **States**: running, completed, and failed; hiding a running notice does not cancel its background analysis.
- **Interaction**: every state can be dismissed with an upward swipe or the named accessibility action. A completed report opens when tapped.
- **Lifecycle**: starting analysis shows the running notice. Completion or failure always presents a new notice even if the running notice was dismissed.
- **Motion**: an upward drag tracks the finger and dismissal exits toward the top with opacity; Reduce Motion uses opacity only.
- **Accessibility**: each state retains a stable identifier and announces that an upward swipe dismisses the notice.

### Orbit loading indicator

- **Structure**: the existing mannequin and orbit artwork are layered with one independent sparkle that travels along the tilted ring.
- **Variants**: FitLab uses report-generation copy and exposes retry feedback; Closet uses owned-garment registration copy.
- **Motion**: while work is active, the sparkle completes a steady elliptical orbit in 1.8 seconds. Reduce Motion keeps the sparkle stationary.
- **Accessibility**: mannequin, ring, and sparkle are decorative; the surrounding loading screen owns the operation label and stable identifier.

### Fit report decision actions

- **Structure**: the result closes with a primary `히스토리에 추가` action, a secondary `확인하기` action, and an explicit persistence guide.
- **States**: before saving, the guide states that `확인하기` returns to FitLab without saving. After saving, the guide states that the report is available from FitLab and Home history.
- **Interaction**: saving persists the full report snapshot; confirming never writes history and returns to the FitLab input.
- **Accessibility**: both actions use stable identifiers and retain at least a 44 pt touch target.

### Fit report analysis system

- **Structure**: recommendation hero, full-width annotated mannequin, all-size score comparison, centered-zero measurement difference chart, overall verdict, recommendation rationale, part-by-part analysis cards, and purchase checks.
- **Size score comparison**: every available size uses a shared 0–100 horizontal scale. The recommended size uses solid `ink`; alternatives use the existing `blue` token at reduced opacity. The chart must never hide lower-scoring candidates.
- **Difference chart**: the midpoint is always 0 cm. Negative bars extend left in `red`, positive bars extend right in `blue`, and aligned values use a compact `green` center mark. Each row also states reference, product, and signed difference values.
- **Mannequin annotations**: pills show the measurement name and signed centimeter difference directly; raw plus/minus glyphs without a measurement label are prohibited.
- **Narrative hierarchy**: major narrative sections use visible English eyebrow labels plus large Korean headings. Each body-part analysis occupies its own bordered panel with a semantic color rail.
- **Content**: confidence, feedback reliability, and the number of reference garments are not presented as quality judgments. The report explains every available measured body part and then synthesizes why the recommended size is the most balanced candidate.
- **Accessibility**: charts expose one stable element per size or measurement with the same numeric content shown visually. Color is always accompanied by text and direction.

### Home fit history preview

- **Structure**: the Home FitLab card renders at most the two most recently saved report snapshots.
- **States**: an empty state replaces sample content when no report has been saved.
- **Interaction**: selecting a preview opens that exact snapshot in the FitLab history detail screen.
- **Data**: Home and FitLab read the same app-scoped history coordinator; previews are never hard-coded samples.

## 6. Motion & Interaction

- Navigation is explicit enum state through `CoorditFrameRoute` and `onRouteChange` callbacks.
- A root feature title bar returns to Home (`.main04`); a nested feature title bar returns to its feature root unless that screen defines a closer parent.
- Motion must communicate state change and respect Reduce Motion. Do not add decorative animation to title bars.
- The orbit loading motion runs only while an operation is active and never changes layout.
- Interactive controls retain at least a 44 pt effective touch target.
- Adjacent content actions use matching heights and alignment; an `HStack` gives each sibling the same flexible width.

## 7. Depth & Surface

Strategy: mixed, following the existing iOS visual language.

- The app shell uses layered navy-to-surface gradients.
- Panels use the shared panel token with restrained radii.
- Feature title bars use a flat panel surface without a feature-specific shadow so all feature families align.
- Primary calls to action use the solid ink token without a decorative shadow. Gradients remain available for chrome, imagery, and non-primary feature surfaces.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Dynamic Type must remain enabled through relative SwiftUI text styles.
- Text and icons must preserve readable contrast against panel and chrome surfaces.
- Interactive elements need stable accessibility labels/identifiers and at least 44 pt effective touch targets.
- Key navigation flows must remain operable through VoiceOver-discoverable buttons.

### Accepted Debt

None accepted for this change. Existing feature-specific token duplication outside the shared title bar is observed but not changed by this task.
