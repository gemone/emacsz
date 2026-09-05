# Emacs UI Protocol (EUP) v1

Status: normative protocol design
Transport-neutral, little-endian wire protocol
This document defines the complete v1 message surface and payload semantics.

## 1. Protocol purpose

EUP describes Emacs display state and user intent. It does not describe buffer text for frontend layout, Elisp semantics, GPU command buffers, or renderer implementation.

Core rules:

1. Emacs redisplay is authoritative.
2. The preferred display message is one composite `FRAME_UPDATE`.
3. Control and resources are reliable.
4. Frame updates may coalesce.
5. All resources are generation-qualified.
6. Unknown optional capabilities and messages are safely ignorable.

## 2. Roles

| Role | Display data | Input data | Responsibility |
|---|---|---|---|
| Core/backend | Producer | Consumer | Owns semantic truth and translates redisplay |
| Frontend | Consumer | Producer | Renders state and reports user/platform intent |
| Replay tool | Producer or observer | Optional injector | Deterministic replay and inspection |
| Diagnostic tool | Observer | None | Reads counters without mutating UI |

## 3. Envelope

Every transport message has a fixed envelope followed by payload.

| Field | Type | Meaning |
|---|---|---|
| `magic` | 4 bytes | `"EUP1"` |
| `major` | u16 | Incompatible protocol major version |
| `minor` | u16 | Compatible protocol minor version |
| `flags` | u16 | Message attributes |
| `message_type` | u16 | Stable message ID |
| `header_size` | u16 | Fixed to 62 in EUP v1 |
| `payload_size` | u32 | Payload byte count for this fragment |
| `sequence` | u64 | Session-wide producer sequence |
| `ack_sequence` | u64 | Highest contiguously processed sequence |
| `session_id` | u64 | Session identity |
| `frame_id` | u32 | Target frame; zero means session-scoped |
| `reserved` | u32 | Must be zero |
| `timestamp_ns` | u64 | Sender monotonic timestamp |
| `payload_hash` | u32 | CRC-32C over payload; zero if disabled |

All integers are little-endian. `payload_size` excludes the envelope.

## 4. Envelope flags

| Flag | Meaning |
|---|---|
| `SNAPSHOT` | Complete state rather than incremental state |
| `DELTA` | Incremental update |
| `COALESCABLE` | May be dropped if superseded |
| `REQUIRES_ACK` | Receiver must advance acknowledgment |
| `FRAGMENTED` | One fragment of a multi-envelope message |
| `LAST_FRAGMENT` | Final fragment |
| `COMPRESSED` | Payload uses negotiated compression |
| `ENCRYPTED` | Transport-level negotiated encryption is applied |
| `IDEMPOTENT` | Safe after replay |
| `DEBUG` | Diagnostic-only; receiver may drop |

## 5. Delivery classes

| Class | Reliability | Ordering | Overflow behavior |
|---|---|---|---|
| Control | Reliable | Ordered | Never drop |
| Resource | Reliable | Ordered by resource | Never drop |
| Frame | Best effort | Per-frame ordered | Coalesce superseded updates |
| Input | Reliable, low latency | Per-device ordered | Never drop |
| Diagnostic | Best effort | Unordered | May drop |

Resource and control pressure may pause message production. Frame pressure must not block Emacs redisplay.

## 6. Identity and units

### 6.1 IDs

| Object | Identity |
|---|---|
| Session | u64 |
| Frame | u32 |
| Window | u32 |
| Row | u32 |
| Render run | u32 |
| Face | u32 + generation |
| Font | u32 + generation |
| Image | u32 + generation |
| Fringe bitmap | u32 + generation |
| Icon | u32 + generation |
| String | u32 + generation |
| Glyph atlas | u32 + generation |
| Menu/dialog | u32 + generation |

Generation zero is reserved.

### 6.2 Coordinates

Default coordinates are logical pixels relative to frame content top-left:

```text
x increases right
y increases down
physical = round(logical * scale)
```

v1 requires uniform scale. Geometry must distinguish outer, content, text, window, and body rectangles.

### 6.3 Time and color

Timestamps are monotonic nanoseconds. Semantic colors are sRGB RGBA8. Pixel surfaces use premultiplied-alpha RGBA8 unless another format is explicitly negotiated.

## 7. Capability negotiation

`CAPABILITIES` contains:

| Section | Contents |
|---|---|
| Versions | Supported major/minor range |
| Feature set | Named capability flags and parameters |
| Limits | Payload, frames, windows, resources, textures |
| Formats | Pixel, image, compression, color space |
| Renderer profile | Software, GPU basic, GPU advanced, hybrid |
| Widget profile | Native, custom GPU, custom CPU, glyph fallback |
| Transport profile | Shared memory, socket, fragmentation, security |
| Diagnostics profile | Counters and trace levels |

Both sides send capabilities. Effective capability is the intersection. Unknown optional capabilities are ignored. Missing required capabilities cause deterministic downgrade or session termination.

See [`capabilities.md`](capabilities.md).

## 8. Message ID ranges

| Range | Class |
|---|---|
| `0x0001-0x00ff` | Session/control |
| `0x0200-0x02ff` | Frame |
| `0x0300-0x03ff` | Window |
| `0x0400-0x04ff` | Render/damage |
| `0x0500-0x05ff` | Resource/atlas |
| `0x0600-0x06ff` | Input/platform |
| `0x0700-0x07ff` | IME |
| `0x0800-0x08ff` | Selection/clipboard/DND |
| `0x0900-0x09ff` | Widgets |
| `0x0a00-0x0aff` | Diagnostics |
| `0xf000-0xfffe` | Extension |
| `0xffff` | Invalid |

## 9. Session and control messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0001` | `HELLO` | F→C | Versions, role, transport profile | Start negotiation |
| `0x0002` | `HELLO_ACK` | C→F | Selected version, session ID | Accept connection |
| `0x0003` | `CAPABILITIES` | C→F | Backend capability set | Declare backend |
| `0x0004` | `CAPABILITIES_ACK` | F→C | Frontend capability set | Declare frontend |
| `0x0005` | `SESSION_READY` | C→F | Effective capabilities, next sequence | Normal traffic may begin |
| `0x0006` | `READY_ACK` | F→C | Effective capability hash | Frontend initialized |
| `0x0007` | `SESSION_SUSPEND` | C→F | Reason | Pause frame updates |
| `0x0008` | `SESSION_RESUME` | C→F | Resume generation | Resume updates |
| `0x0009` | `SESSION_RESUMED` | C→F | Next sequence | Resume confirmed |
| `0x000a` | `SESSION_CLOSE` | C/F | Reason | Ordered close |
| `0x000b` | `PING` | C/F | Timestamp | Liveness probe |
| `0x000c` | `PONG` | C/F | Original timestamp | Liveness reply |
| `0x000d` | `ERROR` | C/F | Code, severity, message reference, detail | Recoverable or fatal error |
| `0x000e` | `VERSION_MISMATCH` | C/F | Required/observed version | Fatal session error |
| `0x000f` | `RESYNC_REQUEST` | F→C | Missing sequences/resources | Request snapshot/replay |
| `0x0010` | `RESYNC_BEGIN` | C→F | Scope | Snapshot follows |
| `0x0011` | `RESYNC_COMPLETE` | C→F | Coherent sequence | Resume normal traffic |

## 10. Frame messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0200` | `FRAME_CREATE` | C→F | W3 lifecycle payload (section 28.4) | Create the frontend frame view |
| `0x0201` | `FRAME_PATCH` | C→F | Parameter patch | Update parameters |
| `0x0202` | `FRAME_SNAPSHOT` | C→F | Complete frame state | Initialization/resync |
| `0x0203` | `FRAME_UPDATE` | C→F | Composite display batch | Primary production hot path |
| `0x0204` | `FRAME_PRESENTED` | F→C | Present timestamp/stats | Presentation feedback |
| `0x0205` | `FRAME_DROPPED` | F→C | Reason/last presented sequence | Presentation diagnostics |
| `0x0206` | `FRAME_DESTROY` | C→F | Frame ID/generation | Destroy surface/window |
| `0x0207` | `FRAME_GEOMETRY` | C→F | Outer/content/text rectangles | Geometry state |
| `0x0208` | `FRAME_VISIBILITY` | C→F | Visible/iconified | Visibility state |
| `0x0209` | `FRAME_TITLE` | C→F | String resource | Window title |
| `0x020a` | `FRAME_ICON` | C→F | Icon resource or null | Frame/app icon |
| `0x020b` | `FRAME_FULLSCREEN` | C→F | Fullscreen mode | Fullscreen state |
| `0x020c` | `FRAME_MAXIMIZE` | C→F | Horizontal/vertical flags | Maximize state |
| `0x020d` | `FRAME_ALPHA` | C→F | Frame/background alpha | Transparency |
| `0x020e` | `FRAME_MONITOR` | C→F | Monitor descriptor | Monitor assignment |
| `0x020f` | `FRAME_SCALE` | C→F | Scale and DPI | Scale change |
| `0x0210` | `FRAME_FOCUS` | C→F | Focused flag | Focus state |
| `0x0211` | `FRAME_SIZE_HINTS` | C→F | Min/max/increment/aspect | Resize constraints |
| `0x0212` | `FRAME_Z_ORDER` | C→F | Above/below/top/bottom | Stack state |
| `0x0213` | `FRAME_PARENT` | C→F | Parent frame or null | Child-frame relation |
| `0x0214` | `FRAME_DECORATIONS` | C→F | Decorated/undecorated | Window decoration policy |

## 11. Window messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0300` | `WINDOW_TREE_SNAPSHOT` | C→F | Complete tree | Initialization/resync |
| `0x0301` | `WINDOW_CREATE` | C→F | Window descriptor | Add window |
| `0x0302` | `WINDOW_PATCH` | C→F | Changed fields | Update window |
| `0x0303` | `WINDOW_DELETE` | C→F | Window ID | Remove window |
| `0x0304` | `WINDOW_GEOMETRY` | C→F | Content/body rectangles | Geometry |
| `0x0305` | `WINDOW_ZONES` | C→F | Mode/header/tab/margins/fringes/scrollbars | Zone rectangles |
| `0x0306` | `WINDOW_FACE` | C→F | Face reference | Window default face |
| `0x0307` | `WINDOW_POSITION` | C→F | Buffer identity/start/point metadata | Diagnostic context |
| `0x0308` | `WINDOW_SCROLL_STATE` | C→F | Hscroll/vscroll/scrollbar state | Authoritative state |
| `0x0309` | `WINDOW_SCROLL_REQUEST` | F→C | Scroll intent | User scrollbar intent |
| `0x030a` | `WINDOW_MOUSE_HIGHLIGHT` | C→F | Rectangle/face | Mouse-face state |

`WINDOW_POSITION` is diagnostic. Frontend layout uses rows and glyph runs, not buffer content.

## 12. Composite `FRAME_UPDATE`

`FRAME_UPDATE` is the required production display message. It atomically carries all changes for one coherent frame state.

### 12.1 Payload sections

1. Update header.
2. Optional frame parameter patch.
3. Window patch table.
4. Row update table.
5. Render item table.
6. Cursor update table.
7. Fringe update table.
8. Divider/border update table.
9. Scroll optimization table.
10. Damage rectangle table.
11. Resource reference table.
12. Present hint.
13. Commit token.

### 12.2 Update header

| Field | Meaning |
|---|---|
| Frame ID/generation | Target frame |
| Sequence | Producer sequence |
| Redisplay generation | Capture generation |
| Logical size | Content logical rectangle |
| Physical size | Content physical rectangle |
| Scale/DPI | Presentation scaling |
| Damage mode | None, partial, full, state-only, resource-only |
| Update cause | Typing, cursor, scroll, resize, face, font, image, state |
| Coalesced count | Collapsed update count |
| Timestamp | Redisplay completion time |

### 12.3 Window patch

| Field | Meaning |
|---|---|
| Window ID/generation | Stable identity |
| Parent window ID | Tree relation |
| Frame-local rectangle | Authoritative layout |
| Body rectangle | Text drawing bounds |
| Zone rectangles | Mode/header/tab/margins/fringes/scrollbars |
| Default face | Face reference |
| Flags | Visibility, selected window, active modeline, scrollbar presence |
| Scroll metadata | Hscroll, vscroll, scrollbar state |

### 12.4 Row update

| Field | Meaning |
|---|---|
| Row ID | Stable row identity |
| Window ID | Owning window |
| Zone | Text, mode line, header line, tab line, margin |
| Y/height | Logical geometry |
| Ascent/descent/baseline | Text metrics |
| Background face | Row background |
| Flags | Enabled, reversed, truncated, continued, ends at ZV |
| Render item range | Items assigned to row |
| Damage rectangle | Conservative row damage |

### 12.5 Render item

Item types:

| Type | Meaning |
|---|---|
| `GLYPH_RUN` | Shaped text run |
| `GLYPHLESS_RUN` | Glyphless-character representation |
| `COMPOSITION_RUN` | Composite glyph sequence |
| `IMAGE_RUN` | Image placement |
| `STRETCH_RUN` | Stretched space |
| `RECT_RUN` | Filled rectangle |
| `FRINGE_ITEM` | Left/right fringe bitmap |
| `DIVIDER_ITEM` | Window divider |
| `CURSOR_ITEM` | Cursor rendering state |

Common fields:

| Field | Meaning |
|---|---|
| Item type | Render record type |
| Run ID | Stable cache identity |
| Window/row ID | Association |
| Area | Left margin, text, right margin |
| X/Y/base | Logical placement |
| Clip rectangle | Drawing bounds |
| Face/font references | Generation-qualified IDs |
| Direction/BiDi level | Already visually ordered |
| Item count | Number of records |

### 12.6 Glyph record

| Field | Meaning |
|---|---|
| Glyph ID | Raster or atlas key |
| Cluster | Source cluster index |
| Source charpos | Diagnostic mapping |
| Codepoint | Logical fallback |
| X/Y advance | Placement advance |
| X/Y offset | Drawing offset |
| Width/ascent/descent | Metrics |
| Flags | Zero width, combining, ligature, color, padding, box |

Visual order is decided by Emacs. Frontends must not reorder glyphs.

### 12.7 Cursor update

| Field | Meaning |
|---|---|
| Window/row ID | Location |
| Rectangle | Logical geometry |
| Style | Filled box, hollow box, bar, underline, none |
| Face ID | Cursor face |
| Active/visible | Focus and visibility |
| Blink policy | Core-defined state |
| IME rectangle | Candidate/preedit placement |

### 12.8 Damage and present hint

Damage entries contain a conservative logical rectangle, optional physical rectangle, affected window or whole-frame marker, and reason class.

Present hint fields:

| Field | Meaning |
|---|---|
| Preferred mode | Vsync, adaptive vsync, mailbox, immediate |
| Damage-only allowed | Presentation optimization hint |
| Deadline | Monotonic presentation deadline |
| Refresh interval | Expected period |
| Profile | Typing, scroll, animation, resize, idle |

Hints are non-authoritative; frontend reports actual behavior.

## 13. Granular render messages

These messages are reserved for tools, debug, and explicitly negotiated fallback paths. They are not required in the normal hot path.

| ID | Name | Direction | Semantics |
|---|---|---|---|
| `0x0400` | `BEGIN_UPDATE` | C→F | Debug update boundary |
| `0x0401` | `END_UPDATE` | C→F | Debug commit |
| `0x0402` | `ROW_SNAPSHOT` | C→F | Complete row |
| `0x0403` | `ROW_UPDATE` | C→F | Row patch |
| `0x0404` | `ROW_DELETE` | C→F | Remove row |
| `0x0405` | `GLYPH_RUN` | C→F | Glyph run |
| `0x0406` | `GLYPH_RUN_DELETE` | C→F | Remove run |
| `0x0407` | `CURSOR_UPDATE` | C→F | Cursor state |
| `0x0408` | `FRINGE_UPDATE` | C→F | Fringe item |
| `0x0409` | `DIVIDER_UPDATE` | C→F | Divider geometry/style |
| `0x040a` | `BORDER_UPDATE` | C→F | Border geometry/color |
| `0x040b` | `CLEAR_AREA` | C→F | Clear rectangle with face |
| `0x040c` | `SCROLL_RUN` | C→F | Source/destination optimization |
| `0x040d` | `DAMAGE_RECTS` | C→F | Damage array |
| `0x040e` | `FLUSH` | C→F | Present boundary |
| `0x040f` | `RENDER_HINT` | C→F | Renderer preference |

## 14. Resource messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0500` | `FACE_DEFINE` | C→F | Complete face | Create face |
| `0x0501` | `FACE_PATCH` | C→F | Attribute patch | Update face |
| `0x0502` | `FACE_DELETE` | C→F | ID/generation | Invalidate face |
| `0x0503` | `FONT_DEFINE` | C→F | Descriptor/metrics | Create font |
| `0x0504` | `FONT_PATCH` | C→F | Descriptor patch | Update font |
| `0x0505` | `FONT_METRICS` | C→F | Metric update | Authoritative metrics |
| `0x0506` | `FONT_DELETE` | C→F | ID/generation | Invalidate font |
| `0x0507` | `IMAGE_DEFINE` | C→F | Metadata/layout | Create image |
| `0x0508` | `IMAGE_DATA` | C→F | Inline or fragmented pixels | Provide pixels |
| `0x0509` | `IMAGE_DELETE` | C→F | ID/generation | Invalidate image |
| `0x050a` | `FRINGE_BITMAP_DEFINE` | C→F | Bits/geometry | Define fringe |
| `0x050b` | `FRINGE_BITMAP_DELETE` | C→F | ID/generation | Invalidate fringe |
| `0x050c` | `ICON_DEFINE` | C→F | Metadata/payload | Define icon |
| `0x050d` | `ICON_DELETE` | C→F | ID/generation | Invalidate icon |
| `0x050e` | `STRING_DEFINE` | C→F | UTF-8 text | Define repeated string |
| `0x050f` | `STRING_DELETE` | C→F | ID/generation | Invalidate string |
| `0x0510` | `RESOURCE_REQUEST` | F→C | Missing IDs | Request retransmission |
| `0x0511` | `RESOURCE_EVICT` | C→F | ID/reason | Eviction |
| `0x0512` | `RESOURCE_SNAPSHOT` | C→F | Resource set | Resync |
| `0x0513` | `ATLAS_DEFINE` | C/F | Atlas descriptor | Define glyph atlas |
| `0x0514` | `ATLAS_PAGE_UPDATE` | C/F | Page pixels | Update page |
| `0x0515` | `ATLAS_GLYPH_ADD` | C/F | Glyph entry | Add cache entry |
| `0x0516` | `ATLAS_INVALIDATE` | C/F | Page/glyph range | Invalidate cache |

Resource payload requirements:

### Face resource

Must include foreground, background, underline, overline, strike-through, box, inverse video, extend, stipple reference, font reference, and line-spacing fields where present.

### Font resource

Must include family, foundry, slant, weight, width, pixel/point size, DPI, spacing, ascent, descent, line height, average/space/max/min width, baseline offset, underline metrics, scalable flag, feature tags, variation axes, and fallback chain when available.

### Image resource

Must include dimensions, stride, pixel format, color space, alpha mode, transform, scaling filter, cache policy, animation frame count/duration, and payload location.

### Atlas glyph entry

Must include font ID/generation, glyph key/hash, variation/feature hash, size, weight/slant, page ID, rectangle, bearing, advance, and flags.

## 15. Input messages

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0600` | `KEY_EVENT` | F→C | Physical/logical key, text, modifiers, state |
| `0x0601` | `TEXT_INPUT` | F→C | Committed Unicode text |
| `0x0602` | `POINTER_EVENT` | F→C | Position, buttons, phase, modifiers |
| `0x0603` | `WHEEL_EVENT` | F→C | Deltas, unit, phase, source |
| `0x0604` | `TOUCH_EVENT` | F→C | Contacts and positions |
| `0x0605` | `GESTURE_EVENT` | F→C | Phase and transform |
| `0x0606` | `FOCUS_EVENT` | F→C | Frame/window focus |
| `0x0607` | `WINDOW_REQUEST` | F→C | Close/resize/move/fullscreen intent |
| `0x0608` | `MONITOR_EVENT` | F→C | Monitor enumeration/change |
| `0x0609` | `DPI_EVENT` | F→C | Scale/DPI change |
| `0x060a` | `THEME_EVENT` | F→C | Theme/accessibility preference |
| `0x060b` | `INPUT_DEVICE_EVENT` | F→C | Device change |
| `0x060c` | `INPUT_BATCH` | F→C | Ordered event array |

### Key event fields

```text
event_id
frame_id
timestamp_ns
device_id
physical_key
platform_key
logical_key
text
modifiers
state: pressed/released/repeat
repeat_count
layout_id
dead_key_state
caps_lock/num_lock/scroll_lock
source
```

Modifiers:

```text
shift control meta alt super hyper function
caps_lock num_lock scroll_lock
```

### Pointer event fields

```text
event_id frame_id pointer_id timestamp_ns
x y physical_x physical_y
buttons modifiers click_count
drag_phase hover source
```

Pointer events include enter, leave, motion, press, release, click, double-click, triple-click, drag, and cancel.

### Wheel event fields

```text
frame_id window_hint timestamp_ns
delta_x delta_y unit phase
source modifiers momentum
```

Units are pixel, line, or page. Sources include wheel, touchpad, gesture, and scrollbar.

## 16. IME messages

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0700` | `IME_ATTACH` | C→F | Context and policies |
| `0x0701` | `IME_DETACH` | C→F | Context ID |
| `0x0702` | `IME_FOCUS` | C→F | Focus state |
| `0x0703` | `IME_CURSOR_RECT` | C→F | Candidate/preedit rectangle |
| `0x0704` | `IME_ALLOWED_INPUT` | C→F | Input policy |
| `0x0705` | `IME_SURROUNDING_TEXT` | C→F | Text and selected range |
| `0x0706` | `IME_RESET` | C→F | Reason |
| `0x0710` | `IME_ATTACHED` | F→C | Platform details |
| `0x0711` | `IME_DETACHED` | F→C | Context ID |
| `0x0712` | `IME_PREEDIT_START` | F→C | Context ID |
| `0x0713` | `IME_PREEDIT_UPDATE` | F→C | Styled preedit segments |
| `0x0714` | `IME_PREEDIT_END` | F→C | Context ID |
| `0x0715` | `IME_COMMIT` | F→C | Committed text |
| `0x0716` | `IME_REQUEST_SURROUNDING` | F→C | Request ID |
| `0x0717` | `IME_DELETE_SURROUNDING` | F→C | Offset/length |
| `0x0718` | `IME_CANDIDATE_UPDATE` | F→C | Candidate state/geometry |
| `0x0719` | `IME_CANCEL` | F→C | Context ID |

Preedit segments include text, selection range, underline/highlight style, and conversion target.

## 17. Selection, clipboard, and DND messages

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0800` | `SELECTION_OWNER_SET` | C→F | Selection, targets, policy |
| `0x0801` | `SELECTION_OWNER_CLEAR` | C→F | Selection |
| `0x0802` | `SELECTION_LOST` | F→C | Selection/reason |
| `0x0803` | `SELECTION_REQUEST` | F→C | Target/request ID |
| `0x0804` | `SELECTION_DATA` | C→F | MIME target/data |
| `0x0805` | `SELECTION_ERROR` | C/F | Request/reason |
| `0x0810` | `CLIPBOARD_SET` | C→F | Offers/priority |
| `0x0811` | `CLIPBOARD_GET` | C→F | Selection/target request |
| `0x0812` | `CLIPBOARD_DATA` | F→C | MIME data |
| `0x0813` | `CLIPBOARD_CLEAR` | C→F | Selection |
| `0x0820` | `DND_ENTER` | F→C | Position/offers |
| `0x0821` | `DND_POSITION` | F→C | Position/actions |
| `0x0822` | `DND_LEAVE` | F→C | Drag ID |
| `0x0823` | `DND_DROP` | F→C | Position/action |
| `0x0824` | `DND_CANCEL` | F→C | Drag ID |
| `0x0825` | `DND_REPLY` | C→F | Accepted action/rejection |
| `0x0826` | `DND_DATA` | F/C | MIME payload |

Selection kinds are `PRIMARY`, `SECONDARY`, and `CLIPBOARD`. Required text targets include UTF-8 text; image and rich-text targets are optional and negotiated.

## 18. Widget messages

### Menu

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0900` | `MENU_MODEL` | C→F | Complete menu tree |
| `0x0901` | `MENU_PATCH` | C→F | Item changes |
| `0x0902` | `MENU_OPEN` | C→F | Placement/parent |
| `0x0903` | `MENU_CLOSE` | C→F | Menu ID/reason |
| `0x0904` | `MENU_RESULT` | F→C | Selected item ID |
| `0x0905` | `MENU_CANCEL` | F→C | Menu ID |
| `0x0906` | `MENU_HOVER` | F→C | Hover item ID |

Menu item fields include ID, parent, label, help, key binding, icon, enabled, selected, radio, checkbox, separator, submenu, and accelerator.

### Tool bar, dialog, tooltip, scrollbar

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0910` | `TOOLBAR_MODEL` | C→F | Complete tool bar |
| `0x0911` | `TOOLBAR_PATCH` | C→F | Item changes |
| `0x0912` | `TOOLBAR_CLICK` | F→C | Item/modifiers |
| `0x0920` | `DIALOG_OPEN` | C→F | Dialog model |
| `0x0921` | `DIALOG_UPDATE` | C→F | Changes |
| `0x0922` | `DIALOG_CLOSE` | C→F | Dialog ID/reason |
| `0x0923` | `DIALOG_RESULT` | F→C | Button/fields/path/color/font |
| `0x0930` | `TOOLTIP_SHOW` | C→F | Content/placement |
| `0x0931` | `TOOLTIP_MOVE` | C→F | New placement |
| `0x0932` | `TOOLTIP_HIDE` | C→F | Tooltip ID |
| `0x0940` | `SCROLLBAR_STATE` | C→F | Authoritative values |
| `0x0941` | `SCROLLBAR_EVENT` | F→C | Drag/page/step intent |

Dialog kinds include message, question, yes/no, yes/no/cancel, OK/cancel, prompt, error, progress, file open/save, font, color, and custom.

## 19. Diagnostic messages

| ID | Name | Direction | Payload |
|---|---|---|---|
| `0x0a00` | `PERF_STATS` | C/F | Counters/histograms |
| `0x0a01` | `FRAME_TIME` | F→C | Present timing |
| `0x0a02` | `BANDWIDTH_STATS` | C/F | Bytes/messages |
| `0x0a03` | `RESOURCE_STATS` | C/F | Cache/evictions |
| `0x0a04` | `DAMAGE_STATS` | C/F | Damage/coalescing |
| `0x0a05` | `INPUT_LATENCY` | F→C | Event timing |
| `0x0a06` | `DESYNC_REPORT` | C/F | Divergence details |
| `0x0a07` | `TRACE_BEGIN` | C/F | Trace marker |
| `0x0a08` | `TRACE_END` | C/F | Trace marker |
| `0x0a09` | `REPLAY_MARKER` | C/F | Replay checkpoint |

## 20. State machine

```text
DISCONNECTED -> CONNECTING -> NEGOTIATING -> READY
READY -> SUSPENDED -> READY
READY -> RESYNCING -> READY
any -> ERROR -> CLOSED
```

## 21. Initialization sequence

1. Frontend connects.
2. Frontend sends `HELLO`.
3. Backend sends `HELLO_ACK`.
4. Both exchange capabilities.
5. Backend sends initial resources.
6. Backend sends frames and window-tree snapshots.
7. Backend sends `SESSION_READY`.
8. Frontend sends `READY_ACK`.
9. Normal `FRAME_UPDATE` traffic begins.

## 22. Redisplay sequence

1. Emacs redisplay invokes backend hooks.
2. Backend accumulates rows, render items, cursors, fringes, dividers, scroll state, and damage.
3. At flush, backend encodes one `FRAME_UPDATE`.
4. Transport may coalesce superseded frame updates.
5. Frontend applies the payload atomically.
6. Frontend presents and sends `FRAME_PRESENTED` or `FRAME_DROPPED`.

## 23. Input sequence

1. Frontend captures a platform event.
2. Frontend converts it to EUP intent.
3. Frontend sends the event or ordered input batch.
4. Backend translates intent to Emacs input.
5. Emacs executes a command.
6. Later redisplay emits `FRAME_UPDATE`.

Input never synchronously waits for rendering.

## 24. Resynchronization

1. Frontend detects a missing resource, stale generation, or sequence gap.
2. Frontend sends `RESYNC_REQUEST`.
3. Backend sends `RESYNC_BEGIN`.
4. Backend sends missing resources.
5. Backend sends frame snapshots.
6. Backend sends a full-damage `FRAME_UPDATE`.
7. Backend sends `RESYNC_COMPLETE`.

## 25. Versioning policy

1. Major version changes may break wire compatibility.
2. Minor version additions must be safely ignorable.
3. Message IDs are never reused within a major version.
4. Tables must include counts or offsets for append-only evolution.
5. Capability keys use stable names.
6. Removing a v1 message requires EUP v2.

## 26. Limits and security

Every session negotiates:

```text
maximum payload size
maximum fragments per message
maximum active resources
maximum frames/windows
maximum texture dimensions
ring/arena watermarks
parse timeout
```

v1 targets local trusted IPC. Encryption, when present, is a transport property. Resource exhaustion must enter a degraded state or close the frontend session without crashing Emacs.

## 27. Conformance

A conformant backend:

1. Emits valid envelopes and sequences.
2. Publishes referenced resources.
3. Preserves core state ownership.
4. Handles required input messages.
5. Supports snapshot/resync or declares absence.

A conformant frontend:

1. Validates envelopes and payload tables.
2. Ignores unknown optional capabilities/debug messages.
3. Applies `FRAME_UPDATE` atomically.
4. Requests missing resources.
5. Reports presentation feedback.
6. Never invents Emacs UI state.

The primary required display message is `FRAME_UPDATE`; all granular render messages are tool/debug or explicitly negotiated fallback paths.

## 28. W1 concrete wire subset

The first protocol implementation freezes the following concrete subset. It is intentionally minimal; later W4+ tasks add concrete record schemas inside each section.

### 28.1 Envelope wire layout

The header is exactly 62 bytes, with no trailing padding:

```text
magic             4 bytes
major             u16
minor             u16
flags             u16
message_type      u16
header_size       u16
payload_size      u32
sequence          u64
ack_sequence      u64
session_id        u64
frame_id          u32
reserved          u32
timestamp_ns      u64
payload_hash      u32
payload           payload_size bytes
```

All flag bits 10-15 are reserved and invalid in v1. The v1 decoder rejects compressed, encrypted, fragmented, and lone-final-fragment payloads until those transports are negotiated and implemented. A zero `payload_hash` disables checksum validation; otherwise it is CRC-32C over payload bytes.

### 28.2 FRAME_UPDATE concrete header

`FRAME_UPDATE` payload begins with ASCII magic `"FUP1"` followed by an 88-byte header:

```text
magic                  4 bytes ("FUP1")
frame_id               u32
frame_generation       u32
sequence               u64
redisplay_generation   u64
logical_x              i32
logical_y              i32
logical_width          i32
logical_height         i32
physical_x             i32
physical_y             i32
physical_width         i32
physical_height        i32
scale                  f32
dpi_x                  f32
dpi_y                  f32
damage_mode            u8
update_cause           u8
reserved               u16
coalesced_count        u32
timestamp_ns           u64
```

The header repeats `frame_id` and `sequence` so the frontend can reject a payload attributed to the wrong envelope/frame. Frame generation must be nonzero, dimensions must be nonnegative, scale/DPI must be finite and positive.

### 28.3 W1 section envelope

After the header is a u32 section count. Each section is:

```text
section_kind    u32
record_length   u32
records         record_length bytes
```

Known section kinds are values 1 through 12 corresponding to the semantic sections in section 12. Extension section kinds are `0x8000-0xfffe`. Values 0 and 13-0x7fff are reserved in W1 and invalid. Known sections must appear in ascending order and cannot duplicate; extension sections may be interleaved.

At W1, section records are opaque byte strings for encoding/transport tests. Promoting them to concrete window, row, glyph, damage, resource, present-hint, and commit-token tables is explicitly deferred to W4–W6 and must not be assumed complete by callers.

### 28.4 W3 lifecycle payload

The W3 skeleton fixes the lifecycle payload for the two emitted lifecycle
messages.  A terminal ID is backend-private and is not part of the EUP payload.

`FRAME_CREATE` and `FRAME_DESTROY` both use this 8-byte payload:

```text
frame_id          u32
frame_generation  u32
```

`frame_id` and `frame_generation` must be nonzero.  The envelope `frame_id`
must equal the payload `frame_id`.  `FRAME_CREATE` marks generation one of a
new, non-recycled frame ID.  `FRAME_DESTROY` retains the same generation and
marks the frontend view dead.  Terminal-to-frame ownership is tracked by the
backend state machine.  W3 memory-sink messages deterministically emit
`timestamp_ns = 0`; a real transport replaces this with a monotonic timestamp.

### 28.5 W4a/W4b/W4c-a FRAME_UPDATE wire subset

`FRAME_UPDATE` payload begins with ASCII magic `"FUP1"` followed by the
concrete 88-byte header described conceptually in section 12.  After the
header is a u32 section count followed by length-prefixed sections.

The W4a/W4b/W4c-a encoder emits these known sections in ascending order:

1. `WINDOWS` (kind 2), for captured window geometry.
2. `ROWS` (kind 3), for captured row metadata.
3. `CURSORS` (kind 5), when a cursor was captured.
4. `DAMAGE` (kind 9), emitting captured rectangles or one conservative
   full-frame fallback.
5. `PRESENT_HINT` (kind 11).

The window record is 40 bytes:

```text
window_id         u64
frame_id          u32
x                 i32
y                 i32
width             i32
height            i32
reserved          12 bytes
```

The row record is 56 bytes:

```text
window_id         u64
row_index         u32
flags             u32
x                 i32
y                 i32
width             i32
height            i32
ascent            i32
descent           i32
baseline          i32
visible_height    i32
reserved          8 bytes
```

The cursor record is 56 bytes:

```text
window_id         u64
x                 i32
y                 i32
width             i32
height            i32
cursor_kind       u8
visible           u8
active            u8
reserved          29 bytes
```

The damage record is 16 bytes:

```text
x                 i32
y                 i32
width             i32
height            i32
```

The present-hint record is 16 bytes:

```text
present_mode      u32 (0 = vsync in W4a/W4b/W4c-a)
flags             u32 (bit 0 = damage-only allowed)
deadline_ns       u64 (0 = no deadline)
```

In W4b/W4c-a, row `flags` is `0`.  All `reserved` bytes in the window, row,
and cursor records are zero; the present-hint record has no reserved bytes.
The row and damage caps are each 256 records per frame update.  W4c-a and
W4c-a emits captured damage rectangles and sets header `damage_mode = 1`
(partial); when no rectangle was captured the encoder emits one conservative
full-frame rectangle and sets `damage_mode = 2` (full).  When either capture
exceeds its cap, the
backend marks the update capture failed and rejects/cancels the flush; it
never commits an incomplete update.

Window and row records are upserts for the state observed during the current
update, not a complete historical table or a guarantee that every visible
window/row was rewritten.  Row coordinates are logical window-relative pixels;
damage coordinates are logical frame-relative pixels because damage records
have no owning-window field.  A row ID is currently its zero-based window row
index.  The cursor section is optional and present only when the backend
captured a cursor; W4a capture always emits one, while non-GUI proto paths may
emit none.  The rejected W4c-b1-a real-row fixture used deterministic
placeholder metrics; it was quarantined under the adapter-first rule.  Concrete
glyph, face, font, and image tables remain W5 work and
must not be assumed present from this subset.

### 28.6 Replay-file container

W1 replay files are a transport capture, not a new EUP message:

```text
magic              4 bytes ("ERP1")
message_count      u32
message_count × message
```

Each message is:

```text
length             u32
bytes              length bytes containing one full EUP envelope/payload
```

The container is little-endian. Readers must enforce an implementation-defined maximum file size; W1 uses 64 MiB. A malformed count or length terminates the replay read without executing partial messages.
