# Proto-UI Capability and Compatibility Matrix

Status: normative design baseline
Reference backend: PGTK
Protocol: EUP v1

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
| `window_tree` | Required | core/backend | Backend cannot operate |
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
| `scroll_optimization` | Recommended | backend/frontend | Full redraw |
| `scrollbars` | Required PGTK parity | negotiated | Scrollbar hidden |
| `menu_model` | Required | core/backend | Menus unavailable |
| `native_menus` | Optional | frontend/platform | Custom renderer |
| `dialog_model` | Required | core/backend | Lisp fallback |
| `tooltips` | Required PGTK parity | negotiated | Echo-area fallback |
| `selection` | Required GUI | negotiated | Clipboard unavailable |
| `clipboard` | Required GUI | frontend | Clipboard unavailable |
| `dnd` | Optional | frontend/platform | DND unavailable |
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
| Tool bar | Core/backend | Glyph, custom, native | Visible model |
| Tab bar | Core/redisplay | Glyph/custom | Visible model |
| Dialog | Core/backend | Custom/native | Result returns |
| File dialog | Core/backend | Native/custom | Path returns |
| Color dialog | Core/backend | Native/custom | Color returns |
| Font dialog | Core/backend | Native/custom | Font spec returns |
| Tooltip | Core/backend | Custom/native | Content/placement |
| Scrollbar | Core/backend | Custom/native | Scroll intent |
| IME candidate | Platform/frontend | Platform/custom | Composition works |

## 6. PGTK parity matrix

Status is specification status, not implementation status. Current implementation status is **not started** unless explicitly changed by a later workstream report.

Priorities:

| Priority | Meaning |
|---|---|
| P0 | Required for first real SDL3 Emacs frame |
| P1 | Required for production proto UI |
| P2 | Required for complete PGTK parity |
| EXP | Protocol-defined experimental/explicitly unsupported initially |

### 6.1 Terminal/display

| Capability | PGTK equivalent | Proto requirement | Priority |
|---|---|---|---|
| Terminal creation | `create_terminal(output_pgtk)` | `create_terminal(output_proto)` | P0 |
| Terminal deletion | PGTK terminal hooks | EUP session/frame teardown | P0 |
| Graphic frame predicate | `output_pgtk` frame | `output_proto` frame | P0 |
| Focus frame | GDK focus | Frontend focus + core state | P0 |
| Multi-frame | GTK windows | Multiple SDL windows | P1 |
| Monitor attributes | GDK monitor | SDL monitor events | P1 |
| Scale factor | GDK scale | SDL display scale | P1 |
| DPI | GTK/GDK | SDL display data | P1 |
| Monitor change | GDK signal | Frontend event/redisplay | P1 |

### 6.2 Frame lifecycle

| Capability | Priority |
|---|---|
| Create/delete frame | P0 |
| Visible/invisible | P0 |
| Iconify/deiconify | P1 |
| Raise/lower | P1 |
| Restack | P1 |
| Fullscreen states | P1 |
| Maximize horizontal/vertical | P1 |
| Undecorated frame | P1 |
| Override redirect | P2 |
| Parent frame | P2 |
| Child frame | P2 |
| Tooltip frame | P2 |
| Title/name | P0 |
| Icon | P1 |
| Outer/native/text geometry | P0 |
| Size hints | P1 |
| Alpha/background alpha | P1 |
| Internal border | P0 |
| Skip taskbar | P2 |
| Sticky | P2 |
| Z-group | P2 |

### 6.3 Redisplay/rendering

| Capability | Priority |
|---|---|
| Glyph rows | P0 |
| Glyph runs | P0 |
| Character glyphs | P0 |
| Composite glyphs | P1 |
| Glyphless glyphs | P1 |
| Image glyphs | P1 |
| Stretch glyphs | P1 |
| XWidget glyphs | EXP |
| Faces | P0 |
| Cursor styles | P0 |
| Mouse face | P1 |
| Fringe bitmaps | P1 |
| Window divider | P1 |
| Vertical border | P1 |
| Mode line | P0 |
| Header line | P1 |
| Tab line | P1 |
| Tab bar | P1 |
| Tool bar | P1 |
| Menu bar | P1 |
| Scrollbar | P1 |
| Overlay arrow | P1 |
| Hourglass | P2 |
| Visible bell | P2 |
| Audible bell | P1 |
| Partial damage | P0 |
| Scroll optimization | P1 |
| Double-buffer equivalent | P1 |

### 6.4 Text/fonts

| Capability | Priority |
|---|---|
| Monospace Latin text | P0 |
| Font fallback | P1 |
| CJK text | P1 |
| BiDi ordering | P1 |
| Arabic shaping | P2 |
| Indic shaping | P2 |
| Emoji | P2 |
| Color emoji | P2 |
| Variable fonts | P2 |
| Color fonts | P2 |
| Synthetic bold/italic | P1 |
| Underline/overline/strike-through | P0 |
| Box faces | P0 |
| Baseline/line spacing | P0 |
| Frame font change | P1 |
| Fontset semantics | P1 |

### 6.5 Input/IME

| Capability | Priority |
|---|---|
| Keyboard events | P0 |
| Modifier state | P0 |
| Multibyte input | P0 |
| Dead keys | P1 |
| Mouse motion | P0 |
| Mouse buttons | P0 |
| Click count | P1 |
| Drag events | P1 |
| Wheel scroll | P0 |
| Touchpad scroll | P1 |
| Touch | EXP |
| Pen | EXP |
| Gestures | EXP |
| Focus enter/leave | P0 |
| IME activation | P1 |
| Preedit | P1 |
| Commit | P1 |
| Surrounding text | P2 |
| Candidate placement | P1 |

### 6.6 Desktop integration

| Capability | Priority |
|---|---|
| Clipboard text | P0 |
| Clipboard images | P2 |
| PRIMARY selection | P1 |
| SECONDARY selection | P2 |
| Selection ownership | P1 |
| Selection target negotiation | P1 |
| DND text | P2 |
| DND files | P2 |
| DND images | P2 |
| DND copy/move/link | P2 |
| System theme event | P2 |
| System font preference | P2 |
| App icon | P1 |
| Taskbar state | P2 |
| WM hints | P2 |

### 6.7 Widgets

| Capability | Priority |
|---|---|
| Menu bar model | P1 |
| Popup menu model | P1 |
| Native menu | Optional |
| Tool bar model | P1 |
| Dialog model | P1 |
| File dialog | P1 |
| Color dialog | P2 |
| Font dialog | P2 |
| Tooltip model | P1 |
| Scrollbar model | P1 |

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

## 12. Initial explicit limitations

These may be represented by the protocol but are not required for first completion:

* XWidget rendering.
* Raw GPU command buffers.
* Shader graph exposure.
* Untrusted remote transport.
* Non-uniform X/Y scale.
* Frontend ownership of Emacs layout.
