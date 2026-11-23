# Liquid Glass audit (1.6, #343 B0)

This audit decides the scope of the 1.6 interface refresh. It answers which
surfaces macOS 26 turns into Liquid Glass on its own, which custom surfaces
clash with it, and whether the main window needs a sidebar.

**Method.** The audit read the code in `src/Wallnetic` on `dev` at c498fb5 in
November 2026. Nothing was built or run.
- Rows marked *(inferred)* follow from the code and Apple's documented
  behavior, not from a screenshot.
- Every path below is relative to `src/Wallnetic/`.

**Background.**
- The app deploys to macOS 13 and is built with the Xcode 26 SDK.
- On macOS 26, standard chrome built with that SDK adopts Liquid Glass
  automatically: window toolbars, sidebars, menus, sheets, alerts and standard
  controls. Custom-drawn chrome does not.
- `glassEffect()`, `GlassEffectContainer` and the glass button styles exist only
  on macOS 26.
- `Views/Components/LiquidGlass.swift` imitates the glass look on earlier
  systems.

## Surfaces

| Surface | Standard or custom | macOS 26 *(inferred)* | macOS 13–25 |
| --- | --- | --- | --- |
| Main window title bar (`App/WallneticApp.swift:63-75`, `Views/Components/WindowChrome.swift:24-43`) | Standard `.titleBar` window, adjusted by `configureAppWindow`:<br>• `isOpaque = true` and `backgroundColor = Surface.stageFloor` (:36-37)<br>• no title separator (:41)<br>• `.fullSizeContentView` removed (:33, the #237 fix)<br>• hidden title (:28) | New title bar and window controls. There is no `NSToolbar`, so no glass toolbar forms. The title bar is an empty opaque strip above `TopNavigationBar`. | Native title bar on the opaque window background. |
| `TopNavigationBar` (`Views/Main/TopNavigationBar.swift:27-36, 129`) | Custom. A view inside `ContentView`, not a toolbar. Background: `.ultraThinMaterial` plus `Surface.glassStandard/Prominent` and a hairline. | Custom material, no system glass. It sits right under the title bar, so the window shows two stacked bars with different looks. | Reads as a blurred in-window toolbar. |
| `ContentView` shell (`Views/Main/ContentView.swift:24-75`) | Custom stack:<br>• navigation bar<br>• download progress bar<br>• desktop hint<br>• tab content<br>No sidebar or `NavigationSplitView`. | Nothing for the system to adopt. | Same. |
| Download bar and desktop hint (`ContentView.swift:355-385`) | Custom `ultraThinMaterial` with a control tint and an accent gradient. | Custom material. | Same. |
| Import toast (`ContentView.swift:113-118`) | Floating card on `.regularMaterial`. | Candidate for glass. | Material. |
| Home hero and carousels (`Views/Main/HomeView.swift:118-171, 296-311`) | Custom. Full-bleed art with gradient overlays and auto-advance (`isAutoAdvancing`). Cards use `glowCard`, buttons `neonGlow`. | No glass. Neon glows clash with the macOS 26 look. | Same. |
| Explore, Popular, Discover grids (`Views/Main/ExploreView.swift`, `PopularView.swift`, `DiscoverView.swift`) | Custom cards with `glowCard`, `neonGlow` and `staggered`. Explore uses `Carousel3DGallery` (`ExploreView.swift:205`). | Same as Home. | Same. |
| Grid and History badges (`Views/Main/WallpaperGridView.swift:228`, `Views/Main/HistoryView.swift:207, 221`) | Small `.ultraThinMaterial` badges on thumbnails. | Acceptable; optional glass. | Same. |
| Grid HUD (`Views/Main/WallpaperGridView.swift:478`) | `.liquidGlassHUD` polyfill. | Polyfill, not system glass. | As designed. |
| `WallneticSheet` (`Views/Components/WallneticSheet.swift:45-51, 75`) | Custom content in a system `.sheet`. Applies `.liquidGlass(… .prominent)`; the title is hard-coded `.white`. | The sheet is already glass, so the polyfill adds a second blur. A white title is hard to read in light appearance *(inferred)*. | As designed. |
| Other sheets: onboarding, Trim, optimized copy, packs, collections | System `.sheet` with custom content. Onboarding uses hard-coded white (`OnboardingView.swift:212-219`). | Sheet chrome becomes glass; opaque custom content may clash. | Standard. |
| Alerts | Standard `.alert`. | Automatic. | Standard. |
| Settings window (`App/WallneticApp.swift:92-100`, `Views/Main/SettingsView.swift`) | Custom `WindowGroup(id: "settings")`, not the `Settings` scene:<br>• hand-built 224 pt sidebar on `ultraThinMaterial` (:116-130)<br>• opaque backdrop with gradient and grain (:10-25) | No system sidebar glass. | As designed. |
| Menu bar menu (`WallneticApp.swift:103-109`, `Views/Main/MenuBarView.swift`) | Standard `MenuBarExtra` with `.menu` style. | System menu glass, automatic. | Native menu. |
| Dynamic Island (`Views/Main/DynamicIslandView.swift`, `Engine/OverlayWindowFactory.swift:33`) | Custom borderless panel, black fill, own shape. | Stays black to match the notch. Do not glass it. | Same. |
| Now Playing overlay (`Views/Main/NowPlayingOverlayView.swift:38-46`) | Custom floating card on `ultraThinMaterial`. | Good candidate for glass. | Material card. |

`project.yml` and the plists set no `UIDesignRequiresCompatibility` key, so the
app takes the macOS 26 design. Setting that key would opt out of Liquid Glass
for as long as the system allows. It is a fallback, not the plan.

## Conflicts on macOS 26

1. **Opaque window.** `isOpaque = true` and the custom `backgroundColor` keep
   the system from drawing a glass title bar or toolbar. These lines are part of
   the #237 fix for onboarding and the window controls. Change them only
   together with a toolbar, and re-test #237.
2. **Two bars.** `TopNavigationBar` is a hand-built toolbar under a native title
   bar, so two different bars are stacked.
3. **Double blur.** `WallneticSheet` draws the polyfill inside a sheet that is
   already glass.
4. **Hard-coded white.** Sheet titles and onboarding use hard-coded white, which
   breaks in light appearance. The forced theme from `ThemeManager` partly hides
   this. Dynamic Island white is fine, since it is always black.
5. **Settings sidebar.** It is material on an opaque backdrop, not a system
   sidebar, so it gets no Liquid Glass.
6. **Neon and glow.** `glowCard`, `neonGlow` and the accent drop shadows in
   `LiquidGlass.swift` clash with the lighter, edge-lit macOS 26 style.

## Call sites

Counted with `grep -rnF` over `*.swift`, without the definitions.

| Helper | Call sites | Where |
| --- | ---: | --- |
| `.neonGlow(` | 14 | `ContentView` 1, `HomeView` 3, `ExploreView` 2, `PopularView` 3, `DiscoverView` 3, `VideoPreviewView` 2 |
| `.glowCard(` | 5 | `HomeView`, `ExploreView`, `PopularView`, `DiscoverView`, `VideoPreviewView` |
| `.staggered(` | 5 | `HomeView` 1, `ExploreView` 2, `PopularView` 1, `DiscoverView` 1 |
| `.liquidGlass(` | 1 | `WallneticSheet.swift:45` |
| `.liquidGlassHUD(` | 1 | `WallpaperGridView.swift:478` |
| `.liquidGlassControl(` | 0 | — |
| `glassBackground`, `shimmer`, `parallaxHover`, `cardFlip` | 0 | Only defined in `StrikingEffects.swift`, so they are dead code |
| `pressEffect`, `AnimatedGradientBackground` | 0 likely | Confirm before deleting |

## Decision

**Is a `NavigationSplitView` sidebar needed now? No.**
- The main window has no sidebar to convert.
- Settings already has a working custom sidebar on every supported system.
- A split view would change navigation from tabs to a sidebar on macOS 13 as
  well, and nothing about Liquid Glass requires that.
- Revisit it as a separate redesign.

| Step | Decision | Scope |
| --- | --- | --- |
| **B1** remove neon and glow | Confirmed | 24 call sites in 6 files, plus the dead helpers in `StrikingEffects.swift`. Replace glows with a plain selection stroke or an opacity change. Keep `staggered` only where it respects Reduce Motion. |
| **B2** Library-first Home | Confirmed | `HomeView.swift:118-171, 296-311` is the only auto-rotating surface. |
| **B3** adaptive glass | Confirmed, narrower | One modifier: `glassEffect()` in `if #available(macOS 26, *)`, `LiquidGlass` otherwise. Use `GlassEffectContainer` on macOS 26 when glass elements sit next to each other. |
| **B4** menu bar menu | Confirmed | The menu is already system-styled, so this is a content trim only. |

**B3 applies glass to:**
- the Now Playing overlay card (`NowPlayingOverlayView.swift:38`);
- the import toast (`ContentView.swift:113-118`);
- the download progress bar and desktop hint (`ContentView.swift:355-385`);
- the grid HUD (`WallpaperGridView.swift:478`);
- the `TopNavigationBar` background, while it remains an in-window bar;
- optionally, thumbnail badges.

**B3 removes custom backgrounds so system glass shows through:**
- `.liquidGlass` in `WallneticSheet.swift:45`. Keep the header and footer layout,
  and use `.primary` instead of the hard-coded `.white`.
- Onboarding's hard-coded white text.

**Leave alone:**
- the Dynamic Island;
- the wallpaper and desktop windows;
- the window opacity from #237, unless a system toolbar is adopted later.

## Update after B2 (toolbar navigation)

The owner chose toolbar tabs after this audit, so B2 (#353) changed three
things recorded above:

- **`TopNavigationBar` is gone.** Home, Library and Discover are a segmented
  control in the window's system toolbar, next to Add, Settings and search.
  This resolves conflict 2, and the toolbar's controls take system glass on
  macOS 26.
- **Explore and Popular are one Library view.** Popular's order became
  Library's sort menu. `Carousel3DGallery` stays, for Library's gallery mode.
- **A now-playing bar** runs along the bottom of the window. It is a custom
  surface on `.bar` material, so it joins the B3 list in place of the
  `TopNavigationBar` background.

Conflict 1 is resolved for the main window on macOS 26. With the #237
settings the toolbar sat on a grey title-bar strip above the content. Now
`WindowChrome.configureAppWindow(_:hostsToolbar:)` keeps
`.fullSizeContentView` there, which is SwiftUI's default for a window with a
toolbar: the page background and scrolled rows pass under the glass toolbar,
and the window controls stay in the toolbar above the content.
- Settings, which has no toolbar, keeps the #237 title bar on every system.
- On macOS 13–25 the main window keeps it too.
- `testToolbarWindowFollowsTheSystemAndKeepsItsControls` covers the new case,
  and the #237 test still covers the old one.

**Checked by running the app on macOS 27.2.1** with two displays, in dark and
light appearance: Home, Library, Discover, search, a rename sheet, full screen
and back. The window controls stayed visible throughout. Not checked: macOS
26.6.2, where #237 was reported, and macOS 13–25.

## Result of B3 (adaptive glass)

`Views/Components/AdaptiveGlass.swift` holds the one place that checks for
macOS 26. On macOS 13–25 every surface below draws what it drew before.

| Surface | macOS 26 | macOS 13–25 |
| --- | --- | --- |
| Now-playing bar | Floating glass bar, inset from the window edges | Full-width `.bar` with a divider |
| Import toast | Glass | `.regularMaterial` |
| Download bar and desktop hint | Glass strip, accent tint kept on top | Material strip, as before |
| Grid HUD (`liquidGlassHUD`) | Glass | Polyfill |
| Preview control panel (`VideoPreviewView`) | Glass | `glassBackground` |
| Now Playing overlay card | Glass | `.ultraThinMaterial` card |
| `WallneticSheet` | No panel of its own; the system sheet shows | Polyfill panel |

Also changed:
- `WallneticSheet`'s title and the Now Playing overlay's text use `.primary`
  and `.secondary` instead of hard-coded white, so they stay readable in light
  appearance. The sheet icon lost its accent glow.
- The primary button's accent glow became a short, soft shadow.

**Checked by running the app on macOS 27.2.1**, in dark and light appearance:
the now-playing bar with rows scrolling under it, the desktop hint and a
rename sheet. Not checked:
- the import toast and the download bar, which need a real import or download;
- the grid HUD, the preview control panel and the Now Playing overlay card.
  Nothing in the app opens `WallpaperGridView` or starts
  `NowPlayingOverlayController` today, so these three cannot be reached.
- macOS 13–25.

Left as they were, on purpose:
- **Onboarding's white icon.** It sits on a coloured disk in both appearances,
  so the audit's concern does not apply.
- **Thumbnail badges.** They are small labels on artwork, and the audit marked
  them optional.
- **`GlassEffectContainer`.** No two custom glass surfaces touch.
- **The polyfill's accent shadow.** macOS 26 no longer draws the polyfill, and
  earlier systems keep their look.

## Screens to confirm visually

Check each on macOS 26 and on macOS 13, in light and dark appearance:

1. Main window on Home: is there a seam or a double bar under the title bar?
   Check it at rest and scrolled.
2. A rename sheet (`WallneticSheet`): look for a double blur and check the
   title's legibility.
3. The onboarding sheet.
4. The Settings window: sidebar, window controls and backdrop.
5. The menu bar menu, including the long Spaces and playlist submenus.
6. The Now Playing overlay over a bright desktop and a dark one.
7. The Dynamic Island, collapsed and expanded.
8. Explore with `Carousel3DGallery`, card hover and the Popular rank glow.
9. An alert and the download progress bar.
10. The main window in full screen.
