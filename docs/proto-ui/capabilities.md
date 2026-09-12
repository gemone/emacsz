# Proto-UI Capability and Compatibility Matrix

Status: normative capability and compatibility baseline
Reference backend: PGTK
Protocol: EUP v1
Current status manifest: 133 features — 5 implemented, 125 degraded, and 3
pending; scope-sensitive bounded coverage, not PGTK parity

Adapter-first is normative: new Proto-UI capability implementation belongs in
the adapter, frontend, tooling, Lisp integration, or build glue—not in
inherited GNU Emacs C source.  See
[`adapter-boundary.md`](adapter-boundary.md).

## 1. Capability model

Each capability has:

1. Owning side.
2. Support level.
3. Negotiation direction.
4. Degradation strategy.
5. Conformance evidence.

Unknown optional capabilities are ignored. Unknown required messages trigger controlled resync or session error. Missing optional capabilities must produce a safe fallback.

## 2. Support levels

| Level | Meaning |
|---|---|
| Required | Every complete implementation must provide it |
| Recommended | Required for production quality; fallback allowed |
| Optional | May be absent with defined behavior |
| Conditional | Present only when platform/renderer supports it |
| Explicitly unsupported | Protocol can describe request, implementation rejects safely |

## 3. Backend and session capabilities

| Capability | Level | Owner | Fallback |
|---|---|---|---|
| `protocol.v1` | Required | both | No session |
| `session.control_v1` | Required | both | Disconnect/reconnect |
| `session.resume` | Recommended | backend | New session/full snapshot |
| `session.replay` | Recommended | backend | Snapshot fallback |
| `multi_frame` | Required | backend/core | One frame only |
| `multi_monitor` | Recommended | frontend/platform | Primary monitor |
| `dpi_scale` | Required on scalable platforms | frontend | Scale 1.0 |
| `frame.alpha` | Optional | frontend | Opaque frame |
| `frame.opacity` | Optional | frontend | No fade |
| `frame.fullscreen` | Required desktop | frontend | Normal window |
| `frame.maximize` | Required desktop | frontend | Manual resize |
| `frame.undecorated` | Optional | frontend/platform | Decorated frame |
| `frame.override_redirect` | Conditional | frontend/platform | Managed frame |
| `frame.child` | Required for PGTK parity | negotiated | Tooltip/child unavailable |
| `frame.tooltip` | Required for PGTK parity | negotiated | Echo-area fallback |
| `frame.patch_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded atomic visibility/focus/opacity/decoration/scale batch only, with no complete frame-state parity |
| `frame.snapshot_core_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded atomic core presentation snapshot only, with no complete Emacs frame-parameter parity |
| `window_tree` | Required | core/backend | Backend cannot operate |
| `window.tree_snapshot_v1` | Optional/degraded | adapter/frontend | Bounded complete-tree state codec and Scene validation; no rendering/management parity |
| `window.geometry_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded content/body geometry and diagnostic body-boundary render |
| `window.zones_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded disjoint zone state and diagnostic top-boundary render |
| `window.position_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded diagnostic buffer/start/point state only |
| `window.face_state_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded default-face evidence that drives the window background and, when the face carries a foreground, its live text color; per-line/per-run faces unavailable |
| `window.mouse_highlight_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; one bounded visible rectangle per displayed row with a live face, carrying either the active region (`sdl3-emacs-graphic-smoke`) or the live `mouse-face` span the producer resolves under the mirror's pointer (`sdl3-emacs-mouse-smoke`); arbitrary non-row-aligned shapes and hit testing are not claimed |
| `font.descriptor_patch_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded scalar descriptor evolution only, with no real font-object or frame-font parity |
| `fringe.bitmap_resource_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded monochrome bitmap rendering plus a display-backed frame's real fringe widths drawn as edge bars, with those reserved columns insetting the rows and cursor (`sdl3-emacs-graphic-smoke`), and no full fringe semantics or PGTK parity |
| `widget.tooltip_bounded_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded frontend box only, with no platform tooltip policy or full PGTK parity |
| `widget.menu_model_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded complete-tree model, a menu-bar row whose slots are sized by their own labels, and the live publisher's real `menu-bar-keymap` item labels plus, while a menu is open, that item's real child rows; bounded pointer and keyboard traversal through the depth-four model is supported, while full PGTK menu parity remains pending |
| `widget.menu_open_request_v1` | Optional/degraded | frontend/adapter | Bounded 40-byte reverse intent naming the menu-bar item the user pressed and its logical slot origin, shared with the menu-bar layout the draw path uses and delivered over EPXL; the publisher opens that item's real keymap as a bounded popup, the frontend's result/cancel closes it, and choosing a row runs that row's real command when it is in the publisher's closed safe set (`sdl3-emacs-menu-open-smoke`, `sdl3-emacs-menu-apply-smoke`) |
| `widget.menu_open_close_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded popup state and child render that reflects the backend-owned `selected` and `enabled` flags, with pointer and keyboard traversal through the depth-four model, while full PGTK menu parity remains pending |
| `widget.menu_result_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded acknowledged result/cancel queue plus popup click selection, outside dismissal, Escape cancellation, and live selection that runs the chosen row's real command when it is in the publisher's closed safe set (`sdl3-emacs-menu-apply-smoke`); arbitrary commands and full PGTK menu parity remain pending |
| `widget.menu_hover_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded acknowledged enter/move/leave queue plus a shared-geometry popup hover/navigation highlight that reports enter/leave transitions, with no `move` streaming |
| `widget.menu_patch_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded ordered upsert/delete model evolution only, with no move policy or complete menu semantics |
| `widget.toolbar_model_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded complete tool-bar model whose items draw a live image resource when the backend references one, and fall back to the text label for a missing, incomplete, or stale generation, with no overflow or full policy |
| `widget.toolbar_click_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded acknowledged press/release queue plus a shared-layout click hit test for visible enabled button/toggle items, with no command execution or full PGTK tool-bar parity |
| `widget.toolbar_patch_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded ordered upsert/delete evolution that keeps the same icon-or-label draw rule, with no move policy, overflow, or full toolbar parity |
| `widget.dialog_model_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded message/prompt/confirm state, diagnostic box, the standard button row implied by the backend button mask, and a bounded ASCII prompt field for prompt dialogs, with no native/file/color/font dialog or full callback parity |
| `widget.dialog_result_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; bounded acknowledged button/text queue plus a shared-layout standard-button hit test, Escape dismissal, and the bounded prompt field text, with no Unicode field input or Emacs callback dispatch |
| `window.scrollbar_state_v1` | Optional/degraded | adapter/frontend | Ignore unsupported message; dedicated bounded vertical and horizontal states, each with a proportional track/thumb from one geometry source shared with pointer hit testing, and the live publisher reports the real window line count/window start and widest-line/`window-hscroll`; no advanced scrollbar policy |
| `window.scroll_request_v1` | Optional/degraded | adapter/frontend | Bounded absolute/relative intents with negotiated EPXL delivery for the existing 0x0309 contract, plus bounded thumb drag and one-viewport trough paging on both axes; the live publisher applies a vertical intent to the real `window-start` (`sdl3-emacs-scrollbar-interaction-smoke`) and a horizontal one to the real `window-hscroll` (`sdl3-emacs-hscroll-smoke`); arrow-step geometry and full core dispatch pending |
| `window.scrollbar_event_v1` | Optional/degraded | adapter/frontend | Separate negotiation required for dedicated 0x0941 absolute/relative intents; no drag/page/step policy or core dispatch |
| `glyph_rows` | Required | core/backend | Backend cannot operate |
| `shaped_glyphs` | Required | core/font stack + frontend | Incomplete text fallback |
| `bidi` | Required | core/redisplay | RTL text nonconformant |
| `cjk` | Required production | core/font stack + frontend | Missing CJK rendering |
| `composition` | Required production | core/font stack | Complex script degradation |
| `emoji` | Optional | fonts/frontend | Boxes/fallback glyph |
| `color_fonts` | Optional | frontend/backend atlas | Monochrome fallback |
| `font_metrics` | Required | core/backend | Protocol cannot operate |
| `font_frontend_raster` | Recommended | frontend | Backend atlas required |
| `font_backend_atlas` | Required fallback | backend/frontend | Frontend raster unavailable |
| `face_resources` | Required | backend | Backend cannot operate |
| `image_resources` | Required graphic parity | backend/frontend | Images unavailable |
| `animated_images` | Optional | backend/frontend | Static first frame |
| `fringe_bitmaps` | Required graphic parity | backend/frontend | Fringe degraded |
| `partial_damage` | Required | backend/frontend | Full redraw |
| `damage_coalescing` | Required | backend | Higher bandwidth/frame drops |
| `render.glyph_run_debug_v1` | Optional/degraded | adapter/frontend | Facts text remains the safe baseline |
| `render.glyph_face_debug_v2` | Optional/degraded | adapter/frontend | Facts text remains the safe baseline; no shaped-text or face parity |
| `render.image_debug_v1` | Optional/degraded | adapter/frontend | Complete bounded RGBA8 resource rendering only |
| `scroll_optimization` | Recommended | backend/frontend | Full redraw |
| `scrollbars` | Required PGTK parity | negotiated | Scrollbar hidden |
| `menu_model` | Required | core/backend | Menus unavailable |
| `native_menus` | Optional | frontend/platform | Custom renderer |
| `dialog_model` | Required | core/backend | Lisp fallback |
| `tooltips` | Required PGTK parity | negotiated | Echo-area fallback |
| `selection` | Required GUI | negotiated | Clipboard unavailable |
| `clipboard` | Required GUI | frontend | Clipboard unavailable |
| `input.pointer_selection_left` | Optional | adapter/frontend | Pointer events remain observed |
| `input.pointer_middle_paste` | Optional | adapter/frontend | Requires the completed bounded left-selection evidence |
| `input.touch_bounded_v1` | Optional | adapter/frontend | Requires negotiated `input.pointer_v2`; multi-touch gestures, pressure, and pen stay unclaimed |
| `input.pen_bounded_v1` | Optional | adapter/frontend | Requires negotiated `input.pointer_v2`; the eraser tip, barrel buttons, pressure axes, tilt, and proximity events stay unclaimed |
| `dnd.bounded_v1` | Optional | adapter/frontend | Negotiated bounded single-offer receive only (≤256 payload bytes) plus best-effort drag-position feedback; drag-out, MIME negotiation, and multi-format drops unavailable |
| `ime` | Required CJK production | frontend + core | No platform IME |
| `shared_memory` | Optional | transport | Socket/pipe |
| `file_replay` | Recommended | backend/tools | Live session only |
| `compression` | Optional | transport | Uncompressed |
| `encryption` | Optional | transport | Local trusted IPC |
| `diagnostics` | Recommended | both | Minimal errors |

## 4. Frontend renderer capabilities

| Capability | Purpose | Fallback |
|---|---|---|
| `renderer.class` | Software, GPU basic, GPU advanced, hybrid | Software |
| `renderer.api` | SDL Renderer, SDL GPU, Vulkan, Metal, D3D12, compositor | Software |
| `texture.max_width/height` | Resource limits | Clamp/slice |
| `texture.formats` | Accepted pixel formats | Convert RGBA8 |
| `texture.srgb` | Correct sRGB output | Manual gamma approximation |
| `blend.premultiplied_alpha` | Correct alpha | Conversion |
| `clip.scissor` | Efficient clipping | Software clip |
| `glyph.atlas` | Cached glyph textures | Per-glyph textures |
| `glyph.persistent_atlas` | Avoid churn | Recreate pages |
| `glyph.subpixel` | Better positioning | Integer positioning |
| `image.cache` | Avoid re-upload | Reupload |
| `image.mipmap` | Downscale quality | Linear filtering |
| `async_upload` | Avoid stalls | Synchronous upload |
| `damage.present` | Present changed regions | Full present |
| `render.glyph_run_debug_v1` | Diagnostic ASCII run transport/render | Ignore unsupported message; keep facts text |
| `present.vsync` | Avoid tearing | Software pacing |
| `present.adaptive_vsync` | Latency control | Regular vsync |
| `present.mailbox` | Low latency | Vsync/immediate fallback |
| `refresh.range` | Supported refresh rates | Platform default |
| `multi_window` | Multiple frames | One visible frame |
| `msaa` | Primitive quality | No MSAA |
| `hdr` | HDR output | SDR |
| `wide_gamut` | Extended color | sRGB |

## 5. Widget renderer capabilities

Semantic ownership remains in Emacs regardless of renderer.

| Widget | Semantic owner | Renderer options | Baseline |
|---|---|---|---|
| Menu | Core/backend | Custom GPU/CPU, native | Functional model |
| Menu bar | Core/backend | Custom/native | Visible model |
| Popup menu | Core/backend | Custom/native | Functional model |
| Tool bar | Core/backend | Glyph, custom, native | Visible model with text labels or live image-resource icons |
| Tab bar | Core/redisplay | Glyph/custom | Visible model |
| Dialog | Core/backend | Custom/native | Result returns; bounded standard buttons and an ASCII prompt field are presented |
| File dialog | Core/backend | Native/custom | Path returns |
| Color dialog | Core/backend | Native/custom | Color returns |
| Font dialog | Core/backend | Native/custom | Font spec returns |
| Tooltip | Core/backend | Custom/native | Content/placement |
| Scrollbar | Core/backend | Custom/native | Vertical state/thumb rendering, bounded thumb drag, and one-viewport trough paging from one shared geometry source; horizontal state, arrow steps, and Emacs dispatch pending |
| IME candidate | Platform/frontend | Platform/custom | Composition works |

## 6. PGTK parity matrix

Priority and requirement columns define the specification target. The Status and Evidence columns are the current implementation snapshot. They are intentionally more conservative than historical workstream approvals: an approved bounded bridge is not claimed as PGTK parity.

### Status legend

| Status | Meaning |
|---|---|
| Implemented | Full row scope is available in the adapter-first path and covered by a gate |
| Degraded | A bounded, safe subset works; the fallback and missing scope are explicit |
| Pending | No adapter-first runtime implementation yet; the protocol/design may be specified |
| Blocked | Requires a defined runtime seam or capability before it can proceed |

The base snapshot below records `23da8d92855`; the current revision adds W12a
bounded capability/status negotiation, W12b bounded frame/resource generation
contracts, W12c real-frame lifecycle bridge smoke, W12d frame
visibility/focus state contracts, W12e bounded resource payload/eviction
policy, W12f optional host frame-state ABI seam, W12g terminal-lifecycle core,
W12h fail-closed runtime manifest/gate, W12i generated C adapter plus
linkable observation library, W12j R5 frame-service mapping, and W12k R6
atomic capture batches. 118 PGTK rows are audited: 21 Degraded,
97 Pending, 0 Blocked, and 0 fully Implemented. Pending rows are not failures
of the protocol design; they are requirements still separating the bounded
facts bridge from W12 PGTK parity and the W16 real-frame acceptance test.

Outside that audited PGTK count, W10d additionally reports
`render.glyph_run_debug_v1` as optional/degraded/negotiable.  Its evidence is
`sdl3-glyph-run-smoke`; it is a transport/render diagnostic and does not change
the pending `redisplay.glyph_rows` or any PGTK status above.  W10e also uses
that bounded path in `sdl3-frame-smoke` to render the public-facts marker
`Emacs Proto-UI`, and W10f adds its exact-delete lifecycle and facts fallback;
this remains diagnostic fallback, not redisplay-owned capture, shaped text,
face/font rendering, or `output_proto`.

P30 moves the matrix's `Faces` row from Pending to Degraded: bounded
`FACE_DEFINE`/`FACE_PATCH`/`FACE_DELETE` resources and `WINDOW_FACE` v1 can
validate and render one live default-face background, but core-owned face
capture and complete Emacs face semantics remain pending.

Priorities:

| Priority | Meaning |
|---|---|
| P0 | Required for first real SDL3 Emacs frame |
| P1 | Required for production proto UI |
| P2 | Required for complete PGTK parity |
| EXP | Protocol-defined experimental/explicitly unsupported initially |

### 6.1 Terminal/display

| Capability | PGTK equivalent | Proto requirement | Priority | Status | Evidence |
|---|---|---|---|---|---|
| Terminal creation | `create_terminal(output_pgtk)` | generic `output_provider` with `proto` identity | P0 | Headless implemented | Opt-in TPE gate creates a real Emacs terminal; default builds remain disabled and no SDL frame exists |
| Terminal deletion | PGTK terminal hooks | EUP session/frame teardown | P0 | Headless cleanup implemented | TPE headless gate drains adapter state and deletes its terminal; frontend disconnect rollback remains pending |
| Graphic frame predicate | `output_pgtk` frame | `output_proto` frame | P0 | Pending | Headless terminal identity is `proto`, but no frame exists and `make-frame` on provider is not implemented |
| Focus frame | GDK focus | Frontend focus + core state | P0 | Degraded | Strict EUP focus state plus one-frame SDL gained/lost round trip through public Emacs selection and focused fact; no OS focus control or multi-frame parity |
| Multi-frame | GTK windows | Multiple SDL windows | P1 | Pending | Single SDL facts window and one EUP frame profile |
| Monitor attributes | GDK monitor | SDL monitor events | P1 | Degraded | EUP `FRAME_MONITOR` v1 owns generation-qualified identity, primary flag, and bounds; negotiated `MONITOR_EVENT` EPXL transport records current SDL bounds, while migration and redisplay adaptation remain pending |
| Scale factor | GDK scale | SDL display scale | P1 | Degraded | `FRAME_SCALE` v1 owns generation-qualified scale state, SDL reports per-window scale, and negotiated `DPI_EVENT` records scale observations; redisplay still consumes fixed `FRAME_UPDATE` values |
| DPI | GTK/GDK | SDL display data | P1 | Degraded | `FRAME_SCALE` v1 owns generation-qualified X/Y DPI state and negotiated `DPI_EVENT` records SDL scale/DPI observations; redisplay still consumes fixed `FRAME_UPDATE` values |
| Monitor change | GDK signal | Frontend event/redisplay | P1 | Degraded | SDL display/scale changes refresh frontend-local monitor facts and negotiated `MONITOR_EVENT`/`DPI_EVENT` EPXL transport is smoke-verified; redisplay adaptation and Emacs migration remain pending |

### 6.2 Frame lifecycle

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Create/delete frame | P0 | Degraded | W12c creates/deletes one real PGTK observation frame and one EUP/SDL3 frame in a bounded smoke; no `output_proto`-owned frame predicate or general lifecycle |
| Visible/invisible | P0 | Degraded | W12d strict EUP hidden/visible state contract and scene registry; no Emacs/SDL3 runtime round trip |
| Iconify/deiconify | P1 | Pending | W12/W16 PGTK parity gate not met |
| Raise/lower | P1 | Degraded | EUP `FRAME_Z_ORDER` v1 models raise/lower; SDL probe covers top/always-on-top only while portable raise/lower and Emacs round trips remain pending |
| Restack | P1 | Degraded | EUP relative above/below records validate another active frame generation; SDL relative restacking and redisplay adaptation remain pending |
| Fullscreen states | P1 | Degraded | EUP `FRAME_FULLSCREEN` v1 models none/fullboth/fullwidth/fullheight/maximized and SDL probes and restores fullboth; width-only, height-only, maximized, persistence policy, and PGTK parity remain pending |
| Maximize horizontal/vertical | P1 | Degraded | EUP `FRAME_MAXIMIZE` v1 carries independent axis flags; SDL probes/restores both-axis maximization, while single-axis mapping, geometry adaptation, and PGTK parity remain pending |
| Undecorated frame | P1 | Degraded | EUP `FRAME_DECORATIONS` v1 maps decorated/undecorated policy to the diagnostic SDL border flag; persistence, parent/tooltip policies, and PGTK parity remain pending |
| Override redirect | P2 | Pending | W12/W16 PGTK parity gate not met |
| Parent frame | P2 | Degraded | EUP `FRAME_PARENT` v1 models nullable parent relation and modal policy; Scene validates active-parent identity and the SDL probe verifies unparent path, while linked child-window ownership remains pending |
| Child frame | P2 | Pending | EUP relation policy exists, but linked SDL child ownership, visibility propagation, tooltip behavior, and Emacs child-frame parity remain pending |
| Tooltip frame | P2 | Pending | W12/W16 PGTK parity gate not met |
| Title/name | P0 | Degraded | Public Emacs title facts publish through bounded `FRAME_TITLE` v1 and set the diagnostic SDL window title; complete frame title/name/icon-name parameters and PGTK parity remain pending |
| Icon | P1 | Degraded | `ICON_DEFINE`/`DELETE` v1 own complete RGBA8 icons and `FRAME_ICON` v1 references them through SDL; multi-resolution, animated, and taskbar parity remain pending |
| Outer/native/text geometry | P0 | Degraded | Public frame/window geometry facts; no platform-native geometry contract |
| Size hints | P1 | Degraded | EUP `FRAME_SIZE_HINTS` v1 models min/max, increment, and aspect constraints; SDL applies min/max/aspect and Scene owns increments, while redisplay geometry adaptation remains pending |
| Alpha/background alpha | P1 | Degraded | EUP `FRAME_ALPHA` v1 carries active/inactive/background opacity; SDL probe applies active window opacity and falls back opaque, while focus transitions and complete PGTK visual parity remain pending |
| Atomic bounded frame patch | P1 | Degraded | `FRAME_PATCH` v1 atomically updates selected visibility/focus/opacity/decoration/scale state; title, geometry, monitor, and z-order are separate bounded messages, while complete frame semantics and redisplay adaptation are pending |
| Core frame snapshot | P1 | Degraded | `FRAME_SNAPSHOT` v1 atomically restores visibility/focus/opacity/decoration/scale/geometry/fullscreen/maximize; title, icon, monitor, z-order, and parent have separate bounded messages, while full parameters and redisplay adaptation are pending |
| Internal border | P0 | Degraded | `BORDER_UPDATE` v1 validates sides/thickness/color and SDL renders window edges; core-owned border semantics pending |
| Skip taskbar | P2 | Pending | W12/W16 PGTK parity gate not met |
| Sticky | P2 | Pending | W12/W16 PGTK parity gate not met |
| Z-group | P2 | Pending | W12/W16 PGTK parity gate not met |

### 6.3 Redisplay/rendering

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Glyph rows | P0 | Degraded | Bounded public-fact rows in EUP; not redisplay-owned glyph rows |
| Glyph runs | P0 | Pending | W12/W16 PGTK parity gate not met |
| Character glyphs | P0 | Degraded | Bounded printable ASCII through SDL debug text and bounded UTF-8 lines through SDL_ttf with `PROTO_UI_FONT` or platform-font discovery; no shaping, font metrics, BiDi, or fallback policy |
| Composite glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Glyphless glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Image glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| Stretch glyphs | P1 | Pending | W12/W16 PGTK parity gate not met |
| XWidget glyphs | EXP | Pending | W12/W16 PGTK parity gate not met |
| Faces | P0 | Degraded | Bounded face resources and `WINDOW_FACE` v1 validate exact live generations; SDL renders the default-face background and uses its foreground for that window's live text, refreshing when the face generation is replaced (`sdl3-face-text-smoke`), and the owned publisher now reports the frame's real default face so the live SDL window draws Emacs's own colors (`sdl3-emacs-face-smoke`); redisplay capture, per-line/per-run faces, overlays, derived faces, shaping, and PGTK face parity pending |
| Cursor styles | P0 | Degraded | `CURSOR_UPDATE` v1 `cursor_kind` is rendered as a bounded shape — solid box/bar/hbar, a four-edge hollow outline, and a bottom-edge underline, with any unknown kind falling back to the solid box — the cursor uses the window's live default-face foreground (`sdl3-cursor-style-smoke`), a display-backed frame sizes it to the real character cell and uses its real `cursor` face color (`sdl3-emacs-graphic-smoke`); the owned publisher reports the selected window's real `cursor-type` as that bounded kind (`sdl3-emacs-cursor-smoke`); a cursor that does not fit its window clamps into it instead of failing the whole snapshot (`proto-ui-unit`), while the publisher still bounds the mirrored cursor column at nine; the scene tracks the active cursor rather than the last-emitted window and draws a non-selected window's caret hollow (`sdl3-emacs-graphic-smoke`, `inactive_cursor_hollow`); blink state, exact cursor column, per-window cursor faces, IME-coupled caret behavior, and redisplay-owned cursor semantics pending |
| Mouse face | P1 | Degraded | `WINDOW_MOUSE_HIGHLIGHT` v1 validates active frame/window, rect containment, and exact live face generation, with bounded SDL rendering; pointer motion, face resolution, overlays, and PGTK parity pending |
| Fringe bitmaps | P1 | Degraded | `FRINGE_BITMAP_DEFINE`/`DELETE` v1 restore bounded monochrome resources and SDL expands validated bits; the owned publisher also reports a display-backed frame's real fringe widths, drawn as edge bars (`sdl3-emacs-graphic-smoke`); color/alpha bitmaps, authoring, and draggable semantics pending |
| Window divider | P1 | Degraded | `DIVIDER_UPDATE` v1 validates orientation/bounds/generation and SDL renders fixed-color divider; draggable/resize semantics pending |
| Vertical border | P1 | Pending | W12/W16 PGTK parity gate not met |
| Mode line | P0 | Degraded | Bounded public `WINDOW_MODE_LINE_V1` observation and SDL bar spanning the frame's real text area; a display-backed publisher reports the real `format-mode-line` text and height of a live PGTK/X frame plus that frame's real mode-line face colors, the frontend draws the bar with them, and a split frame's inactive window uses the real `mode-line-inactive` colors (`sdl3-emacs-graphic-smoke`), while a batch publisher still observes none; per-segment runs carry `format-mode-line`'s own faces for the mode line, header line, and tab line into the draw list in each line's face color (`header_line_face_runs`, `tab_line_face_runs`), runs of one chrome kind never suppress another line's plain text, and the face's real `:box` (the default theme's released-button border) draws as approximation bars with the real `:line-width` and a released-button bevel (`mode_line_box`); item models, per-character header/tab fonts, mouse interaction, redisplay ownership, and full PGTK parity pending |
| Header line | P1 | Degraded | Bounded public `WINDOW_AUX_LINE_V1` text/height observation and SDL diagnostic bar; item models, faces, mouse, redisplay ownership, and parity pending |
| Tab line | P1 | Degraded | Bounded public `WINDOW_AUX_LINE_V1` text/height observation and SDL diagnostic bar; item models, faces, mouse, redisplay ownership, and parity pending |
| Tab bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Tool bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Menu bar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Scrollbar | P1 | Pending | W12/W16 PGTK parity gate not met |
| Overlay arrow | P1 | Pending | W12/W16 PGTK parity gate not met |
| Hourglass | P2 | Pending | W12/W16 PGTK parity gate not met |
| Visible bell | P2 | Pending | W12/W16 PGTK parity gate not met |
| Audible bell | P1 | Pending | W12/W16 PGTK parity gate not met |
| Partial damage | P0 | Degraded | Explicit `DAMAGE_RECTS` retained-target clip plus cursor and bounded text/region clips; redisplay-owned incremental damage pending |
| Scroll optimization | P1 | Degraded | Bounded full-width vertical `SCROLL_RUN` codec, overlap planning, and scratch-target SDL scroll-copy smoke; redisplay-owned scroll semantics and GPU batching pending |
| Double-buffer equivalent | P1 | Degraded | Adapter-owned SDL target; no full redisplay invalidation model |

### 6.4 Text/fonts

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Monospace Latin text | P0 | Degraded | Bounded printable ASCII, 120 columns/32 lines, 8x8 debug font |
| Font fallback | P1 | Pending | W12/W16 PGTK parity gate not met |
| CJK text | P1 | Pending | W12/W16 PGTK parity gate not met |
| BiDi ordering | P1 | Pending | W12/W16 PGTK parity gate not met |
| Arabic shaping | P2 | Pending | W12/W16 PGTK parity gate not met |
| Indic shaping | P2 | Pending | W12/W16 PGTK parity gate not met |
| Emoji | P2 | Pending | W12/W16 PGTK parity gate not met |
| Color emoji | P2 | Pending | W12/W16 PGTK parity gate not met |
| Variable fonts | P2 | Pending | W12/W16 PGTK parity gate not met |
| Color fonts | P2 | Pending | W12/W16 PGTK parity gate not met |
| Synthetic bold/italic | P1 | Pending | W12/W16 PGTK parity gate not met |
| Underline/overline/strike-through | P0 | Degraded | Policy-derived approximation bars in SDL debug glyph path; shaped text and font metrics pending |
| Box faces | P0 | Degraded | Policy-derived four-edge approximation boxes in SDL debug glyph path; font metrics and core face parity pending |
| Baseline/line spacing | P0 | Degraded | Facts-profile row baseline and visible-height geometry only |
| Frame font change | P1 | Pending | W12/W16 PGTK parity gate not met |
| Fontset semantics | P1 | Pending | W12/W16 PGTK parity gate not met |

### 6.5 Input/IME

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Keyboard events | P0 | Degraded | Printable ASCII insert, backspace, arrows, copy, paste; negotiated single-key and exact `C-x 1/2/3/o` commands map a closed SDL whitelist to bounded Emacs key descriptions; smokes observe `C-x 2`, `C-x 3` plus `C-x o` navigation/edit, and `C-x 1` one-window restore; no general keymap/IME/session parity |
| Modifier state | P0 | Degraded | Ctrl+C/V plus bounded C/M/s/H-modified key descriptions and exact two-key `C-x 1/2/3/o` commands through full key v2 with `input.key_command_v1` and `input.composite_key_command_v1`; arbitrary modifier combinations, complete Emacs translation, and general command parity pending |
| Multibyte input | P0 | Degraded | Smoke-seeded bounded committed UTF-8 from `SDL_EVENT_TEXT_INPUT` uses `input.text_unicode`, EPXL `TEXT_INPUT`, and `render.unicode_text_v1`; cursor-anchored SDL text-input area is lifecycle-managed. No OS-generated commit, composition/candidate/preedit acquisition, surrounding-text deletion, full IME lifecycle, or shaped-input parity |
| IME context lifecycle | P1 | Degraded | `IME_ATTACH`/`DETACH`/`FOCUS`/`CURSOR_RECT`/`ALLOWED_INPUT`/`SURROUNDING_TEXT`/`RESET` codecs and Scene owner validation; platform backend and composition pending; bounded commit report state exists without core text application |
| IME policy and surrounding state | P1 | Degraded | Bounded policy mask and 120-byte surrounding-text snapshot in Scene; platform backend and Emacs application pending |
| IME reverse wire reports | P1 | Degraded | Bounded attached/detached/preedit/commit/surrounding/delete/candidate/cancel codecs; Scene preedit/candidate/commit state and bounded ASCII SDL overlays proven, with no platform backend or core commit application |
| Dead keys | P1 | Pending | W12/W16 PGTK parity gate not met |
| Mouse motion | P0 | Degraded | Bounded hover/drag admission; negotiated v2 preserves the exact button mask |
| Mouse buttons | P0 | Degraded | Bounded left plus negotiated strict left/middle/right/X1/X2 v2 intents; generic publisher performs frame-relative window hit-testing, selects the clicked Emacs window, and moves point for bounded left v2 press/drag/release; right button, X buttons, advanced selection, and full mouse parity pending |
| Click count | P1 | Degraded | V2 validates and transports clicks 1..8; execution/selection parity remains pending |
| Drag events | P1 | Degraded | Ordered bounded left or negotiated v2 exact-mask drag; not selection drag |
| Left-drag selection | P1 | Degraded | One negotiated smoke subset sets public mark/point and copies at most 120 ASCII bytes (`sdl3-pointer-selection-smoke`); no mouse parity |
| Middle-click paste | P1 | Degraded | One negotiated smoke subset yanks the most recent kill after a prior bounded left selection (`sdl3-pointer-middle-paste-smoke`); no X11 PRIMARY or generic mouse yank |
| Wheel scroll | P0 | Degraded | Bounded whole-line vertical and horizontal ticks; pixel/page units, momentum, and smooth scrolling pending |
| Touchpad scroll | P1 | Pending | W12/W16 PGTK parity gate not met |
| Touch | EXP | Degraded | Negotiated `input.touch_bounded_v1` converts one SDL finger contact into a bounded Pointer v2 press/drag/release/cancel and drops a second concurrent contact (`sdl3-touch-tap-smoke`); multi-touch, gestures, pressure, pen, and Emacs gesture commands remain pending |
| Pen | EXP | Degraded | Negotiated `input.pen_bounded_v1` maps the pen tip to bounded Pointer v2 intents — air hover, tip-down press, tip-down drag, and release — and rejects the eraser tip (`sdl3-pen-tap-smoke`); barrel buttons, pressure axes, tilt, proximity events, drawing surfaces, and Emacs command dispatch remain pending |
| Gestures | EXP | Pending | W12/W16 PGTK parity gate not met |
| Focus enter/leave | P0 | Degraded | Negotiated strict FOCUS_EVENT observation with one-frame Emacs focused-fact round trip (`sdl3-focus-roundtrip-smoke`); no OS focus control or multi-frame parity |
| Window requests | P1 | Degraded | Negotiated close/resize/move/fullscreen/maximize/minimize/restore intents; bounded resize/move/fullscreen/maximize apply or record public frame-parameter acceptance, and bounded minimize/restore dispatch is smoke-verified (`sdl3-window-resize-roundtrip-smoke`, `sdl3-window-move-roundtrip-smoke`, `sdl3-window-maximize-roundtrip-smoke`, `sdl3-window-fullscreen-roundtrip-smoke`, `sdl3-window-minimize-restore-smoke`); actual WM completion, close request, host contract, exact WM geometry, and multi-frame parity remain pending |
| IME activation | P1 | Pending | W12/W16 PGTK parity gate not met |
| Preedit | P1 | Degraded | EUP start/update/end Scene state with bounded UTF-8 text, cursor offset, selected length, and bounded ASCII SDL overlay; platform input, Unicode/font rendering, and PGTK parity pending |
| Commit | P1 | Degraded | `IME_COMMIT` stores bounded UTF-8 committed text and clears active preedit/candidates in Scene; no platform IME hook or core buffer application |
| Surrounding text | P2 | Pending | W12/W16 PGTK parity gate not met |
| Candidate placement | P1 | Degraded | `IME_CANDIDATE_UPDATE` stores selected index/count/page and bounded selected label with an SDL diagnostic overlay; full candidate lists, Unicode label rendering, platform IME, selection input, and PGTK parity pending |

### 6.6 Desktop integration

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Clipboard text | P0 | Degraded | Bounded printable ASCII paste and copy smoke paths |
| Clipboard images | P2 | Pending | W12/W16 PGTK parity gate not met |
| PRIMARY selection | P1 | Degraded | Bounded UTF-8 text round-trips through the negotiated SDL PRIMARY API via Shift+Insert (`sdl3-primary-selection-roundtrip-smoke`); X11/Wayland expose an OS-shared PRIMARY while SDL fallbacks on other platforms are app-local; no selection ownership negotiation, targets, multi-format data, or general Emacs selection parity |
| SECONDARY selection | P2 | Pending | W12/W16 PGTK parity gate not met |
| Selection ownership | P1 | Degraded | Negotiated `selection.primary_ownership_v1` delivers bounded owner cancel/loss, replacement, and `SELECTION_OWNER_CLEAR` into Scene while SDL claims/releases its bounded PRIMARY marker (`sdl3-selection-owner-smoke`); no external request service, target conversion, multi-format data, or clipboard/PRIMARY exchange parity |
| Selection target negotiation | P1 | Degraded | Negotiated `selection.primary_transfer_v1` transports bounded `SELECTION_REQUEST`/`DATA` plus a matched `SELECTION_ERROR` into Scene, and a completed UTF8 transfer from an `export_to_platform` owner can claim/release SDL PRIMARY (`sdl3-selection-transfer-smoke`); external request service, target conversion, and Emacs/core transfer application remain pending |
| DND text | P2 | Degraded | Negotiated `dnd.bounded_v1` reports one bounded text/plain drop as `DND_ENTER`/`DND_DROP`/`DND_DATA` plus one best-effort `DND_POSITION` when the journal is idle, and the owned publisher applies the bounded payload (`sdl3-dnd-drop-smoke`); rich MIME, multi-offer, and drag-out remain pending |
| DND files | P2 | Degraded | The same bounded receive path offers a dropped file name as `text/uri-list` with the same best-effort position feedback; no file open, URI policy, or multi-file bundle is claimed |
| DND images | P2 | Pending | W12/W16 PGTK parity gate not met |
| DND copy/move/link | P2 | Pending | W12/W16 PGTK parity gate not met |
| System theme event | P2 | Degraded | SDL system theme captured through negotiated `THEME_EVENT` EPXL transport; Emacs publisher records delivered dark/light appearance and no complete face/theme refresh is claimed |
| System font preference | P2 | Pending | W12/W16 PGTK parity gate not met |
| App icon | P1 | Pending | W12/W16 PGTK parity gate not met |
| Taskbar state | P2 | Pending | W12/W16 PGTK parity gate not met |
| WM hints | P2 | Pending | W12/W16 PGTK parity gate not met |

### 6.7 Widgets

| Capability | Priority | Status | Evidence |
|---|---|---|---|
| Menu bar model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Bounded menu tree | P1 | Degraded | `MENU_MODEL` and `MENU_PATCH` schema 2 validate a bounded UTF-8 hierarchy plus generation-qualified nullable image references and ordered incremental updates; SDL renders a menu bar whose slots come from the backend-owned labels, and the owned publisher reports the frame's real `menu-bar-keymap` labels (`sdl3-emacs-menu-bar-smoke`); navigation/result/full menu semantics pending |
| Bounded menu open state | P1 | Degraded | `MENU_OPEN`/`CLOSE` v1 validate live model identity, submenu state, owner bounds, and exact generations; SDL renders direct child rows from one shared geometry source that also drives hit testing, pointer hover, and keyboard navigation (Up/Down move a frontend highlight over selectable rows and Enter chooses it), and the rows reflect backend `selected`/`enabled` flags with distinct checkbox/radio markers, resource-backed icons, dimmed disabled labels, and fixture-rendered bounded ASCII help, all evidenced by `sdl3-menu-hit-smoke`; on the live path the publisher publishes the real child rows of the requested menu-bar item or bounded submenu path, closes the popup when the frontend reports its result (`sdl3-emacs-menu-open-smoke`), derives bounded icon id/generation references from real `:image` specs, captures bounded file-backed XBM payloads while missing, malformed-XBM, or oversized payloads safely fall back, and requires help metadata without claiming render when P180 suppresses it; paths beyond the depth-four model, non-XBM payload capture, and full command execution remain pending |
| Bounded menu result intent | P1 | Degraded | `MENU_RESULT`/`CANCEL` v1 validate bounded menu/window/frame identity in a negotiated acknowledged queue, and the SDL frontend reports a clicked row, an outside dismissal, or an Escape cancellation from the shared popup hit test; on the live path the publisher resolves the chosen row to its real command and runs it only when that command is in a closed safe set (`sdl3-emacs-menu-apply-smoke`), so arbitrary or prompting commands still never execute |
| Bounded menu hover intent | P2 | Degraded | `MENU_HOVER` v1 validates phase-specific menu/item/window/frame identity and bounded coordinates in a negotiated acknowledged queue, and the SDL frontend now reports exactly one `leave` + `enter` pair per highlight transition driven by pointer hover or Up/Down (`sdl3-menu-hit-smoke`) while rendering the highlight locally; `move` streaming and backend-driven highlight dispatch remain pending |
| Bounded menu open request | P2 | Degraded | `MENU_OPEN_REQUEST` v1 validates bounded menu/window/frame identity plus the pressed item and its logical slot origin in a negotiated acknowledged queue, and the SDL frontend reports a press on a real menu-bar slot from the same layout the draw path uses (`sdl3-emacs-menu-open-smoke`); the owned publisher answers with that item's real keymap children, each row's `:filter`-resolved binding, real evaluated `:enable`/`:visible` state, bounded `:keys` hints, and bounded `:help` metadata (mark-dependent rows arrive disabled and the popup draw list carries a key hint; the live Undo row proves `popup_help`), and a bounded popup rectangle, the frontend's reported result closes it, and choosing a safe resolved command runs it in the real buffer, and an enabled submenu row reports a bounded child popup request, and the producer can traverse two successive submenu selections up to the shared depth bound (`proto-ui-menu-submenu-unit`, `sdl3-emacs-menu-open-smoke`); paths beyond that bound and arbitrary commands remain pending |
| Bounded tool bar model | P1 | Degraded | `TOOLBAR_MODEL` v1 validates bounded UTF-8 item models and SDL renders the row; an item that references a live image resource draws that icon, and a missing, incomplete, or stale generation falls back to the text label (`sdl3-toolbar-hit-smoke`); a display-backed publisher reports the frame's real `tool-bar-map` items (printable name, bounded key, `:help`, and evaluated `:visible`/`:enable`/`:button` state) into the same model plus the frame's real `tool-bar` face colors and released-button box, and the graphic smoke requires the live items, their drawn labels, the real-color strip, and the button borders with the real `:line-width` and bevel (`sdl3-emacs-graphic-smoke`, `tool_bar_face_colors`, `tool_bar_box`, `tool_bar_box_bevel`); real icons, overflow, orientation, and full policy pending |
| Bounded tool bar patch | P1 | Degraded | `TOOLBAR_PATCH` v1 applies ordered upsert/delete operations with strict generations and atomic Scene evolution, and patched items keep the same icon-or-label draw rule; dedicated moves, overflow, and full policy pending |
| Bounded tool bar click intent | P1 | Degraded | `TOOLBAR_CLICK` v1 preserves press/release, toolbar/item/window/frame identity, click count, button, modifiers, and coordinates in a negotiated queue, and the SDL frontend reports a press/release pair for the clicked visible enabled button or toggle from one shared layout used by the draw path and the hit test, dropping a stale press whose toolbar generation was replaced; overflow, orientation, command execution, and full tool-bar parity remain pending |
| Bounded dialog model | P1 | Degraded | `DIALOG_OPEN`/`UPDATE`/`CLOSE` v1 validate kind, button policy, owner containment, exact generations, UTF-8 title/text, and lifecycle cleanup; SDL renders the diagnostic box, the standard button row implied by the backend button mask, and — for a prompt dialog tall enough to hold it — a bounded ASCII text field, all from one layout shared with the hit test (`sdl3-dialog-hit-smoke`) |
| Bounded dialog result intent | P1 | Degraded | `DIALOG_RESULT` v1 validates button/text tails, nonzero dialog/window/frame identity, and negotiated acknowledged delivery, and the SDL frontend reports a clicked standard button or an Escape dismissal from the shared layout with the current bounded prompt text in the text tail; Unicode field input, custom buttons, and Emacs callback dispatch remain pending |
| Dedicated scrollbar state | P1 | Degraded | `SCROLLBAR_STATE` v1 reuses the bounded authoritative state codec with per-window-per-orientation Scene upsert and SDL vertical/horizontal thumb evidence, and every drawn thumb comes from the same layout the pointer hit test uses (`sdl3-scrollbar-smoke`); the owned publisher reports the real selected window's line count/window start and, independently, its widest visible line and `window-hscroll`, and its mirrored rows and runs drop the horizontally scrolled-off columns (`sdl3-emacs-scrollbar-smoke`, `sdl3-emacs-hscroll-smoke`); advanced scrollbar policy pending |
| Dedicated scrollbar event | P1 | Degraded | `SCROLLBAR_EVENT` v1 has separate capability negotiation and accepts only the bounded absolute/relative request payload through EPXL; the frontend now ends a thumb drag session on release (and when the primary button is no longer held), pages one viewport per trough press, tracks the drag axis, and converts window coordinates to frame-logical units before the hit test and drag tracker so a scaled live window can open a vertical or horizontal drag session; the publisher applies the delivered intent to the real `window-start` or `window-hscroll` (`sdl3-emacs-scrollbar-interaction-smoke`, `sdl3-emacs-hscroll-smoke`), while full core dispatch and arrow steps remain pending |
| Popup menu model | P1 | Degraded | Bounded popup rows render the backend-owned state: a selected checkbox gets a 4x4 square, a selected radio gets a distinct 2x2 dot, both have shifted labels, and a disabled row is drawn dimmed, while an enabled submenu row maps to a backend popup request (`sdl3-menu-hit-smoke`, `proto-ui-unit`); paths beyond the depth-four model, non-XBM payload capture, and full PGTK popup parity remain pending; bounded menu nodes can name existing image resources and the popup renders them with label fallback (`sdl3-menu-hit-smoke`), while the live publisher derives generation-qualified icon references from `:image` specs, captures bounded file-backed XBM payloads, and treats malformed or oversized payloads as per-row fallback; the highlighted help tip uses shared popup geometry; the live publisher derives checkbox/radio kind and selection from Emacs `:button` state and the producer unit pins a toggle plus two independent radio groups with separator-safe state (`proto-ui-menu-radio-unit`), while the line-number and line-wrapping radio groups are applied through the bounded result path (`proto-ui-menu-radio-apply-unit`) |
| Popup menu help tip | P2 | Degraded | The highlighted row's already-validated help renders through shared popup geometry as bounded printable-ASCII text, greedily wrapped at whitespace into at most three owner-safe lines and positioned above or below the popup only when it fits (`sdl3-menu-hit-smoke`); the live publisher still carries help, with frontend suppression when no text fits; non-ASCII help, oversized words, hover timing, and platform tooltip parity remain pending |
| Native menu | Optional | Pending | No platform menu bridge |
| Tool bar model | P1 | Degraded | Bounded items render text or a live image resource with a stale-generation label fallback (`sdl3-toolbar-hit-smoke`); a display-backed publisher mirrors the frame's real `tool-bar-map` items and `tool-bar` face colors, and the graphic smoke requires them, their drawn labels, and the real-color strip (`sdl3-emacs-graphic-smoke`); overflow, orientation, dedicated moves, and full PGTK tool-bar parity remain pending |
| Full dialog model | P1 | Pending | W12/W16 PGTK parity gate not met; bounded message/prompt/confirm adapter slice only |
| File dialog | P1 | Pending | W12/W16 PGTK parity gate not met |
| Color dialog | P2 | Pending | W12/W16 PGTK parity gate not met |
| Font dialog | P2 | Pending | W12/W16 PGTK parity gate not met |
| Tooltip model | P1 | Pending | W12/W16 PGTK parity gate not met |
| Bounded tooltip surface | P1 | Degraded | `TOOLTIP_SHOW`/`MOVE`/`HIDE` v1 validate frame/window identity and exact generations, and SDL renders a bounded box; delay/dismiss policy, Unicode glyphs, hit testing, accessibility, and PGTK parity pending |
| Full scrollbar model | P1 | Degraded | Dedicated vertical state and event transport exist plus a shared-geometry thumb drag with a real release lifecycle and trough paging (`sdl3-scrollbar-smoke`); horizontal state, arrow steps, and Emacs dispatch remain pending |

## 7. GPU acceleration tiers

GPU acceleration is negotiated frontend capability, not core obligation.

### Tier 0: software correctness

Required fallback.

```text
No GPU dependency
Complete semantics
Full redraw allowed
CI/headless/replay baseline
```

### Tier 1: GPU basic

Minimum production GPU path.

```text
GPU surface
Glyph atlas
Image textures
Blend/scissor
Damage redraw
Vsync
1080p60 target
```

### Tier 2: GPU advanced

Performance target.

```text
Persistent glyph atlas
Image cache
Async texture upload
Damage-only present
Multi-window batching
Frame pacing
1440p60 / capable 4K60 target
```

### Tier 3: low latency/high refresh

Optional.

```text
VRR
Mailbox/low-latency present
GPU timestamps
Zero-copy shared textures
120Hz+ scheduling
```

## 8. Font render modes

| Mode | Producer | Consumer | Use |
|---|---|---|---|
| Frontend raster | Core supplies font descriptor/metrics | Frontend rasterizes/caches | Low bandwidth production path |
| Backend atlas | Backend supplies glyph pixels | Frontend textures | Deterministic/fallback path |
| Hybrid | Per-font/per-glyph decision | Frontend | Production default target |

Backend atlas is mandatory fallback for missing frontend fonts, emoji, color fonts, and deterministic replay.

## 9. Capability negotiation rules

1. Backend and frontend both advertise capabilities.
2. Effective capability is intersection.
3. Required capability missing -> deterministic session error.
4. Optional capability missing -> explicit fallback.
5. Capability set is echoed in `SESSION_READY`.
6. Capability changes after initialization require session reset.
7. Unknown optional capabilities are ignored.

## 10. Degradation requirements

| Missing capability | Required fallback |
|---|---|
| GPU | Software renderer |
| Glyph atlas | Per-glyph textures or backend pixels |
| Image format | Convert to RGBA8 |
| Partial present | Full present |
| Native menu | Custom menu or glyph fallback |
| Native dialog | Custom dialog |
| Clipboard | Disable clipboard capability |
| DND | Disable DND capability |
| IME | Disable IME capability |
| Shared memory | Socket/pipe |
| Replay | Live session only |
| Compression | Uncompressed payload |

## 11. Compatibility acceptance

A capability row is complete only when:

1. Negotiation is specified.
2. Payload is specified.
3. Fallback is specified.
4. Emacs semantics are correct.
5. A replay or live test covers it.
6. Performance is measured when applicable.
7. Failure cannot crash Emacs.
8. Implementation status is recorded.

The base compatibility gate checks existing Emacs behavior only.  It runs
isolated batch scenarios for identity, buffer text and undo, point/mark and
narrowing, text/overlay properties, face definition/readback, window split and
delete, resize/scroll/recenter, and buffer-local variables.  When
`DISPLAY`/`WAYLAND_DISPLAY` is present it creates one real PGTK frame, repeats
the window/scroll/face checks there, deletes the frame, and verifies cleanup.
Without a display the PGTK scenarios are explicit skips, never passes disguised
as GUI evidence.

The backend semantic matrix extends that gate with seven fixed
backend-neutral scenarios.  It runs the same semantic scenarios in the
isolated batch/TTY parent and, when a display is present, in a real PGTK
child.  Each backend record has a canonical signature and SHA-256 digest, and
the report includes ordered combined digests plus per-pair match/skip status.
Digests exclude pixel dimensions, font names, frame identities/types, object
IDs, and elapsed time.  The Zig gate validates exact scenario order and
recomputes the combined and pair digests.  This is not proto-frame parity.

## 12. W12d implementation evidence baseline

This section is the pinned `zig-build-step-4` evidence checkpoint through
`8bebccada16` plus the W12d state contract.  It is retained for historical
comparison and is not the current status: later W14/W15 and P-series milestones
supersede its gaps.  The normative capability rows above, together with the
machine-readable manifest generated from `src/proto-ui/capability.zig`, describe
the current bounded surface through P186; regenerate it with
`zig build -Dproto-ui=true proto-ui-status`.  Every evidence summary is
scope-sensitive; "implemented" never implies PGTK parity.

### 12.1 W12d layer status

| Layer | Working now | Still required for parity | Evidence |
|---|---|---|---|
| Protocol coverage | All 165 assigned EUP IDs are classified in a deterministic manifest: 165 implemented codecs, 0 partial, and 0 planned; no unassigned or unclassified ID | Production implementation of the remaining face/text/graphics protocol gaps |
| Protocol/transport | EUP envelope, bounded `FRAME_UPDATE`, replay, EPXL framing, resync, ACK/retry, bounded in-session display sequence-gap recovery, bounded selection/clipboard/DND/resync transfer codecs, bounded diagnostic, touch/gesture, monitor/DPI/theme/device, and ordered input-batch codecs, explicit clipboard-kind wrappers, deterministic ordered/resync/ACK-loss/ERP1 convergence differential with
`RESOURCE_SNAPSHOT`-aware concrete face/font/string/image fingerprints, bounded EPXL capability negotiation/status manifest, frame visibility/focus state codec, bounded resource payload cache/eviction policy, request/evict codecs, bounded string define/delete, fixed-layout face/font/image define/data/delete, and atomic concrete `RESOURCE_SNAPSHOT` v1 restore with frontend ownership, optional host frame-state ABI seam, terminal-lifecycle core and fake-host runtime service, generated read-only C adapter, dynamically linkable observation library, bounded host-frame to EUP-frame service mapping, deterministic atomic capture batches, deterministic protocol fuzz hardening, and bounded process-level frontend crash isolation, and negotiated strict focus/window observation, machine-readable blocked R8 entry readiness, fail-closed host-audit candidate runtime-host adapter artifact, and pinned ABI/table linkage provenance | General resource/widget capability coverage, arbitrary recovery, remote safety, reviewed R7 registration and runtime terminal registration | `proto-ui-conformance`, `proto-ui-unit`, `proto-ui-terminal-service`, `proto-ui-fuzz`, `proto-ui-recovery-diff`, `proto-ui-crash-isolation`, `proto-ui-shim-conformance`, `proto-ui-shim-library-conformance`, `sdl3-live-smoke`, `sdl3-epxl-resync-smoke`, `sdl3-epxl-recovery-smoke`, `sdl3-epxl-gap-recovery-smoke`, `proto-ui-r8-adapter-linkage`, `proto-ui-r8-readiness` |
| Emacs observation | Real Emacs process publishes public frame geometry, bounded selection-relative flat live-window geometry (up to 16 windows, process-lifetime nonzero weak-key IDs that are not reused), bounded UTF-8 `TEXT_LINE_V2` for up to eight visible lines per window, and bounded public point cursors for observed windows through `FRAME_UPDATE`; exactly one selected-window cursor is active and a real `C-x 2` split-smoke observes two windows; the selected window's real `cursor-type` is published as a bounded `cursor_kind`; a display-backed publisher runs the frame itself so the real `format-mode-line` text, real scroll-bar width, and real line height (which then drives row spacing and cursor geometry) and real fringe widths are observable; the frame's real `menu-bar-keymap` item labels are published as a bounded menu-bar model in display order; each observed window that reports a scroll bar publishes its real line count/window start and widest visible line/`window-hscroll` as independent vertical and horizontal `SCROLLBAR_STATE` records, and a delivered bounded scroll intent moves that real `window-start` or `window-hscroll`; the frame's real default face colors are published as `#rrggbb` and projected to a generation-qualified `FACE_DEFINE` plus `WINDOW_FACE` binding; the window's displayed rows are mirrored (wrapped rows included) on a larger 256-byte row bound, interior blank lines are preserved, over-long rows are truncated to that bound, and horizontally scrolled rows drop the scrolled-off columns (with their runs) so the mirrored rows keep display alignment; debug fallback is ASCII-only while non-ASCII facts lines use bounded SDL_ttf when negotiated and a font is available, and a mixed row's ASCII spans still carry their face colours as partial runs drawn over that plain text; W12c creates/deletes one real display-backed frame and synchronizes one EUP/SDL3 frame lifecycle; W10e renders that public-facts marker through the bounded glyph-run debug fallback | Redisplay-owned per-window cursor semantics, cursor blinking/focus policy, more than eight visible lines per window, cross-restart window identity, hierarchical redisplay-owned window trees, display-row cursor placement on wrapped rows, rows past the 256-byte bound, rows/glyphs/faces/fonts, `output_proto`-owned frame creation/deletion, runtime visibility/focus events, full menu navigation and arbitrary command dispatch | `proto-ui-module-smoke`, `proto-ui-frame-fact-smoke`, `sdl3-emacs-smoke`, `sdl3-epxl-facts-smoke`, `sdl3-frame-smoke`, `sdl3-emacs-window-split-smoke`, `sdl3-emacs-scrollbar-smoke`, `sdl3-emacs-scrollbar-interaction-smoke`, `sdl3-emacs-hscroll-smoke`, `sdl3-emacs-menu-bar-smoke`, `sdl3-emacs-graphic-smoke` |
| SDL3 rendering | Real SDL window, frame/window/row/cursor scene, software/GPU selection, clear/fill/debug-text list, retained cursor/text clips, explicit damage-array retained-target clip, CPU command culling, bounded face-colored clear areas, window default-face backgrounds, body geometry and zone-boundary evidence, bounded ASCII atlas-glyph rendering, body/mode-line text drawn with the frame's real SDL_ttf font and pixel size, bounded UTF-8 SDL_ttf presentation with a system font fallback for uncovered scripts, sized from a real frame's font pixel size (line height fallback) and using that frame's real font file when published, up to thirty-two mirrored window lines per window, with font-lock runs positioned on the real character cell and clamped to the owning window (a line with any non-ASCII character keeps its plain SDL_ttf text instead of publishing an ASCII-only run that would fail the whole snapshot, and a line wider than its window clamps instead of failing the frame-bounds check), with a bounded LRU line-texture cache, vertical scroll-copy execution and policy, bounded border/divider/fringe styles, face decoration bars (including box borders), bounded debug glyph runs (including a real frame's bounded font-lock colors, plus its real header-line and tab-line faces plus per-run bold/italic and overlay-aware faces), EUP-resolved Scene title application, optional face-colored fallback text, and popup-menu, tool-bar, and dialog interaction that each share one geometry source with its draw path (including popup pointer hover and keyboard navigation), with all mirror text (body, mode line (including its own per-segment faces and box), aux lines, menu, dialogs, tool bar (including its real face colors and box), tooltips, IME) drawn in the frame font the live mouse-face highlight under the mirror pointer, and the frame echo area mirrored into the bottom strip | Production shaped glyph runs, persistent glyph atlas ownership, font metrics/fallback parity, full faces, image presentation, submenu paths beyond the depth-four model, native widgets, GPU timestamps | `sdl3-ui-smoke`, `sdl3-renderer-smoke`, `sdl3-pointer-smoke`, `sdl3-epxl-interactive-smoke`, `sdl3-epxl-unicode-input-smoke`, `sdl3-menu-hit-smoke`, `sdl3-toolbar-hit-smoke`, `sdl3-dialog-hit-smoke`, `sdl3-runtime-bridge-smoke` |
| Input | Bounded ASCII insert/delete, negotiated bounded UTF-8 text, arrows, negotiated strict down/up/repeat key v2, Ctrl+C/Ctrl+V, negotiated bounded closed-whitelist key-command descriptions, negotiated exact `C-x 1/2/3/o` window commands (smokes observe `C-x 2`, `C-x 3` plus `C-x o` navigation/edit, and `C-x 1` one-window restore), left pointer sessions, negotiated bounded left-drag selection, bounded middle-click yank, negotiated bounded single-contact `input.touch_bounded_v1` and pen-tip `input.pen_bounded_v1` translation into Pointer v2 (`sdl3-touch-tap-smoke`, `sdl3-pen-tap-smoke`), bounded vertical/horizontal line wheel, negotiated focus and strict window request observation | General keymap/command execution, IME, shaped Unicode rendering, host-applied window mutations, general selection semantics, right-button semantics, generic mouse behavior, multi-touch gestures, pen pressure/tilt/barrel buttons, pixel scroll | `sdl3-input-translate-smoke`, `sdl3-epxl-input-smoke`, `sdl3-epxl-unicode-input-smoke`, `sdl3-epxl-key-v2-smoke`, `sdl3-key-modifier-smoke`, `sdl3-emacs-window-split-smoke`, `sdl3-emacs-window-navigation-smoke`, `sdl3-emacs-window-restore-smoke`, `sdl3-epxl-edit-smoke`, `sdl3-pointer-smoke`, `sdl3-pointer-selection-smoke`, `sdl3-pointer-middle-paste-smoke`, `sdl3-pointer-v2-smoke`, `sdl3-touch-tap-smoke`, `sdl3-pen-tap-smoke`, `sdl3-wheel-smoke`, `sdl3-focus-window-smoke` |
| Desktop | Bounded UTF-8 clipboard paste/copy, with Unicode gated by negotiated `clipboard.text_unicode`; negotiated bounded PRIMARY text using the ASCII clipboard prerequisite and optional Unicode upgrade (OS-shared on X11/Wayland, app-local SDL fallback elsewhere); negotiated `dnd.bounded_v1` receive that reports one bounded text or file drop as `DND_ENTER`/`DND_DROP`/`DND_DATA` plus best-effort `DND_POSITION` feedback over the authenticated EPXL journal, with the owned publisher applying the bounded text payload | MIME negotiation, multi-offer and multi-file drops, drag-out, SECONDARY selection, platform selection ownership/target negotiation, native dialogs, native scrollbars | `sdl3-clipboard-smoke`, `sdl3-clipboard-unicode-smoke`, `sdl3-emacs-copy-smoke`, `sdl3-primary-selection-roundtrip-smoke`, `sdl3-dnd-drop-smoke` |
| Performance | Change-aware present/skip, Unicode line-texture cache counters, damage-class counters, clip counters, renderer tier reporting, bridge-owned `FRINGE_UPDATE`/`DIVIDER_UPDATE`/`BORDER_UPDATE`/`SCROLL_RUN`/`DAMAGE_RECTS`/`FLUSH`/`RENDER_HINT` emission, `CLEAR_AREA` Scene acceptance, scroll copy-plan bytes, executed scratch-target scroll copies, explicit submitted/skipped command counters, `FRAME_PRESENTED`/`FRAME_DROPPED` codec conformance, persisted opt-in ReleaseFast adapter hot-path baseline for EUP encode/decode, Scene application, atomic capture, and bounded memory send; opt-in SDL3 full-draw, unchanged-skip, typing/scroll/resize renderer-call workload-proxy CPU wall-clock benchmark with per-workload p50/p95/p99/mean, FPS, and command/frame counters; opt-in bounded EPXL edit round-trip benchmark measuring per-step intent-to-control-ACK and intent-to-next-`FRAME_UPDATE` latency percentiles against a real owned Emacs publisher | Core redisplay flush emission, renderer pacing integration, real end-to-end latency, real redisplay/typing/scroll/resize benchmarks, a performance-improvement claim, GPU timestamps, PGTK comparison, host-independent regression evidence, comprehensive GPU-tier comparisons | `proto-ui-bench` (opt-in), `sdl3-renderer-bench` (opt-in), `sdl3-epxl-roundtrip-bench` (opt-in), `zig-out/proto-ui/benchmark.json`, `zig-out/proto-ui/sdl3-renderer-benchmark.json`, `zig-out/proto-ui/sdl3-epxl-roundtrip-benchmark.json`, renderer/interactive smoke diagnostics; W14 remains partial |
| Base Emacs compatibility | Existing-buffer health gate for version, text/undo, narrowing, properties, faces, windows, scroll/recenter, buffer locals, optional real PGTK frame lifecycle, and a seven-scenario deterministic TTY/PGTK semantic matrix | Proto-frame compatibility and full PGTK parity | `proto-ui-compat` (opt-in); `compatibility.pgtk_base_gate` and `compatibility.backend_semantic_matrix` are degraded and non-negotiable |
| Disabled/default isolation | Bounded marker audit of inherited C/Header/Lisp files and generated `src/config.h`; explicit owned-root/build-output exclusion; deterministic machine-readable fail-closed JSON | Runtime host registration, real `output_proto` enablement, and proto-frame compatibility | `proto-ui-isolation-audit`; `isolation.disabled_default_gate` is degraded and non-negotiable |

At the W12d checkpoint, the status audit contained 120 PGTK capability rows:
32 Degraded, 88 Pending,
0 Blocked, and 0 fully Implemented. A Degraded row always identifies both the
verified bounded subset and the parity gap that remains.

### 12.2 Largest W12d P0 gaps

1. **Graphic frame ownership.** The dynamic-module bridge observes a real Emacs process, but there is no `output_proto` terminal or graphic frame predicate.
2. **Redisplay-owned rendering.** EUP carries bounded facts rows, not authoritative glyph rows, runs, faces, fonts, or redisplay damage.
3. **Frame lifecycle and focus.** W12c proves one bounded real-frame create/update/delete bridge and W12d defines strict visibility/focus scene state, but `output_proto` frame ownership and runtime focus/visibility round trips remain absent.
4. **Capability coverage.** The bounded EPXL profile now negotiates, but resources, widgets, and the full EUP feature table are outside that set.
5. **Resource model.** Generation declarations, a bounded payload cache/eviction policy, request/evict wire contracts, bounded `STRING_DEFINE`/`STRING_DELETE`, fixed-layout `FACE_DEFINE`/`FACE_DELETE`, `FONT_DEFINE`/`FONT_DELETE`, and bounded `IMAGE_DEFINE`/`IMAGE_DATA`/`IMAGE_DELETE`, and atomic concrete `RESOURCE_SNAPSHOT` v1 restore exist. The host ABI now has a bounded face-observation seam, but snapshot presentation, runtime recovery activation, real redisplay capture and full resource parity remain pending. Font/image capture is bounded adapter groundwork only.

### 12.3 W12d minimum next milestone

The normative target is a **pure SDL3 `output_proto` UI backend** with PGTK used
only as a reference/parity backend.  PGTK must not be a runtime fallback for a
Proto frame.  The target ownership model, PGTK responsibility matrix, protocol
gaps, differential gates, and final acceptance rules are defined in
[`sdl3-pgtk-parity.md`](sdl3-pgtk-parity.md).

`runtime_bridge` now refreshes authoritative host geometry, rejects records
outside it, and emits `FRAME_UPDATE` headers from that rectangle.
`runtime_bridge` also exposes bounded lifecycle operations and marks accepted
input transactions cancelled after host-wide cancellation.
`render.glyph_face_debug_v2` binds a bounded run to a live generation-qualified
face and projects foreground/background colors in the SDL debug fallback.
`runtime_bridge` also refreshes host frame visibility/focus and projects changes
to existing EUP state messages in unit conformance.  Real platform events and
Emacs visibility still require R8.
The same smoke now delivers one SDL key and one bounded SDL text intent through
`PureRuntimeHostV1` input callbacks with result/completion tracking.  This is
not keymap or command parity.
`runtime_bridge` also observes a generation-qualified bounded `FACE_DEFINE`
record through the redisplay ABI, rejects runs whose referenced face is absent
or stale, and emits the captured resource before run application.  Real Emacs
redisplay attachment and complete face semantics remain pending.
`runtime_bridge` also observes a bounded `FONT_DEFINE` record and rejects a
face-backed font reference when the font is absent or stale.  Real font
rasterization, metrics-driven shaping, and Emacs redisplay attachment remain
pending.
The redisplay ABI also carries bounded RGBA8 `IMAGE_DEFINE` metadata and up to
four 1 KiB fragments; the bridge validates ordering and total length before
emitting existing image resources.  Full-size image capture, streaming, and
Emacs redisplay attachment remain pending.
`sdl3-runtime-bridge-smoke` presents that fake-host bridge scene through SDL3
without Emacs registration.  `runtime_bridge` can also project bounded host ASCII run payloads into existing
debug `GLYPH_RUN` messages; this remains fallback diagnostic rendering.
`runtime_bridge` proves the same host ABI can produce deterministic EUP frame
create/update/destroy messages with a fake host.  It is not runtime registration.
`runtime_bridge` can also begin a committed capture again with a strictly newer
redisplay generation, atomically reset bounded observations, and bind the next
`FRAME_UPDATE`/`FLUSH` pair to that generation.  A frame must be explicitly
accepted before flush, and flush invokes the host callback before EUP emission.
Render hints remain frame-lifetime policy.  This remains fake-host adapter
preparation, not redisplay capture.
`terminal_service` can also orchestrate fake-host terminal create/activate/
drain/delete callbacks against the bounded no-reuse registry.  It retries a
failed drain safely and tracks rollback-pending cleanup.  R7 policy approval is
recorded.  The selected adapter is unlinked by default and no Emacs terminal is
registered; explicit native-glibc linkage remains uncalled.
`proto-ui-terminal-service` emits machine-readable lifecycle/rollback evidence
and explicitly reports `emacs_registered=false` and `runtime_available=false`.
`proto-ui-host-adapter` records the versioned pure-SDL3 `output_proto` candidate
as selected by the approved, metadata-complete R7 decision.  The default
host-audit artifact remains unlinked.  Its policy forbids inherited-source
edits, PGTK/TTY runtime fallback,
and frontend Elisp/layout ownership.
`runtime_activation` defines the approved activation sequence and reverse
rollback sequence.  The controller is selection-gated and conformance tests can
exercise a linked fake-host path, but the current selected candidate remains
unlinked and the manifest is `blocked_by_linkage_or_registration` with no
registration or runtime.
`proto-ui-runtime-host-abi` projects that contract to a generated C header and
compiles a conformance translation unit.  `proto-ui-runtime-host` defines and conformance-tests a versioned five-group
PureRuntimeHostV1 ABI while keeping runtime unavailable.  It does not register a
terminal or claim output_proto.  `proto-ui-pgtk-parity-plan` emits a 48-case planned PGTK/SDL differential
matrix; it is planning policy, not parity evidence.  R7 host-registration
decision infrastructure is implemented, and `proto-ui-r7-proposal` emits a
source-authoritative pure-SDL3 registration proposal with `approved` status and
scope `policy_and_candidate_selection_only`.  The current fail-closed reason is
`runtime_host_linkage_or_registration_missing`: no terminal can be registered
and runtime remains unavailable.  The Terminal Provider Extension in
[`registration-seam.md`](registration-seam.md) remains the only registration
path.  Its TP1 generic core dispatch is not implemented or authorized.  TP2
now provides adapter-only fake-core policy conformance in
`proto-ui-tpe-registration`; it performs no production core dispatch, Emacs
registration, terminal creation, or runtime activation.
`-Dproto-ui-runtime=true` additionally
requires a native Linux glibc target, selects a target-specific static adapter
candidate, forces its ABI symbol into the temacs link, and audits the resulting
ELF with `proto-ui-r8-link`; the state is only `linked_not_registered`.
`proto-ui-r8-readiness` records the R8 entry as blocked, inventories R7
metadata, state-aware adapter linkage, explicit registration, isolation,
callback conformance, crash containment, fail-closed runtime, and rollback
requirements, and proves that no inherited source edits are declared.  Its
opt-in negative gate (`-Dr8-entry-gate=true`) fails while registration is
missing (and, without runtime linking, linkage also remains missing).
Current PGTK/SDL diagnostic bridges therefore remain non-final compatibility
evidence.
The task split and fail-closed runtime contract are defined in
[`output-proto-runtime.md`](output-proto-runtime.md); the only selected
registration path is defined in
[`registration-seam.md`](registration-seam.md).

## 13. Initial explicit limitations

These may be represented by the protocol but are not required for first completion:

* XWidget rendering.
* Raw GPU command buffers.
* Shader graph exposure.
* Untrusted remote transport.
* Non-uniform X/Y scale.
* Frontend ownership of Emacs layout.
