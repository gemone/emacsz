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

### 11.1 `WINDOW_TREE_SNAPSHOT` v1 (implemented bounded adapter contract)

`WINDOW_TREE_SNAPSHOT = 0x0300` is an authoritative complete-tree state message.
Its little-endian payload is a 24-byte header followed by 1..32 fixed 48-byte
nodes.

Header:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | schema | `1` |
| 2 | 1 | flags | zero |
| 3 | 1 | reserved | zero |
| 4 | 4 | frame_id | nonzero and equal to envelope frame_id |
| 8 | 4 | frame_generation | nonzero |
| 12 | 4 | node_count | `1..32` |
| 16 | 4 | selected_window_id | nonzero and present |
| 20 | 4 | root_window_id | nonzero, present, visible, depth zero |

Node:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 8 | window_id | nonzero, unique |
| 8 | 8 | parent_window_id | zero only for root; every parent exists |
| 16 | 4 | x | nonnegative |
| 20 | 4 | y | nonnegative |
| 24 | 4 | width | nonnegative |
| 28 | 4 | height | nonnegative |
| 32 | 4 | flags | bit0 selected, bit1 visible, bits2..31 zero |
| 36 | 4 | default_face_id | may be zero |
| 40 | 1 | depth | root is zero; child depth is parent depth + one; max eight |
| 41 | 7 | reserved | zero |

Validation requires exactly one root and exactly one selected visible node. All
parent links must resolve and terminate at the root without cycles. The Scene
replaces its complete tree only after all validation succeeds. This does not yet
provide full window-management commands, buffer/bidi rows, widgets, or runtime
registration.

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

### 13.1 `GLYPH_RUN` debug-fallback v1 (implemented bounded adapter contract)

`GLYPH_RUN = 0x0405` has one explicit normative v1 encoding: an exact
little-endian 60-byte header followed by 1..120 bytes of printable ASCII
(0x20..0x7e).  It is a diagnostic fallback, **not** the normative shaped
`GLYPH_RUN`, redisplay-owned row model, face/font renderer, BiDi, or image
path.  The byte length must exactly equal `60 + text_length`; trailing bytes
are invalid.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `1` |
| 2 | 2 | `flags` | bit 0 (`debug fallback`) must be 1; bits 1..15 must be 0 |
| 4 | 2 | `direction` | `1` means visual LTR diagnostic |
| 6 | 2 | `reserved` | zero |
| 8 | 4 | `run_id` | nonzero stable identity |
| 12 | 4 | `generation` | nonzero; replacement must be strictly newer |
| 16 | 8 | `window_id` | nonzero, exists in active frame context |
| 24 | 4 | `row_index` | an existing row owned by `window_id` |
| 28 | 4 | `face_id` | zero in v1 |
| 32 | 4 | `font_id` | zero in v1 |
| 36 | 4 | `x` | nonnegative logical coordinate |
| 40 | 4 | `y` | nonnegative logical coordinate |
| 44 | 4 | `width` | nonnegative |
| 48 | 4 | `height` | nonnegative |
| 52 | 8 | `reserved` | zero |
| 60 | 1..120 | `text` | printable ASCII; no NUL, C0, DEL, or high bytes |

A v1 message is accepted only when its EUP envelope frame names the frontend's
single active frame at that frame's current generation, the referenced window
and row exist, the rectangle fits the current frame logical bounds, and there
are no more than 64 active runs after validation.  A run ID replacement is
accepted only for a strictly newer generation; stale/equal input is rejected
atomically and does not advance the expected sequence.  `FRAME_UPDATE` is
authoritative and clears all debug runs; frame deletion, resync, and scene
teardown free all owned text.

This schema has no shaping, cluster, BiDi reorder, font, face, atlas, image,
widget, Emacs capture, or `output_proto` semantics.

#### `GLYPH_RUN` v2 — face-bound debug fallback

Schema 2 keeps the same 60-byte header and 1..120 printable-ASCII body.  It adds
one generation-qualified face reference:

* `schema = 2`
* `face_id` is nonzero (offset 28)
* `face_generation` is nonzero and occupies offset 52..56
* offsets 56..60 remain zero
* `font_id` remains zero

The frontend accepts v2 only when that exact face generation is live.  Redefining
or deleting the face removes dependent debug runs.  This remains a diagnostic
ASCII fallback and does not provide shaped text, BiDi, fonts, atlas rendering, or
full Emacs face parity.

### 13.2 `GLYPH_RUN_DELETE` debug-fallback v1 (implemented bounded adapter contract)

`GLYPH_RUN_DELETE = 0x0406` is the exact identity delete for the bounded W10d
run.  The payload is exactly 24 bytes of little-endian data; truncated,
trailing, or reserved input is invalid.  It is schema-free: unlike
`GLYPH_RUN`, it carries no schema/flags header because its sole role is to
match and remove one active diagnostic run.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 4 | `run_id` | nonzero |
| 4 | 4 | `generation` | nonzero and equal to the active run generation |
| 8 | 8 | `window_id` | nonzero, exists in the active frame context |
| 16 | 4 | `row_index` | exists and is owned by `window_id` |
| 20 | 4 | `reserved` | zero |

The EUP envelope frame must name the frontend's single active frame.  A delete
succeeds only when the four identity fields exactly match one active run and
the row/window context remains valid.  It frees that run's owned text and
removes exactly that run; legacy facts text for the row resumes as the visual
fallback.  A missing active run, wrong identity, generation mismatch, invalid
context, or reserved byte is rejected atomically before mutation and does not
advance the expected sequence.  This message has no redisplay ownership,
shaping, BiDi, face/font, atlas, image, widget, Emacs capture, or
`output_proto` semantics.

## 14. Resource messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0500` | `FACE_DEFINE` | C→F | Fixed 96-byte face subset (v1) | Create/replace face |
| `0x0501` | `FACE_PATCH` | C→F | Attribute patch | Update face |
| `0x0502` | `FACE_DELETE` | C→F | ID/generation | Invalidate bounded v1 face |
| `0x0503` | `FONT_DEFINE` | C→F | Fixed 224-byte font subset (v1) | Create/replace font |
| `0x0504` | `FONT_PATCH` | C→F | Descriptor patch | Update font |
| `0x0505` | `FONT_METRICS` | C→F | Metric update | Authoritative metrics |
| `0x0506` | `FONT_DELETE` | C→F | ID/generation | Invalidate bounded v1 font |
| `0x0507` | `IMAGE_DEFINE` | C→F | Fixed 72-byte static image subset (v1) | Create/replace incomplete image |
| `0x0508` | `IMAGE_DATA` | C→F | Ordered RGBA8 fragments | Provide bounded pixels |
| `0x0509` | `IMAGE_DELETE` | C→F | ID/generation | Invalidate bounded v1 image |
| `0x050a` | `FRINGE_BITMAP_DEFINE` | C→F | Bits/geometry | Define fringe |
| `0x050b` | `FRINGE_BITMAP_DELETE` | C→F | ID/generation | Invalidate fringe |
| `0x050c` | `ICON_DEFINE` | C→F | Metadata/payload | Define icon |
| `0x050d` | `ICON_DELETE` | C→F | ID/generation | Invalidate icon |
| `0x050e` | `STRING_DEFINE` | C→F | UTF-8 text | Define repeated string |
| `0x050f` | `STRING_DELETE` | C→F | ID/generation | Invalidate string |
| `0x0510` | `RESOURCE_REQUEST` | F→C | Missing IDs | Request retransmission |
| `0x0511` | `RESOURCE_EVICT` | C→F | ID/reason | Eviction |
| `0x0512` | `RESOURCE_SNAPSHOT` | C→F | Atomic concrete resource snapshot (v1) | Replace adapter resource state |
| `0x0513` | `ATLAS_DEFINE` | C/F | Atlas descriptor | Define glyph atlas |
| `0x0514` | `ATLAS_PAGE_UPDATE` | C/F | Page pixels | Update page |
| `0x0515` | `ATLAS_GLYPH_ADD` | C/F | Glyph entry | Add cache entry |
| `0x0516` | `ATLAS_INVALIDATE` | C/F | Page/glyph range | Invalidate cache |

Resource payload requirements:

### Face resource v1 (implemented bounded adapter contract)

`FACE_DEFINE` is a fixed, little-endian 96-byte record.  This is a bounded
protocol subset and **not** full Emacs face parity.  Payload layout:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 4 | `face_id` | nonzero |
| 4 | 4 | `generation` | nonzero |
| 8 | 1 | presence bits | font, stipple, foreground, background, underline color, overline color, strike color, box color |
| 9 | 3 | reserved | zero |
| 12 | 24 | RGBA8 foreground/background/underline/overline/strike/box | foreground and background alpha must agree with their presence bit; other colors are checked by style rules |
| 36 | 1 | underline style | unspecified=0, off=1, single=2, color=3 |
| 37 | 1 | overline style | same tag space |
| 38 | 1 | strike-through style | same tag space |
| 39 | 1 | box style | none=0, simple=1, released=2, pressed=3 |
| 40 | 4 | `i32` box line width | zero unless box color is present |
| 44 | 1 | inverse video | boolean byte, 0 or 1 |
| 45 | 1 | extend | boolean byte, 0 or 1 |
| 46 | 4 | `i32` line spacing | signed |
| 50 | 8 | font id/generation | both zero when absent, both nonzero when present |
| 58 | 8 | stipple id/generation | both zero when absent, both nonzero when present |
| 66 | 30 | reserved | all zero |

A color-bearing decoration style (`color=3`) requires its corresponding color
presence bit.  `unspecified`, `off`, and `single` reject that bit.  Box style
`none` rejects box color and a nonzero width; every other box style requires a
present box color.  Decoders reject wrong size, invalid identity, malformed
optional references, invalid tags/booleans, contradictory presence, and nonzero
reserved bytes.

`FACE_DELETE` is exactly two nonzero little-endian `u32` values: `face_id` then
`generation`.  The frontend requires the next contiguous session sequence.  A
define needs a new face ID or strictly newer generation; equal/stale defines do
not mutate state.  Delete requires the exact live generation, removes the
active value, and marks the registry record deleted.  Faces are protocol-global:
frame destroy retains them, while resync and scene teardown clear them.

### String resource v1 (implemented adapter contract)

All integers are little-endian. `STRING_DEFINE` is:

```text
u32 resource_id      1..=0xffffffff, nonzero
u32 generation       1..=0xffffffff, nonzero
u32 byte_length      1..=4096
u8  bytes[byte_len]  valid UTF-8, no NUL byte
```

The decoder rejects truncation, trailing bytes, oversize, zero identity,
NUL bytes, and invalid UTF-8. `STRING_DELETE` is exactly two nonzero
little-endian `u32` values: `resource_id` then `generation`.

The frontend scene accepts these messages only at the next contiguous
session sequence. A define owns at most 64 active string payloads. A new
resource ID or a strictly newer generation is required; equal or older
generations are rejected without mutation. Delete must name the exact live
generation and marks the shared resource registry deleted while releasing the
owned payload. Resync, frame destroy, and scene teardown release all strings.

### Font resource v1 (implemented bounded adapter contract)

`FONT_DEFINE` is a fixed, little-endian 224-byte record.  It is a bounded
descriptor and is **not** a font-object, shaping, rasterization, or Emacs font
parity contract.  Payload layout:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 4 | `font_id` | nonzero |
| 4 | 4 | `generation` | nonzero |
| 8 | 1 | `family_length` | 1..64 |
| 9 | 1 | `foundry_length` | 1..32 |
| 10 | 1 | `style_length` | 1..32 |
| 11 | 1 | slant | unspecified=0, roman=1, italic=2, oblique=3 |
| 12 | 1 | spacing | unspecified=0, mono=1, proportional=2 |
| 13 | 1 | `scalable` | boolean byte, 0 or 1 |
| 14 | 1 | `fixed_pitch` | boolean byte, 0 or 1 |
| 15 | 1 | reserved | zero |
| 16 | 2 | `weight` | 1..1000 |
| 18 | 2 | `width_percent` | 50..200 |
| 20 | 4 | `pixel_size` | 0 means unspecified; otherwise <=1,048,576 |
| 24 | 4 | `point_size_tenths` | 0 means unspecified; otherwise <=1,048,576 |
| 28 | 4 | `x_dpi` | 0 means unspecified; otherwise <=4096 |
| 32 | 4 | `y_dpi` | 0 means unspecified; otherwise <=4096 |
| 36 | 4 | `ascent` | signed; 0..1,048,576 |
| 40 | 4 | `descent` | signed; 0..1,048,576 |
| 44 | 4 | `line_height` | unsigned; >= `ascent + descent` |
| 48 | 4 | `average_advance` | unsigned; <= max advance |
| 52 | 4 | `space_advance` | unsigned; <= max advance |
| 56 | 4 | `max_advance` | unsigned; >= min advance |
| 60 | 4 | `min_advance` | unsigned |
| 64 | 4 | `baseline_offset` | signed; 0..`ascent` |
| 68 | 4 | `underline_position` | signed; absolute value <= `ascent` |
| 72 | 4 | `underline_thickness` | unsigned; <= line height |
| 76 | 2 | `feature_count` | zero in v1 |
| 78 | 2 | `variation_axis_count` | zero in v1 |
| 80 | 2 | `fallback_count` | zero in v1 |
| 82 | 14 | reserved | zero |
| 96 | 64 | family bytes | first exact prefix is UTF-8, no NUL; tail zero |
| 160 | 32 | foundry bytes | first exact prefix is UTF-8, no NUL; tail zero |
| 192 | 32 | style bytes | first exact prefix is UTF-8, no NUL; tail zero |

X and Y DPI are either both unspecified or both specified.  `mono` spacing
requires `fixed_pitch`; proportional spacing rejects it.  Advance ordering and
the vertical metric ranges above are enforced.  Explicit v1 feature, variation,
and fallback counts must be zero; extension schemas require a later protocol
version.  Decoders reject wrong size, invalid identity, malformed strings,
invalid enums/booleans, contradictory/range-invalid values, nonzero extension
counts, and every nonzero reserved byte.

`FONT_DELETE` is exactly two nonzero little-endian `u32` values: `font_id`
then `generation`.  The frontend requires the next contiguous session sequence.
A define needs a new font ID or strictly newer generation; equal/stale defines
do not mutate state.  Delete requires the exact live generation, removes the
active value, and marks the shared registry record deleted.  Fonts are
protocol-global: frame destroy retains them, while resync and scene teardown
clear them.  The active table is bounded to 64; replacement remains available
at capacity.

### Image resource v1 (implemented bounded adapter contract)

`IMAGE_DEFINE` is a fixed, little-endian 72-byte record.  It declares an
incomplete static image and is **not** an Emacs image-object, decoding,
scaling, animation, or rendering parity contract.  Payload layout:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 4 | `image_id` | nonzero |
| 4 | 4 | `generation` | nonzero |
| 8 | 4 | `width` | 1..8192 pixels |
| 12 | 4 | `height` | 1..8192 pixels |
| 16 | 4 | `total_byte_count` | exactly `width * height * 4`, at most 4 MiB |
| 20 | 2 | format | `rgba8_premultiplied=1` only |
| 22 | 2 | color space | `srgb=1` only |
| 24 | 2 | alpha mode | `premultiplied=1` only |
| 26 | 2 | scaling filter | `nearest=1` or `linear=2` |
| 28 | 2 | transform | `identity=1` only |
| 30 | 2 | cache policy | `lru=1` or `pinned=2` |
| 32 | 2 | animation frame count | exactly 1 |
| 34 | 4 | animation duration ns | exactly 0 |
| 38 | 34 | reserved | all zero |

The width-times-height-times-four calculation is performed in 64-bit arithmetic
before the 4 MiB check.  Decoders reject wrong size, invalid identity, invalid
dimensions or totals, unsupported tags, animation fields, and nonzero reserved
bytes.

`IMAGE_DATA` is a little-endian 16-byte header followed by exact payload bytes:

```text
u32 image_id          nonzero
u32 generation        nonzero
u16 fragment_index    zero based and less than fragment_count
u16 fragment_count    1..256
u32 byte_length       1..65536
u8  bytes[length]     exact wire payload
```

The frontend requires fragments beginning at index zero, with no gap or
duplicate, for the exact declared generation.  A fragment must fit the declared
total.  The final expected fragment is accepted only when the assembled byte
count equals `total_byte_count`; otherwise the whole image remains incomplete
and the message is rejected.  Decoders reject truncation, trailing bytes, zero
identity, invalid fragment ranges, and oversized chunks.

`IMAGE_DELETE` is exactly two nonzero little-endian `u32` values: `image_id`
then `generation`.  A define needs a new image ID or strictly newer generation;
equal/stale defines do not mutate state and replacement resets all fragment
state.  Delete requires the exact live generation, works for complete or
incomplete payloads, frees owned bytes, and marks the shared registry deleted.
Images are protocol-global: frame destroy retains them, while resync and scene
teardown clear them.  At most 8 images are active, and the sum of their
declared pixel-byte totals is at most 4 MiB.

### Resource snapshot v1 (implemented bounded adapter contract)

`RESOURCE_SNAPSHOT` begins with two little-endian `u32` values:
`snapshot_format_version` (exactly `1`) and `entry_count` (`0..64`).  It is
followed by ordered entries.  An entry has a fixed little-endian 16-byte header
and an exact payload:

```text
u8  kind             face=1, font=2, image=3, fringe_bitmap=4, icon=5, string=6
u8  status           live=1, deleted=2
u16 reserved        zero
u32 resource_id      nonzero
u32 generation       nonzero
u32 payload_length   exact remaining bytes for this entry
u8  payload[length]
```

Entries are unique by `(kind, resource_id)`.  A deleted tombstone has a
zero-length payload and may name any known resource family.  A live record is
allowed only for the concrete v1 encodings: exact 96-byte `FACE_DEFINE` bytes,
exact 224-byte `FONT_DEFINE` bytes, 1..4096 bytes of strict UTF-8 for a string,
or an image payload consisting of exact `IMAGE_DEFINE` metadata followed by the
metadata's exact declared RGBA8 bytes.  Face/font/image payload identities must
equal the entry identity.  Live image payloads together use at most 4 MiB of
pixel bytes.  Wrong boundaries, mismatched identities, reserved bytes, invalid
UTF-8, duplicate IDs, oversized budgets, and trailing bytes are rejected.

The frontend parses and constructs an entire replacement state before mutating
the scene.  A successful snapshot atomically replaces string, face, font, and
image tables plus the shared resource registry; deleted records become registry
tombstones.  Incomplete image state is cleared or replaced.  Any decode,
allocation, capacity, or payload error leaves the prior resources and message
sequence unchanged.  Decoded snapshots own their entry array and payload bytes;
callers free them with the explicit snapshot-free API.

### Face resource (full model, pending)

Must include foreground, background, underline, overline, strike-through, box, inverse video, extend, stipple reference, font reference, and line-spacing fields where present.

### Font resource (full model, pending)

Must include family, foundry, slant, weight, width, pixel/point size, DPI, spacing, ascent, descent, line height, average/space/max/min width, baseline offset, underline metrics, scalable flag, feature tags, variation axes, and fallback chain when available.

### Image resource (full model, pending)

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

### 27.0 Assigned-message coverage

EUP v1 assigns exactly 164 message IDs.  `proto-ui-protocol-coverage` emits and
audits a source-authoritative manifest for every assigned ID.  The current
honest classification is:

| Status | IDs | Meaning |
|---|---:|---|
| `implemented_codec` | 32 | Concrete encode/decode plus Scene, bridge, transport, or smoke evidence |
| `partial` | 3 | Concrete local path exists; full payload/recovery semantics remain pending |
| `planned` | 129 | Assigned for the target protocol but not implemented |
| `reserved_diagnostic` | 0 | No assigned ID currently receives this classification |

The manifest records one status, domain, family, and evidence/gap note for every
assigned ID.  A `planned` entry must not be sent as a concrete codec or counted
as production capability.  This is completeness auditing for the protocol table,
not a claim that EUP parity is complete.

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

### 28.7 EPXL v1 local live transport

EPXL is an optional local Unix-stream framing for EUP.  It is not a replacement
for EUP capability negotiation and carries only complete EUP messages.

#### Handshake

Both directions use one exact 44-byte record:

```text
magic             4 bytes ("EPXL")
version           u16 (1, little endian)
kind              u16 (1 = client hello, 2 = server ready)
token             32 bytes
```

The publisher listens on an adapter-owned local endpoint and accepts one
client.  The client sends `client hello` containing the 256-bit token.  The
publisher compares the token with constant-time semantics, then replies with
`server ready` and a zero token.  Any bad magic, version, kind, or token is a
transport failure and closes the stream.

#### Capability negotiation

Immediately after the transport handshake, EPXL performs a bounded EUP
capability exchange:

| Order | Message | Direction | Sequence | Ack sequence | Payload |
|---:|---|---|---:|---:|---|
| 1 | `CAPABILITIES` | C→F | 1 | 0 | backend capability table |
| 2 | `CAPABILITIES_ACK` | F→C | 2 | 1 | frontend capability table |
| 3 | `SESSION_READY` | C→F | 3 | 2 | effective capability table |
| 4 | `READY_ACK` | F→C | 4 | 3 | 32-byte SHA-256 effective-set hash |

All four envelopes use session `0x1001`, `frame_id=0`, and exactly the idempotent flag. They reserve session-wide producer sequences 1..4; the facts publisher therefore starts backend frame sequences at 5 and a fresh frontend reverse-input journal starts at 5 and reconnect uses `max(existing, 5)` so pending retries and later intents remain monotonic. The effective
set is the name intersection of both advertised sets. Required names in the
EPXL profile are `protocol.v1`, `transport.epxl_local`, `session.resync`,
`frame.facts_profile`, `text.ascii_bounded`, and `renderer.sdl3`; any missing required name is
fatal. A known EPXL capability has value `"1"`; an unknown optional name is
ignored, while a malformed known value is fatal. The hash is canonical over all
negotiable EUP names in feature-declaration order (name, NUL, one presence
byte). `zig-out/proto-ui/status_manifest.json` is generated from the
authoritative adapter source and records each profile feature's status,
required/negotiable flags, and evidence gate. General EUP-wide negotiation for
resources, widgets, and the remaining feature table remains future work.

#### Frame

After the handshake, each EUP message is:

```text
length            u32 (little endian)
message           length bytes containing one complete EUP envelope/payload
```

Length zero is invalid.  The canonical local-transport ceiling is 16 MiB per
EUP message.  A malformed length closes the transport; receivers must not
expose a partial message to the scene.

#### Control frame

Control records are separate from EUP and use one exact 20-byte record:

```text
magic             4 bytes ("EPXC")
version           u16 (1, little endian)
kind              u16 (1=ACK, 2=RESYNC_REQUEST, 3=RESYNC_BEGIN, 4=RESYNC_COMPLETE)
sequence          u64 (little endian, never zero)
reserved          u32 (must be zero)
```

`ACK` confirms processing of one EPXL EUP frame.  EPXL v1 uses a
one-message sliding window: the publisher waits for ACK `N` before sending
sequence `N+1`.

The adapter facts profile uses the frozen controls for an initial-session
resync.  After an authenticated hello, the frontend sends
`RESYNC_REQUEST(sequence=1)`.  The publisher resets its scene, replies with
`RESYNC_BEGIN(1)`, sends a complete `FRAME_CREATE` and `FRAME_UPDATE` under the
same one-message ACK window, then sends `RESYNC_COMPLETE` with the last coherent
sequence.  General sequence-gap, resource, history, and publisher-crash recovery
remain future work.

The adapter-owned `0x8000` frame-update extension carries bounded facts-profile
text.  Each record is `u32 row_index`, `u32 byte_length`, and valid UTF-8 bytes
without C0 controls; the current producer limits lines to 32 and columns to 120
bytes and maps every row index to a row in the same update.  This is not the
normative `GLYPH_RUN` path and must not be used to claim shaped-text or
face/font compatibility.

The facts profile also defines the `TEXT_INPUT` payload used by
`0x0601`: `u32 byte_length` followed by valid UTF-8 bytes without NUL.
Producers limit the text to 120 bytes; the wire format is unchanged.  The
frontend sends this complete EUP message on its own frontend-to-core sequence;
the core replies with the normal EPXL `ACK` control before applying the input
intent.  Unicode delivery is gated by `input.text_unicode`; ASCII-only peers
can retain `input.text_ascii` alone.  This is not a full keyboard/keymap or IME
protocol.

#### Bounded resource-generation declarations

`FRAME_UPDATE.resources` (section kind 10) carries generation declarations, not
resource payloads. The W12b facts/EPXL contract uses an exact 16-byte record:

```text
kind              u8   (1=face, 2=font, 3=image, 4=fringe bitmap, 5=icon, 6=string)
reserved          u24  (zero)
resource_id       u32  (nonzero)
generation        u32  (nonzero)
flags             u32  (zero)
```

A section may contain at most 64 unique declarations for this profile. The
frontend validates the complete update before committing it. A declaration for
an existing resource kind/id must have a strictly newer generation; older or
equal generations are stale and reject the update atomically. Payload delivery,
deletion messages, snapshots, eviction, missing-resource requests, and actual
face/font/image content remain future resource-model work.

W12e adds the first strict request/eviction wire forms and a bounded adapter
payload cache policy, while leaving actual resource payload formats for their
specific `*_DEFINE` and `*_DATA` messages.

`RESOURCE_REQUEST` uses:

```text
count            u32 (at most 64)
record[count]:
  kind           u8   (1..6)
  reserved       u24  (zero)
  resource_id    u32  (nonzero)
  generation     u32  (0 means latest)
```

Records are unique by kind/resource-id. Truncated or oversized tables, unknown
kinds, duplicate records, zero IDs, and nonzero reserved bytes are invalid.

`RESOURCE_EVICT` uses exactly one 16-byte record:

```text
kind             u8   (1..6)
reserved         u24  (zero)
resource_id      u32  (nonzero)
generation       u32  (nonzero)
reason           u8   (0=lru, 1=capacity, 2=generation, 3=explicit)
reserved         u24  (zero)
```

The adapter-owned payload cache stores at most 32 entries and 16384 total
bytes, with a 4096-byte per-payload ceiling. Replacement requires a strictly
newer generation and evicts only the minimum necessary least-recently-used
entries. This does not imply full resource transport or rendering.

#### Frame visibility and focus state

W12d defines the first strict state payloads for two already-assigned frame
messages. Both are core-to-frontend authority about one active frame
generation:

```text
frame_id          u32 (nonzero, equal to envelope frame_id)
generation        u32 (nonzero)
state             u8
reserved          u24 (zero)
```

For `FRAME_VISIBILITY`, state is `0=hidden`, `1=visible`, or `2=iconified`.
For `FRAME_FOCUS`, state is a Boolean: `0=unfocused` and `1=focused`.
Truncated or oversized payloads are invalid. Receivers must reject unknown
state values and any nonzero reserved byte.

A new frame starts visible and unfocused. Changing to hidden or iconified
clears focus. Setting focus requires visibility; clearing focus is valid in
every visibility state. A stale or destroyed generation is invalid. These
contracts currently stop at the adapter/frontend scene; no runtime Emacs focus
or visibility round trip is claimed.

The facts profile also defines a deliberately bounded `KEY_EVENT` payload for
`0x0600`: `u16 action` (`1=backspace`, `2=cursor-left`, `3=cursor-right`,
`4=cursor-up`, `5=cursor-down`, `6=copy`), `u8 state` (`1=pressed`), and
`u8 modifiers` (`0=none`).  No other key, state, modifier, repeat, keymap, command, macro, IME,
or Unicode-key surface is accepted.  Like text input, it
uses a separate frontend-to-core sequence and requires an EPXL `ACK` before the
intent is applied.

Within `KEY_EVENT`, `u16 action=0` is a backward-compatible v2
discriminator. The next `u16` is exactly `2`. The remaining payload is:
`u8 state` (`1=down`, `2=up`, `3=repeat`), `u32 modifiers`, `u32
physical_key` (nonzero), `u32 repeat_count`, `u32 device_id` (`0` local),
`u32 layout_id` (`0` default), `u8 logical_key_length` (0..64), `u8
text_length` (0..120), logical-key UTF-8, and text UTF-8. Modifier bits are
shift/control/meta/alt/super/hyper/function/caps-lock/num-lock/scroll-lock
from bit zero; unknown bits are invalid. Repeat count is zero for down/up and
at least one only for repeat. Exact length, valid UTF-8, and no NUL are
mandatory. This negotiation-gated profile carries intents only; it is not a
keymap or command execution protocol.

The facts profile reserves extension section `0x8001` for bounded viewport
metadata. A `FRAME_UPDATE` may carry at most one such section; its payload is
exactly `i32 window_start_line` followed by `i32 window_visible_lines`. The
producer derives both from public Emacs window observation and caps the
rendered line count to the facts-profile row limit. The viewport section is
validated and committed atomically with the update. Extension section `0x8000`
remains the separate bounded text-line records section.

The facts profile defines a deliberately bounded `WHEEL_EVENT` subset for
`0x0603`: `u8 unit` (`1=line`), `u8 source` (`1=wheel`), `u8 modifiers`
(`0=none`), `i8 x` (`0` in this profile), `i8 y` (`-8..8`, excluding zero),
and nine reserved zero bytes. Only vertical whole-line wheel ticks are
accepted. Horizontal scroll, pixel/page units, touchpad/gesture sources, smooth
deltas, and modifiers remain outside the bounded profile. Wheel intents use the
same frontend-to-core sequence and EPXL `ACK` rules as other reverse input.

The facts profile defines a deliberately bounded `POINTER_EVENT` subset for
`0x0602`: `u8 phase` (`1=motion`, `2=press`, `3=release`), `u8 button`,
`i32 x`, `i32 y`, `u8 clicks`, `u8 modifiers`, and two reserved zero bytes.
Coordinates are non-negative and at most 16383. The implemented producer
accepts zero-modifier idle motion and ordered single-left-button
press/drag/release sessions. Idle motion uses button zero; drag motion during
an active left session uses button one. A press or release uses the same EPXL
sequence and ACK rules; Emacs maps accepted endpoints through public window
position APIs and republishes the resulting point. Intermediate drag motion is
transported and ACKed but has no text-selection semantics.

Within the same `POINTER_EVENT` message, `u8 phase=0` followed by `u8
reserved=0` and `u16 schema=2` is a backward-compatible v2 discriminator. The
fixed 30-byte v2 payload is little-endian:

```text
0                u8  (v2 marker; legacy phase byte)
reserved         u8  (zero)
schema           u16 (2, little endian)
phase            u8  (1=motion, 2=press, 3=release, 4=cancel, 5=drag)
reserved         u8  (zero)
buttons          u32 (left=1, middle=2, right=4, x1=8, x2=16)
clicks           u8  (0..8)
reserved         u24 (zero)
x                i32 (0..16383)
y                i32 (0..16383)
modifiers        u32 (EUP key modifier bitset)
reserved         u32 (zero)
```

Motion is hover only with an empty button mask; drag requires a nonempty mask.
Press/release carry exactly one left/middle/right button and clicks 1..8.
Cancel carries no buttons or clicks. Unknown buttons or modifiers, nonzero
reserved fields, out-of-range coordinates, contradictory phase state, short or
trailing payloads are invalid. Delivery journals retain the active v2 mask and
click count so a drag cannot silently lose button state.

If the transport ACK is lost before disconnect, a frontend may retry the same
bounded intent with its original reverse-input sequence after authenticated
resync.  The publisher must remain idempotent at the sequence boundary: a
duplicate `KEY_EVENT`, `TEXT_INPUT`, `POINTER_EVENT`, `WHEEL_EVENT`,
`FOCUS_EVENT`, or `WINDOW_REQUEST` sequence must not be applied twice, and a
new sequence may not advance until the prior sequence has been acknowledged.

`input.pointer_selection_left` is an optional, degraded adapter semantic above
this unchanged v2 record.  When it and `input.pointer_v2` are both negotiated,
one bounded smoke action may execute left press/drag/release: press establishes
the public mark through `posn-at-x-y`, drag moves point, and release moves point
and copies an already selected printable-ASCII region of at most 120 characters
with `kill-ring-save`.  No other button, phase, window, overlay, variable-pitch,
touch, pen, or general selection semantic is implied.

`input.pointer_middle_paste` is an optional, degraded adapter semantic over the
same unchanged record.  It may be negotiated only by peers that also offer
`input.pointer_v2` and `input.pointer_selection_left`.  The sole executable case
is a zero-modifier middle release with `buttons=2` and `clicks=1` after that
adapter observed a successful bounded left selection.  It maps the release
position through public `posn-at-x-y` / `posn-point` and invokes public `yank`
once.  A middle press, modified chord, double click, other button, active
session, or paste without prior bounded selection is a no-op.  This is not X11
PRIMARY, generic mouse yank, or multi-window hit testing.

W9m defines two strict, negotiated platform observation payloads.

`FOCUS_EVENT` (`0x0606`) is exactly 20 bytes:

```text
schema           u16 (1, little endian)
phase            u8  (0=lost, 1=gained)
reserved         u8  (zero)
frame_id         u32 (nonzero adapter identity)
sdl_window_id    u32 (nonzero SDL WindowID)
reserved         u64 (zero)
```

`WINDOW_REQUEST` (`0x0607`) is exactly 32 bytes:

```text
schema           u16 (1, little endian)
request          u8  (1=close, 2=resize, 3=move, 4=fullscreen,
                      5=fullscreen-desktop, 6=maximize, 7=minimize,
                      8=restore)
reserved         u8  (zero)
sdl_window_id    u32 (nonzero SDL WindowID)
width            i32 (resize: 1..16384; otherwise zero)
height           i32 (resize: 1..16384; otherwise zero)
x                i32 (move: signed; otherwise zero)
y                i32 (move: signed; otherwise zero)
reserved         u64 (zero)
```

Unknown request values are invalid. Values that are not meaningful to the
request must be zero, so close/fullscreen/maximize/minimize/restore carry no
geometry and resize cannot carry position. Truncated, trailing, contradictory,
reserved, and zero-identity payloads reject before queue mutation. These
events are translated by the SDL frontend only when `platform.focus_window_events`
is effective. They use the ordinary one-in-flight EPXL reverse-input sequence
and ACK discipline; the smoke intentionally does not destroy Emacs in response
to a synthetic close request.

#### Security and limits

EPXL v1 is local trusted IPC, not a wide-area protocol.  The endpoint directory
filesystem permissions are part of the security boundary.  Production publishers
must generate a fresh token for every session, place the endpoint in a private
directory, constrain the token file to owner-only access, and remove stale
endpoints before listening.  Implementations must keep secret comparison
constant time.  Compression, encryption, fragment reassembly, and
external-network deployment remain transport-level future work.

#### Deterministic fuzz hardening

`proto-ui-fuzz` is the adapter-only robustness gate for decode and frontend
application boundaries.  It uses a fixed seeded PRNG, processes 4096
iterations per target by default, and completes without libFuzzer or network
access.  The seven targets are raw EUP envelopes, `FRAME_UPDATE` payloads,
capability tables, strict visibility/focus payloads, resource request/evict
payloads, key/text/pointer/wheel input codecs, and `Scene.apply` messages
derived from valid EUP seeds.

The mutation set includes bit flips, truncation, field/type flips, exact and
structural duplication, zero generations, stale generations, oversized lengths,
and nonzero reserved bytes.  Errors are expected results, every iteration owns
fresh memory, and no scene state survives an iteration.  The emitted one-line
JSON summary names the seed, iteration count, accepted/rejected counts,
targets, and pass result.  `--iterations` is capped at 100000 and `--seed`
must be nonzero; repeated runs with the same options produce identical counts.

#### Deterministic recovery differential

`proto-ui-recovery-diff` is an adapter-only convergence gate.  It compares
four routes to the same final public `Scene`: ordered live application,
authenticated `RESYNC_REQUEST` → `RESYNC_BEGIN` → `RESOURCE_SNAPSHOT` → remaining display state → `RESYNC_COMPLETE`,
ACK-loss retry through the bounded delivery journal, and ERP1
`writeReplay`/`readReplay` round trip.  The resync controls use contiguous
sequence numbers and a local constant-time MAC in the in-process fixture; this
does not replace a production transport token.  `RESYNC_BEGIN` is the only
reset point and `RESYNC_COMPLETE` only releases replay.

The ACK-loss route retains one bounded printable-ASCII intent, retries its
original sequence after resync, invokes the publisher once, and accepts the
transport ACK exactly once.  Duplicate journal and `AckTracker` ACKs are
rejected.  The canonical SHA-256 fingerprint covers frame identity, retained
frame registry state, windows, rows, ordered text, cursor, damage, present
hint, viewport, concrete face attributes, concrete font descriptors/metrics,
string bytes, image metadata, and exact image bytes.  A separate resource
subdigest is canonicalized by resource kind and ID.  Sequence numbers,
timestamps, and ACK bookkeeping are excluded because they are delivery
metadata rather than display truth.

The executable emits one deterministic JSON object with all four per-path
digests, one common final digest, the concrete resource digest, resource
counts, accepted-operation count, and `pass`.  Any
digest difference, malformed control order, duplicate side effect, or invalid
token fails.  The gate has no socket, no Emacs process, no transport listener,
and no `output_proto` activation.
