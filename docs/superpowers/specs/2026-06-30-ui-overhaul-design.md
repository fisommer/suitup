# SuitUp UI overhaul — design spec

**Date:** 2026-06-30
**Companion to:** `IMPLEMENTATION.md` (post-Phase 9)
**Status:** approved direction; ready for an implementation plan

## Context

SuitUp v0 ships as a functional but visually generic SwiftUI app. Today: zero custom fonts, no centralized palette, ad-hoc corner radii and spacing, `Color(.secondarySystemBackground)` gray rectangles everywhere, default `Form` chrome, stock `TabView`. It works; it doesn't *feel* like anything.

The overhaul applies a single coherent aesthetic — soft, friendly minimalism with editorial warmth — across the entire app. Reference language: warm cream canvas, near-black primary actions, honey gold (#FFCB74) used sparingly as an accent (FAB, focus rings, active tab indicator, small status badges), Fraunces serif for display moments + Inter for everything functional. The result should feel modern, chic, and classy — closer to the visual posture of Notion / Threads / Aesop than to default iOS.

Outcome: a real design system (tokens + components), every existing screen re-skinned to use it, and a codebase where future visual polish is a one-file change instead of a tour through every view.

## Decisions locked in with Finn

- **Aesthetic anchor:** soft / friendly minimalism with editorial DNA. Closer to Notion / Threads / Aesop than to Linear / Vercel.
- **Dark mode:** light-first, dark is auto-derived (system iOS handling). Not bespoke-tuned in this round.
- **Accent color:** Honey `#FFCB74`. **Never** on primary buttons. Reserved for FAB +, tab active underline, focus rings, link text, small status badges, edit-link text.
- **Button pairing rule:** primary filled + secondary outlined must share the same color family. No gold-outlined secondary next to a near-black primary. Cross-color pairings are forbidden by component contract.
- **Typography:** Fraunces (variable, opsz axis) for display + tab titles + item hero name; Inter (variable) for body, UI, captions, labels. Both fonts bundled in the app (~640KB total).
- **Icons:** SF Symbols, line-weight (`.light` / `.regular`) throughout. Active tab can use the filled variant. No mixing weights.
- **Splash / onboarding / login:** **skipped** (SuitUp is personal-app, no accounts).
- **Scope:** full overhaul — build design system, refactor every existing screen. Doesn't touch flow logic, only visuals.
- **Approach:** design tokens + reusable components + screen-by-screen refactor. Not tokens-only and not components-only.

## Design tokens

### Color

**Neutrals (warm, paired with the gold — cool grays would clash):**

| Token | Hex | Used for |
|---|---|---|
| `Canvas` | `#FBF8F2` | Main background. Subtle warm cream. |
| `Surface` | `#FFFFFF` | Cards, sheets, raised surfaces. |
| `SurfaceMuted` | `#F4F0E8` | Image placeholders. Replaces today's cold `secondarySystemBackground`. |
| `Border` | `#E8E3DA` | Hairlines, dividers, input borders. |
| `InkPrimary` | `#1A1410` | Primary text, primary button bg. Warm near-black, NOT pure black. |
| `InkSecondary` | `#6B6358` | Secondary text (subtitles, metadata). |
| `InkTertiary` | `#8A8378` | Labels, hints, captions, inactive tab text. |

**Accent (used sparingly):**

| Token | Hex | Used for |
|---|---|---|
| `Accent` | `#FFCB74` | FAB +, tab active indicator, focus rings. Your honey. |
| `AccentDeep` | `#B88838` | Gold-on-white text/icons that need contrast. |
| `AccentSurface` | `#FFF3DC` | Background for accent tags & focus-ring halo. |

**Semantic (muted — they don't compete with the gold):**

| Token | Hex | Used for |
|---|---|---|
| `Warning` | `#F5A623` | Crawler warning banners, "needs attention" states. |
| `Success` | `#5BA678` | Saved toasts, matched badges in recreate. |
| `Danger` | `#C76B5C` | Destructive buttons. Muted terracotta, not aggressive red. |

**Dark mode:** every color token is implemented via `UIColor(dynamicProvider:)` wrapped in a SwiftUI `Color`, returning a hand-picked dark hex when `userInterfaceStyle == .dark`. Not "auto-derived by iOS semantic colors" — those would pick wrong defaults for `#FBF8F2`. Dark hexes are taken once at implementation time without separate tuning passes. Defaults below:

| Token | Light | Dark |
|---|---|---|
| `Canvas` | `#FBF8F2` | `#16110D` |
| `Surface` | `#FFFFFF` | `#1F1A14` |
| `SurfaceMuted` | `#F4F0E8` | `#28221B` |
| `Border` | `#E8E3DA` | `#3A332B` |
| `InkPrimary` | `#1A1410` | `#F5EFE3` |
| `InkSecondary` | `#6B6358` | `#A89F92` |
| `InkTertiary` | `#8A8378` | `#75695C` |
| `Accent` | `#FFCB74` | `#FFCB74` (unchanged — still reads warm on dark) |
| `AccentDeep` | `#B88838` | `#E2B25A` |
| `AccentSurface` | `#FFF3DC` | `#3D2F12` |
| `Warning` | `#F5A623` | `#F5A623` |
| `Success` | `#5BA678` | `#74C091` |
| `Danger` | `#C76B5C` | `#D88474` |

### Typography

| Token | Font | Size | Weight | Line | Tracking | Used for |
|---|---|---|---|---|---|---|
| `suDisplay` | Fraunces (opsz 144) | 44 | 500 | 1.05 | −2% | Rare — empty-state hero, optional splash |
| `suTitle` | Fraunces (opsz 72) | 30 | 500 | 1.15 | −1.5% | Tab header ("Closet"), item detail hero name |
| `suSectionTitle` | Fraunces (opsz 36) | 22 | 500 | 1.25 | −1% | Occasional serif section moments |
| `suHeadline` | Inter | 17 | 600 | 1.3 | −1% | Primary buttons, card titles, modal headers, list row titles |
| `suBody` | Inter | 15 | 400 | 1.5 | 0 | Default text, field values, descriptions |
| `suCaption` | Inter | 13 | 400 | 1.4 | 0 | Tag chips, brand+price, item count, footer hints |
| `suLabel` | Inter | 11 | 600 | 1.4 | +8% (UPPERCASE) | Above rails & form fields (e.g. "TOPS · 12") |

Both fonts bundled (Fraunces ~300KB, Inter ~340KB). Both variable.

### Spacing — 4-point grid

| Token | Value | Used for |
|---|---|---|
| `spaceXS` | 4 pt | Inside chips, icon-to-label gap |
| `spaceSM` | 8 pt | Between tag chips, tight grid items |
| `spaceMD` | 12 pt | Inside cards, between rail tiles, form field padding |
| `spaceLG` | 20 pt | Screen edge padding, between section blocks |
| `spaceXL` | 32 pt | Between tab title and first rail, large vertical breathing |
| `space2XL` | 48 pt | Empty-state hero padding |

### Corner radius

| Token | Value | Used for |
|---|---|---|
| `radiusXS` | 6 pt | Small chips, rectangular tag pills |
| `radiusSM` | 10 pt | Input fields, small thumbnails |
| `radiusMD` | 14 pt | Rail tiles, buttons, cards |
| `radiusLG` | 20 pt | Hero images, item detail photo, sheets |
| `radiusPill` | ∞ | FAB, tag chips, status dots |

### Elevation

| Token | Shadow | Used for |
|---|---|---|
| `elev0` | none (1px Border only) | Flush surfaces |
| `elev1` | `0 1px 2px rgba(20,15,5,0.04) + 1px inset Border` | Cards on Canvas |
| `elev2` | `0 4px 16px rgba(20,15,5,0.06)` | Sheets, modals |
| `elev3` | `0 12px 32px rgba(20,15,5,0.10)` | Floating popovers, toasts |
| `elevAccent` | `0 6px 20px rgba(255,203,116,0.35)` | FAB + only |

### Motion

| Token | Duration | Curve | Used for |
|---|---|---|---|
| `motionFast` | 120 ms | easeOut | Button press scale, toggle flips |
| `motionStandard` | 280 ms | easeOut | Sheet present/dismiss, toast appear, tab indicator slide |
| `motionSlow` | 440 ms | easeOut | Confirm sheet hand-off, success bloom |

Single curve everywhere: `cubic-bezier(0.2, 0, 0.0, 1.0)` — SwiftUI's `.smooth`. No parallax. No celebratory animations. No skeleton shimmer.

## Component library

12 SwiftUI components. Screens become assembly, not styling.

1. **`SUButton`** — `.primary`, `.secondary`, `.tertiary`, `.destructive`, `.disabled`. Pairing rule enforced by docs. Scale-0.96 press feedback.
2. **`SUTextField`** — label + field + optional error. States: default, focused (honey ring), with-value, error.
3. **`SUTag`** — pill chip. Variants: `.neutral`, `.accent`, `.success`, `.warning`. Display-only — never a button.
4. **`SURailTile`** — closet rail tile. Image fill, bottom-left label, optional `.selected` (2.5pt gold inner border).
5. **`SUItemCard`** — horizontal card: thumbnail + title + caption. Used by Recreate history, Wishlist.
6. **`SUOutfitCard`** — square-ish 2-col grid card: image-dominant, optional caption row underneath. Used by Outfits grid.
7. **`SUBanner`** — inline non-blocking message. Variants: `.warning`, `.success`, `.info`. Has the crawler warning treatment.
8. **`SUEmptyState`** — icon + serif title + body copy + primary action. Replaces today's `ContentUnavailableView`.
9. **`SUTabBar`** — floating pill bar. 4 nav tabs + center honey FAB. Active tab gets gold underline (matchedGeometryEffect for the slide).
10. **`SUToast`** — floating confirmation pill. Dark warm-ink bg + gold dot. Replaces today's `SavedToast`.
11. **`SUSectionHeader`** — label + optional trailing action ("See all →").
12. **`SUSheet`** — consistent sheet chrome (handle bar, padding, dismiss-on-drag config). Wraps every modal in the app.

### Pairing rule (codified)

`SUButton` initializer takes a `style: ButtonStyle` enum. Two-button rows are constructed via `SUButtonGroup(primary:, secondary:)` which constrains both to the same color family. There is no way to render a gold-outlined secondary next to a near-black primary — the API doesn't allow it.

## File structure

```
SuitUp/SuitUp/
  DesignSystem/                  (NEW)
    Theme.swift                  — color + radius + spacing + elevation constants
    Typography.swift             — font extensions, .suTitle / .suBody / etc.
    Motion.swift                 — duration + curve constants
    Components/                  (NEW)
      SUButton.swift
      SUTextField.swift
      SUTag.swift
      SURailTile.swift
      SUItemCard.swift
      SUOutfitCard.swift
      SUBanner.swift
      SUEmptyState.swift
      SUTabBar.swift
      SUToast.swift
      SUSectionHeader.swift
      SUSheet.swift
    Fonts/                       (NEW)
      Fraunces-VariableFont.ttf
      Inter-VariableFont.ttf
  Features/
    (all existing views refactored to consume the design system)
```

Existing views will be edited in-place. No file structure changes outside of the new `DesignSystem/` directory.

## Screen-by-screen application

Each screen below lists what the overhaul changes. Functional behavior is unchanged.

### Closet tab (`Features/Closet/ClosetTabView.swift`, `ClosetRailsView.swift`)
- Header becomes serif `suTitle` "Closet" + right-aligned settings & + icons (light SF Symbols).
- Each rail gets an `SUSectionHeader` ("TOPS · 12") with optional "See all".
- Rail tiles → `SURailTile` (replaces the inline tile in `ClosetRailsView`). Selected stroke now uses `Accent` from theme.
- Image placeholders use `SurfaceMuted` (warm) instead of `secondarySystemBackground` (cool).
- Empty state → `SUEmptyState` with serif title + primary `SUButton`.

### Item detail (`Features/Closet/ItemDetailView.swift`)
- Hero photo full-width, `radiusLG` corners, soft gradient overlay.
- Item name in `suTitle` (serif). Brand + price as `suCaption` underneath.
- Attribute tags (`Summer`, `Loose`, `Casual`, `Linen`) become `SUTag.neutral`, with one `SUTag.accent` highlight.
- Action row: `SUButtonGroup` with "Style this piece" (primary near-black) + "Edit details" (secondary near-black outline). No gold-outline.

### Item confirm (`Features/ItemCapture/ItemConfirmView.swift`)
- Hero photo at top, `radiusMD`.
- Existing crawl warnings row → `SUBanner.warning`.
- Every form row gets the new `SUTextField` (uppercase label above + field below).
- Bottom primary button is `SUButton.primary` ("Add to closet"), full-width, sticky.

### References tab (`Features/References/ReferencesTabView.swift`)
- Pinterest-style grid stays. Spacing bumps to `spaceSM` (was 4 — too tight).
- Outer padding `spaceLG`.
- Image corners get `radiusSM` (instead of clipped square).
- Empty state → `SUEmptyState`.
- `AddReferenceSheet` form uses `SUTextField`, `SUButton`.

### Outfits tab (`Features/Outfits/OutfitsTabView.swift`)
- Grid spacing standardizes to `spaceMD`.
- Each cell becomes an `SUOutfitCard` (a sibling to `SUItemCard`, sized for 2-col grid: ~1:1 ratio, image-dominant, optional caption row underneath, no thumbnail-beside-text layout).
- Empty state → `SUEmptyState`.
- Manual builder sheet adopts `SUSheet` chrome.

### Recreate tab (`Features/Recreate/RecreateTabView.swift`)
- The current plain `List` becomes a `ScrollView` with `SUItemCard` rows (consistent with Outfits/Closet).
- Wishlist section → `SUSectionHeader` + cards.
- History section → same.
- `NewRecreateSheet` form uses `SUTextField`, `SUButton`. Analyze button is `SUButton.primary`.
- `RecreateResultView`: tag chips for matched/missing become `SUTag.success` / `SUTag.warning`.

### Settings (`Features/Settings/SettingsView.swift`)
- Replaces stock `Form` with hand-built sections using `SUSectionHeader` and `SUTextField`.
- "Save key" / "Replace" / "Delete" / "Export" / "Clear all" all become `SUButton` variants (Clear All is `.destructive`).
- API-key status row uses `SUBanner.success` when key is stored.

### Tab bar (root)
- `RootTabView` gets a new `SUTabBar` overlay positioned bottom-center.
- 4 nav tabs + central honey FAB. Active tab indicator slides on selection.
- FAB tap presents `AddItemSourceSheet` (existing).

### Sheets / share extension
- Share extension `ShareRouterView` already uses a similar layout. Wrap its action buttons in `SUButton.primary` / `.secondary` (same color family).
- Inbox-presented sheets (`AddReferenceSheet`, `NewRecreateSheet`, `PasteURLView`) inherit `SUSheet` chrome.

## Out of scope

- **Behavioral changes.** No flow logic touched — only visual layer.
- **Splash / onboarding screens.** Personal app, no accounts.
- **Dark-mode bespoke tuning.** System iOS auto-derivation only.
- **Custom icons.** SF Symbols throughout.
- **Animations beyond the three motion tokens** (no parallax, no skeleton shimmer, no confetti).
- **New features.** This is pure UI overhaul; the v0 feature set is unchanged.
- **CloudKit / multi-device sync.** Already deferred to v1 per the project spec.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Font bundle weight ~640KB feels heavy | Variable fonts, both small for what they are. Accepted. |
| Custom font loading delay on cold launch | Register in `Info.plist`, load synchronously at app start. UIKit/SwiftUI handles this transparently. |
| `SUTabBar` overlay competing with iOS system gestures | Floating bar uses `safeAreaInset(edge: .bottom)` not absolute positioning. |
| `matchedGeometryEffect` for tab indicator can flicker if NavigationStack pushes during tab change | Test on physical device; if real, fall back to fixed-width per tab + offset animation. |
| Refactoring every screen touches a lot of files at once | Plan slices the refactor into one screen per commit, in dependency order (design system → tab bar → Closet → others). |
| Dark mode looks unrefined when auto-derived | Acceptable for v0; flagged as a v1 polish item. |

## Verification

**Design system foundation:**
- All token values match this spec exactly (typography sizes, color hexes, spacing).
- `Theme.swift` colors render correctly in light AND dark mode preview.
- Both fonts load on simulator and physical device (verify `UIFont(name:)` returns non-nil).
- Each of the 11 components renders correctly in its own `#Preview` block.

**Per-screen:**
- Build succeeds on both schemes (SuitUp, SuitUpShareExtension).
- All 4 main tabs visually match the direction set in the brainstorm mockups.
- No `Color(.secondarySystemBackground)` or `Color(.systemBackground)` references remain in `Features/` (grep).
- No raw `.font(.title)` / `.font(.headline)` / etc. in `Features/` — every font call goes through `.suTitle`, `.suHeadline`, etc.
- No raw `cornerRadius: <number>` calls — every corner uses `radiusXS/SM/MD/LG/Pill`.
- No raw `padding(<number>)` for spacing values 4 / 8 / 12 / 20 / 32 / 48 — those use spacing tokens.
- Manual smoke test: add an item via photo → confirm sheet styled correctly. Style a piece → suggestions sheet looks right. Save an outfit → toast appears in new style.

**Pairing rule enforcement:**
- `SUButtonGroup` doesn't compile when given two different style families. (Static check via the type system.)

**Regression:**
- Existing test suite passes (worker `npm test`, no iOS tests yet).
- No SwiftUI runtime warnings during a full Closet → Item Detail → Style → Save flow.

## What this enables next

- The Phase 9 empty-state polish + DoD verification becomes a small "use the new components" pass instead of a full design exercise.
- Future visual changes (rebranding, a v1 dark-mode tune, seasonal accents) are one-file edits to `Theme.swift`.
- New features get visual consistency for free — building a new screen is now picking components, not picking colors.
