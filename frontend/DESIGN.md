# Coordit Design System

This system extracts the visual language already established by the public home screen and applies it to authenticated account journeys. Its source of truth is `src/styles/globals.css`, `src/app/page.tsx`, and the shared top navigation.

## 1. Atmosphere & Identity

Coordit feels like a quiet, considered fashion atelier rather than a generic account portal: warm paper, deep ink, and tailored editorial rhythm make personal fit data feel private and valuable. The signature is **the editorial dossier**: a cream record card framed by technical labels, serif statements, and a single walnut or obsidian information block. Account screens should feel like opening a personal wardrobe file, never a separate SaaS login.

## 2. Color

### Palette

| Role | Token | Value | Usage |
| --- | --- | --- | --- |
| Canvas | `--bg` | `var(--ivory)` | Page background |
| Raised paper | `--bg-raised` | `#FBF7EE` | Cards and forms |
| Ink | `--obsidian` | `#1C1B1A` | Primary text, decisive CTA, dark panels |
| Ink soft | `--obsidian-soft` | `#2D2A27` | Supporting dark surface |
| Walnut | `--walnut` | `#4A3826` | Editorial emphasis and selected state |
| Camel | `--camel` | `#B08A5B` | Progress, focus, measured accent |
| Linen | `--linen` | `#E8DFC9` | Quiet contrasting section |
| Primary text | `--text` | `var(--obsidian)` | Body and headings |
| Secondary text | `--text-muted` | `#6B6357` | Supporting copy |
| Quiet text | `--text-dim` | `#9A9287` | Metadata |
| Divider | `--line` | `rgba(28, 27, 26, 0.08)` | Paper-like separation |
| Strong divider | `--line-strong` | `rgba(28, 27, 26, 0.16)` | Inputs, card outlines |
| Success | `--fit-perfect` | `#5B7355` | Completed and secure states |
| Error | `--fit-tight` | `#A8423A` | Errors and destructive actions |

### Rules

- Use camel only to reveal an interaction, completion state, or measurement; it is not decoration.
- Keep primary surfaces warm. A dark panel must carry a clear purpose such as identity, privacy, or progress.
- No raw color literals are introduced in account components; each color resolves through these tokens.

## 3. Typography

| Level | Size | Font | Weight / line-height | Usage |
| --- | --- | --- | --- | --- |
| Display | `clamp(2.5rem, 7vw, 5rem)` | `--font-korean-display` | 400 / 1.02 | Account page statement |
| Page title | `clamp(2rem, 4vw, 3.5rem)` | `--font-korean-display` | 400 / 1.14 | Onboarding and My Page titles |
| Card title | 28px | `--font-korean-display` | 500 / 1.25 | Dossier cards |
| Lead | 17px | `--font-korean` | 400 / 1.7 | Explanatory copy |
| Body | 14px | `--font-korean` | 400 / 1.65 | Forms and settings |
| Caption | 12px | `--font-korean` | 500 / 1.5 | Labels and help text |
| Technical label | 10–11px | JetBrains Mono | 500 / 1.35, `0.14em` tracking | Progress, provider, metadata |

- Use Cormorant Garamond only for brief English editorial emphasis; Korean display copy remains Noto Serif KR.
- Korean display and body copy use `text-wrap: pretty`; concise labels avoid awkward one-character wraps.

## 4. Spacing & Layout

The base unit is 4px. Reuse `4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64 / 80` px for interior rhythm. Account content caps at 1200px with a two-column editorial frame on desktop: the story/progress rail and a 560–640px interactive dossier. At `768px` and below, collapse to one column, reduce page gutters to 20px, and preserve 48px minimum touch targets.

## 5. Components

### Account shell

- **Structure:** contextual wordmark, technical progress/identity rail, main paper dossier.
- **States:** loading, signed-out, signed-in, setup-required, error.
- **Accessibility:** landmarked `main`, heading hierarchy, no redirect flash while session state loads.

### Social provider button

- **Structure:** provider mark, provider label, forward affordance.
- **Variants:** Google and Apple.
- **States:** default, hover, active, focus-visible, disabled/loading, provider configuration error.
- **Accessibility:** real `button`, descriptive provider text, keyboard operable; never use an image as a button.

### Field and choice tile

- **Structure:** label, optional hint, input or radio choice, validation text.
- **States:** default, focus-visible, selected, invalid, disabled.
- **Accessibility:** programmatic labels, grouped radios with `fieldset`/`legend`, error text linked through `aria-describedby`.

### Consent row

- **Structure:** native checkbox, required/optional label, summary, legal link.
- **States:** unchecked, checked, required validation error.
- **Accessibility:** full-row label target, legal documents open as normal routes, required state is explicit in copy.

### Profile dossier and danger zone

- **Structure:** profile summary, editable identity data, account action section.
- **States:** loading, editing, saving, saved, error, logout confirmation.
- **Accessibility:** status is announced with `aria-live`; destructive action is visually and textually distinct.

## 6. Motion & Interaction

Use a 160ms `ease-out` transition for border, background, color, opacity, and transform feedback; a 220ms `cubic-bezier(0.16, 1, 0.3, 1)` transition is reserved for opening an account menu or changing onboarding steps. Press feedback may translate controls by at most 1px. No decorative motion is added. Focus states use a static camel outline, and `prefers-reduced-motion: reduce` removes non-essential transitions.

## 7. Depth & Surface

Coordit uses a **mixed paper depth** strategy: thin warm dividers establish the base hierarchy, raised paper is separated by a restrained walnut-tinted shadow, and a single obsidian panel acts as an intentional contrast anchor. Cards use the existing small radius (4–8px), avoiding generic oversized rounded rectangles or floating glass effects.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Target WCAG 2.2 AA: body text meets a 4.5:1 contrast floor and large text meets 3:1.
- Every control is keyboard reachable with a visible `:focus-visible` outline.
- Social authentication failures, form errors, and save success are announced without color as the only signal.
- Required terms and privacy consent must be accepted before submission. Optional consent defaults to off.
- Session and onboarding guard states do not expose protected product content before redirecting.

### Accepted Debt

| Item | Location | Why accepted | Owner / Exit |
| --- | --- | --- | --- |
| Provider configuration remains an environment/dashboard responsibility | Supabase Auth dashboard | OAuth client credentials and allowed redirect URLs are secret, deployment-owned settings | Configure Google and Apple providers before production launch |
