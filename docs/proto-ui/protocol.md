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

#### Session-control payloads

`SESSION_SUSPEND` is exactly four bytes: `u8 reason` (`1=user`,
`2=background`, `3=resource-pressure`, `4=transport-pressure`, `5=host`) and
`u24 reserved=0`. It moves the control state to suspended.

`SESSION_RESUME` is `u32 generation` (nonzero). It enters a resume-pending
state. `SESSION_RESUMED` then carries `u64 next-sequence` (nonzero), confirms
the resume, and returns control to active.

`SESSION_CLOSE` is exactly four bytes: `u8 reason` (`1=normal`, `2=shutdown`,
`3=protocol`, `4=resource`, `5=transport`) and `u24 reserved=0`. It is an
ordered terminal control state; no normal session work follows it.

`PING` and `PONG` are `u64 monotonic-timestamp` values. Zero is invalid. A
pong must equal the outstanding ping timestamp and clears that pending probe.

`ERROR` is a fixed 12-byte header followed by bounded UTF-8 detail. The header
is `u16 code` (nonzero), `u8 severity` (`1=info`, `2=warning`,
`3=recoverable`, `4=fatal`), `u8 recoverable`, `u32 message-resource-id`
(nonzero), `u16 detail-byte-length` (0..256), and `u16 reserved=0`.
`recoverable=0` or fatal severity transitions control to a fatal state.

`VERSION_MISMATCH` is `u16 required-major`, `u16 required-minor`,
`u16 observed-major`, `u16 observed-minor`. It is always fatal control state.
The standard setup state machine and bounded control state machine are
implemented. EPXL's authenticated frame stream now carries and ACKs
suspend/resume/resumed, PING/PONG, a recoverable ERROR, and normal
SESSION_CLOSE. The frontend automatically replies to PING with a
reverse-direction PONG whose payload echoes the PING timestamp; its envelope
carries the responder's monotonic send time. When standard control is
requested, both transport peers reject the session unless
`session.control_v1` was negotiated.
A fatal `VERSION_MISMATCH` is transported on a fresh connection after the
normal positive-path session closes.

### Session resynchronization payloads

`RESYNC_REQUEST` is 40 bytes: `u16 schema=1`, `u8 reason`, `u8 flags`, 4
reserved bytes, `u64 first_missing_sequence`, `u64 last_missing_sequence`,
`u64 requested_resources`, and 8 reserved bytes.  Reasons are sequence gap=1,
missing resource=2, state digest mismatch=3, and publisher restart=4.  Flags
are full snapshot=1 and resources=2.  Resource bits are faces=1, fonts=2,
strings=4, images=8, and fringe bitmaps=16.  Explicit missing ranges use
nonzero first/last with `first <= last`; sequence gaps require an explicit
range.  A resource mask requires the resources flag, and missing resources
requires that flag and a nonzero mask.  Publisher restart requires a full
snapshot.

`RESYNC_BEGIN` is 32 bytes: `u16 schema=1`, `u8 scope`, 5 reserved bytes,
`u64 nonzero resync_id`, `u64 nonzero first_sequence`, and 8 reserved bytes.
Scopes are display-only=1, resources-only=2, and full=3.  Scope follows the
request: full flag requires full; resources plus a nonzero mask requires
resources-only; otherwise display-only.  An explicit gap requires
`first_sequence == request.first_missing_sequence`.  The frontend scene may
discard old display truth only at this authorized point.

`RESYNC_COMPLETE` is 32 bytes: `u16 schema=1`, 6 reserved bytes,
`u64 nonzero resync_id`, `u64 nonzero coherent_next_sequence`, and 8 reserved
bytes.  The ID must match BEGIN, and coherent next must be after the last
missing sequence for an explicit gap.

These EUP controls are distinct from the smaller authenticated EPXC control
records.  They define payload, ordering, and state ownership; real runtime
history replay and publisher-crash recovery remain separate work.

## 10. Frame messages

| ID | Name | Direction | Payload | Semantics |
|---|---|---|---|---|
| `0x0200` | `FRAME_CREATE` | C→F | W3 lifecycle payload (section 28.4) | Create the frontend frame view |
| `0x0201` | `FRAME_PATCH` | C→F | Parameter patch | Update parameters |
| `0x0202` | `FRAME_SNAPSHOT` | C→F | Bounded core presentation state | Initialization/resync |
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
| `0x0212` | `FRAME_Z_ORDER` | C→F | Raise/lower/top/bottom/above/below | Stack state |
| `0x0213` | `FRAME_PARENT` | C→F | Parent frame or null | Child-frame relation |
| `0x0214` | `FRAME_DECORATIONS` | C→F | Decorated/undecorated | Window decoration policy |

#### `FRAME_PATCH` v1 (implemented bounded adapter contract)

`FRAME_PATCH = 0x0201` is an exact 40-byte atomic parameter patch.  Layout:

```text
offset size field
0      2    schema = 1
2      2    presence mask (nonzero; no unknown bits)
4      4    frame generation (nonzero)
8      1    visibility enum (0 hidden, 1 visible, 2 iconified)
9      1    focused strict boolean
10     1    decorated strict boolean
11     1    reserved = 0
12     2    active opacity (0..10000)
14     2    inactive opacity (0..10000)
16     2    background opacity (0..10000)
18     2    reserved = 0
20     4    scale (finite, >0, <=64)
24     4    DPI X (finite, >0, <=4096)
28     4    DPI Y (finite, >0, <=4096)
32     8    reserved = 0
```

The presence mask selects visibility, focus, alpha, decorations, or scale;
unknown or empty masks are rejected. All fields, including fields excluded by
the mask, are decoded and range-checked. A selected nonvisible state clears
stored focus; explicit `focused=1` together with that nonvisible state, or while
the current frame is nonvisible, is rejected before any field is applied.

The Scene validates the active frame/envelope identity and current lifecycle
state before applying any selected field.  It updates visibility/focus in the
frame registry and stores alpha, decoration, and scale values.  This patch is
bounded batch evidence only: title, geometry, monitor, z-order, parent, size
hints, icon, and full PGTK frame semantics remain pending.

#### `FRAME_SNAPSHOT` v1 (implemented bounded core snapshot)

`FRAME_SNAPSHOT = 0x0202` is an exact 128-byte atomic core presentation
snapshot.  It requires the full presence mask and carries schema, reserved
bytes, active-frame generation, visibility, focused flag, fullscreen mode,
maximize flags, decorated flag, active/inactive/background opacity, finite scale
and X/Y DPI, plus outer/content/text/window/body rectangles.  Rectangles use
signed coordinates, positive dimensions, and overflow-safe bounds with
containment `outer ⊇ content ⊇ text/window ⊇ body`.

The little-endian layout is:

| Offset | Size | Field |
|---:|---:|---|
| `0..2` | 2 | schema, required `1` |
| `2..4` | 2 | reserved, required zero |
| `4..8` | 4 | presence, required complete mask |
| `8..12` | 4 | frame generation, nonzero |
| `12` | 1 | visibility |
| `13` | 1 | focused boolean |
| `14` | 1 | fullscreen mode |
| `15` | 1 | maximize axis mask |
| `16` | 1 | decorated boolean |
| `17` | 1 | reserved, required zero |
| `18..20` | 2 | active opacity |
| `20..22` | 2 | inactive opacity |
| `22..24` | 2 | background opacity |
| `24..28` | 4 | scale, finite positive IEEE-754 bits |
| `28..32` | 4 | X DPI, finite positive IEEE-754 bits |
| `32..36` | 4 | Y DPI, finite positive IEEE-754 bits |
| `36..52` | 16 | outer rectangle |
| `52..68` | 16 | content rectangle |
| `68..84` | 16 | text rectangle |
| `84..100` | 16 | window rectangle |
| `100..116` | 16 | body rectangle |
| `116..128` | 12 | reserved, required zero |

The envelope and Scene frame generation must agree.  The Scene validates
visibility/focus consistency and all geometry before restoring the registry and
presentation state atomically.  This restores the documented bounded core
presentation set only; title, icon, monitor, size hints, z-order, parent,
resources, redisplay rows, buffer/window tree, and the full Emacs frame-parameter
space are not included and remain governed by dedicated contracts or pending
work.

#### Frame presentation feedback

`FRAME_PRESENTED` (`0x0204`) is a fixed 56-byte frontend-to-core record:

```text
schema                   u16 = 1
flags                    u8  = 0
reserved                 u8  = 0
frame_generation         u32 (nonzero)
redisplay_generation     u64 (nonzero)
frame_sequence           u64 (nonzero)
presented_at_ns          u64 (nonzero)
frame_path_ns            u64
draw_command_count       u64
damage_kind              u8  (0..6)
reserved                 u56 = 0
```

`FRAME_DROPPED` (`0x0205`) is a fixed 48-byte frontend-to-core record:

```text
schema                     u16 = 1
flags                      u8  = 0
reserved                   u8  = 0
frame_generation           u32 (nonzero)
redisplay_generation       u64 (nonzero)
frame_sequence             u64 (nonzero)
last_presented_sequence    u64
observed_at_ns             u64 (nonzero)
reason                     u8  (1..6)
reserved                   u56 = 0
```

Drop reasons are invalid window size, render-device loss, draw failure,
superseded frame, missing resource, and limit exceeded. Damage kind distinguishes
none, initial, cursor, text, region, viewport, and unchanged presents. These
codecs and SDL counter conformance are implemented; core consumption, adaptive
pacing decisions, and GPU timestamps remain pending.

#### Frame icon state

`FRAME_ICON` (`0x020a`) references a generation-qualified complete RGBA8 image,
or clears the icon with `present=0`. The fixed 28-byte payload is:

```text
schema               u16 = 1
flags                u8  (bit 0=present; bits 1..7 reserved)
reserved             u8  = 0
image_id             u32 (nonzero when present)
image_generation     u32 (nonzero when present)
hotspot_x            i32 (zero when absent)
hotspot_y            i32 (zero when absent)
frame_generation     u32 (nonzero)
reserved             u32 = 0
```

The envelope frame ID and active frame generation must match. When present,
`Scene` requires the referenced image to be live, complete, and at least one
pixel wide/high; the hotspot must fall inside the image. `Scene` stores the
complete icon reference and clears it on frame destruction, authenticated
resync, or scene teardown. The SDL bridge creates an SDL surface from the
complete RGBA bytes and applies it to the diagnostic window. Multi-resolution
icon bundles, OS taskbar guarantees, and animated icons remain pending.

#### Frame geometry state

`FRAME_GEOMETRY` (`0x0207`) carries the complete frame geometry model in a
fixed 96-byte payload. All fields are little-endian; rectangles use logical
pixels in one outer-frame coordinate space.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | schema | `1` |
| 2 | 1 | flags | `0` |
| 3 | 1 | reserved | `0` |
| 4 | 4 | frame_generation | nonzero |
| 8 | 16 | outer | x, y, width, height as `i32` |
| 24 | 16 | content | x, y, width, height as `i32` |
| 40 | 16 | text | x, y, width, height as `i32` |
| 56 | 16 | window | x, y, width, height as `i32` |
| 72 | 16 | body | x, y, width, height as `i32` |
| 88 | 8 | reserved | zero |

Signed `i32` fields use two's-complement representation on the wire. Every
rectangle must have positive width and height, its right and bottom
edges must not exceed `INT32_MAX`, and the rectangles must nest as
`outer ⊇ content ⊇ {text, window}` and `window ⊇ body`. `Scene`
stores the complete geometry atomically and clears it on frame destruction,
authenticated resync, or scene teardown. The diagnostic SDL bridge reads that
Scene state and queries real window border sizes, but does not yet move or resize
the platform window. Emacs/runtime ownership of the authoritative values and
live resize migration remain pending.

#### Frame size hints

`FRAME_SIZE_HINTS` (`0x0211`) is a fixed 48-byte payload that expresses resize
constraints without changing frame identity:

```text
schema                       u16 = 1
flags                        u8
reserved                     u8  = 0
frame_generation             u32 (nonzero)
min_width                    u32
min_height                   u32
max_width                    u32
max_height                   u32
width_increment              u32
height_increment             u32
aspect_min_numerator         u32
aspect_min_denominator       u32
aspect_max_numerator         u32
aspect_max_denominator       u32
```

Flag bits are `1=min-size`, `2=max-size`, `4=size-increment`, and
`8=aspect-ratio`; unknown bits are invalid. A flag's values are nonzero, while
values for an absent group must be zero. If min and max are present, max must
dominate min. All width, height, and increment values must fit the platform
`c_int` range. Increments are present or absent as a pair. Aspect numerator and
denominator values must be nonzero and min must not exceed max; ordering uses
128-bit cross multiplication. The diagnostic SDL bridge applies min/max and
aspect constraints; size increments and redisplay geometry adaptation remain
pending.

#### Frame z-order state

`FRAME_Z_ORDER` (`0x0212`) carries exactly 24 little-endian bytes:

| Offset | Size | Field | Rule |
|---|---:|---|---|
| 0 | 2 | `schema` | `1` |
| 2 | 1 | `flags` | `0` |
| 3 | 1 | `reserved` | `0` |
| 4 | 1 | `operation` | `1=raise`, `2=lower`, `3=top`, `4=bottom`, `5=above`, `6=below` |
| 5 | 3 | `reserved_after_operation` | zero |
| 8 | 4 | `frame_generation` | nonzero |
| 12 | 4 | `relative_frame_id` | nonzero only for `above`/`below` |
| 16 | 4 | `relative_frame_generation` | nonzero only for `above`/`below` |
| 20 | 4 | `reserved_tail` | zero |

The `above` and `below` operations require both relative fields; all other
operations require both fields to be zero.

`Scene` stores the authoritative request and validates that a relative target
is another active frame with the exact generation. A failed request leaves the
previous stored z-order and sequence unchanged. The diagnostic SDL bridge maps
only `top` to SDL's always-on-top flag, verifies it, and restores the normal
state. Raise/lower mapping is WM-dependent, bottom has no portable SDL
operation, and relative above/below remain pending.

#### Frame parent state

`FRAME_PARENT` (`0x0213`) carries a nullable parent-frame relation in exactly
24 little-endian bytes:

| Offset | Size | Field | Rule |
|---|---:|---|---|
| 0 | 2 | `schema` | `1` |
| 2 | 1 | `flags` | bit `0=parent present`; bit `1=modal`; other bits zero |
| 3 | 1 | `reserved` | zero |
| 4 | 4 | `parent_frame_id` | nonzero only when parent-present |
| 8 | 4 | `parent_frame_generation` | nonzero only when parent-present |
| 12 | 4 | `child_frame_generation` | nonzero |
| 16 | 8 | `reserved_tail` | zero |

The envelope frame ID identifies the child and its active frame generation must
equal `child_frame_generation`. Parent-present requires both parent fields;
unparent requires both fields to be zero, and `modal` requires parent-present.
`Scene` rejects self-parenting and stores a linked relation only for another
active frame with the exact generation. It stores the relation policy and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge applies and verifies the nullable unparent path. Linked
SDL child surfaces, modal propagation, and Emacs child-frame parity remain
pending.

The envelope frame ID identifies the child and its active frame generation must
equal `child_frame_generation`. When `parent-present` is set, the parent ID and
generation must be nonzero; `modal` requires a parent. When absent, the parent
fields must be zero. `Scene` stores the relation policy and clears it on frame
destruction, authenticated resync, or scene teardown. The diagnostic SDL bridge
applies and verifies the nullable unparent path. Linked SDL child surfaces,
modal propagation, and Emacs child-frame parity remain pending.

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

#### `WINDOW_GEOMETRY` v1 (implemented bounded adapter contract)

`WINDOW_GEOMETRY = 0x0304` is an exact 52-byte little-endian record. After
`schema=1`, zero flags/reserved, a nonzero window ID, and the active frame
generation, it carries two owner-relative rectangles: `content` and `body`,
each as x/y/width/height, followed by four zero bytes. Both rectangles must be
positive. `Scene` requires the body to be contained by content, the content to
fit the live owner window, and the envelope/header frame generation to match.
It upserts one geometry per window, caps the table at 32, clears it on
authoritative frame updates/resync/teardown, removes it on window deletion, and
invalidates it when a window patch shrinks the owner. SDL draws the validated
body boundary as diagnostic evidence. This is not yet redisplay-owned layout,
zone geometry, DPI-aware layout, or complete PGTK window parity.

#### `WINDOW_ZONES` v1 (implemented bounded adapter contract)

`WINDOW_ZONES = 0x0305` is an exact 164-byte little-endian record. The 20-byte
header contains `schema=1`, zero flags/reserved, a nonzero window ID, the active
frame generation, and a `u32` presence mask. It is followed by nine fixed
16-byte rectangles. Slots 0 through 8 map, in bit order, to mode line, header
line, tab line, left margin, right margin, left fringe, right fringe,
horizontal scrollbar, and vertical scrollbar.

Every present rectangle must be owner-relative, positive, and fit the live
owner; every absent rectangle must be all zero; and all present rectangles must
be mutually disjoint. Unknown bits, empty masks, stale generations, missing
owners, and out-of-owner rectangles are rejected. When matching geometry exists,
present zones may not overlap its body; when zones already exist, a conflicting
geometry body is rejected. `Scene` performs one bounded upsert per window, caps
the table at 32, clears it on authoritative updates/resync/teardown, removes it
on window deletion, and invalidates it when a patch shrinks the owner. The SDL
diagnostic renderer draws the top edge of each present zone as evidence. This is
not redisplay-owned layout, complete zone semantics, edge/baseline rendering, or
PGTK parity.

#### `WINDOW_POSITION` v1 (implemented bounded diagnostic contract)

`WINDOW_POSITION = 0x0307` is an exact 40-byte little-endian record. After
`schema=1`, a known flags byte, a zero reserved byte, a nonzero live window ID,
and the active frame generation, it carries `buffer_id`, `buffer_generation`,
`window_start`, and `point` as nonzero `u32` values, followed by eight zero
reserved bytes. Flag bit 0 means the point is visible in the window; other
flags are invalid.

Buffer IDs are generation-qualified display identities, not buffer text. The
message carries no string, line content, overlay, match-data, narrowing, or
encoding metadata. `Scene` validates the active frame/header and live owner,
performs one diagnostic upsert per window with a 32-state cap, clears it on
authoritative frame updates/resync/teardown, and removes it on window deletion.
It is not a cursor/render command and does not implement complete point,
narrowing, invisible-text, BiDi, or viewport semantics.

#### Window patch v1 (implemented bounded adapter contract)

`WINDOW_PATCH` (`0x0302`) is a fixed 56-byte little-endian record. It starts
with `schema=1`, a `u32 presence mask`, and zero reserved words, followed by
nonzero frame ID/generation and the target `u64 window_id`. Presence bits are
`1=x`, `2=y`, `4=width`, `8=height`, `16=parent`, `32=visible`,
`64=default-face`, and `128=depth`; unknown bits or an empty mask are invalid.
Present geometry values must be nonnegative with positive width/height. A
present parent must be another live window and must not create a cycle; depth
must equal parent depth plus one and stay at most eight. The Scene applies the
patch in place. Zone rectangles are defined by `WINDOW_ZONES` v1; scroll state
and mouse-highlight records remain separate pending messages, while window
default-face state is defined by `WINDOW_FACE` v1.

#### Window create/delete lifecycle v1 (implemented bounded adapter contract)

`WINDOW_CREATE` (`0x0301`) uses a 12-byte header (`schema=1`, zero flags/reserved,
nonzero frame ID and frame generation) followed by one standard 48-byte tree
node. The node must be visible, have nonzero ID and positive geometry, use depth
at most eight, and reference its parent only when that parent already exists in
`Scene`. The child frame must be active with the envelope frame ID and current
generation. Duplicate IDs are rejected.

`WINDOW_DELETE` (`0x0303`) is a fixed 20-byte record (`schema=1`, zero
flags/reserved, nonzero frame ID/generation, nonzero window ID). Deletion is
rejected while the window still owns rows, glyph runs, cursor state, or image
placements. Successful create/delete messages update `Scene.windows`
atomically and preserve ordering. A successful delete removes dependent window
default-face and zone state. Patch, scroll state, and mouse-highlight records
remain separate.

#### `WINDOW_FACE` v1 (implemented bounded adapter contract)

`WINDOW_FACE = 0x0306` is an exact 24-byte little-endian record:

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `1` |
| 2 | 1 | `reserved` | zero |
| 3 | 1 | `flags` | zero |
| 4 | 8 | `window_id` | nonzero and live in the active frame |
| 12 | 4 | `frame_generation` | active frame generation |
| 16 | 4 | `face_id` | nonzero and live |
| 20 | 4 | `face_generation` | exactly the live face generation |

The envelope frame ID and frame header must identify the same active frame
generation. `Scene` validates the owner window and exact live face before an
atomic upsert; it retains one face state per window and at most 32 states. Face
replacement, a generation-advancing face patch, or exact-generation face delete
removes dependent states; window deletion removes the owner’s state. The SDL diagnostic renderer paints the validated
background over the owner rectangle when that background is present. This is
bounded default-face evidence only, not redisplay-owned face capture, overlays,
derived-face resolution, font shaping, or PGTK face parity.

#### `WINDOW_SCROLL_STATE` v1 (implemented bounded adapter contract)

`WINDOW_SCROLL_STATE = 0x0308` is an exact 48-byte little-endian scrollbar state
record. It carries a visibility flag, window id, active-frame generation,
content/viewport sizes, position, and track width. Unknown flags, reserved
bytes, viewport zero, content smaller than viewport, position past the scroll
range, zero/oversized track width, truncation, or stale generation are rejected.
`Scene` upserts one state per window and SDL renders a proportional vertical
track/thumb. Drag requests, horizontal scroll, and core-owned scroll semantics
remain pending.

#### `WINDOW_SCROLL_REQUEST` v1 (implemented bounded adapter contract)

`WINDOW_SCROLL_REQUEST = 0x0309` is an exact 40-byte little-endian reverse
intent.  Layout: schema (`u16=1`), kind, axis, reserved, nonzero window id,
64-bit position, 32-bit delta, active-frame generation, and four reserved
bytes.  Kind `absolute` requires nonnegative position and zero delta; kind
`relative` requires nonzero delta and zero position.  Axis is vertical or
horizontal.  Delivery requires negotiated `window.scroll_request_v1`, while
actual application remains core-owned.  Horizontal rendering and full scrollbar
semantics remain pending.

#### `WINDOW_MOUSE_HIGHLIGHT` v1 (implemented bounded adapter contract)

`WINDOW_MOUSE_HIGHLIGHT = 0x030a` is an exact 48-byte little-endian
mouse-highlight state record.  Layout: schema (`u16=1`), flags, reserved byte,
nonzero window id, active-frame generation, a 16-byte rectangle, nonzero face id
and exact live face generation, then eight reserved bytes.  The only defined
flag is `visible`; unknown flags, nonzero reserved bytes, nonpositive width or
height, negative coordinates, stale identities or generations, and truncation
are rejected.

The envelope and frame header must identify the same active frame generation.
`Scene` validates that the rectangle is contained by the owner window and that
the face is live with the exact declared generation, then upserts one state per
window with a bounded table of 32 states.  Window deletion removes dependent
states.  Face replacement, generation-advancing patch, and exact-generation
delete remove dependent states.  An authoritative `FRAME_UPDATE` clears the
table.  SDL renders a visible highlight with the live face background when that
face declares one.  This is bounded visual-state evidence only: pointer motion,
Emacs mouse-face resolution, overlays, derived faces, redisplay-owned capture,
and complete PGTK parity remain pending.

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

#### Cursor update v1 (implemented bounded adapter contract)

`CURSOR_UPDATE` (`0x0407`) is an exact 64-byte little-endian payload.  It
permits a bounded cursor move or state change without a full `FRAME_UPDATE`,
but only after an active frame update has established the Scene geometry.  A
matching window replaces that cursor in the bounded per-window cursor set; an
unknown window appends it until the 16-cursor facts-profile cap; a cap-exceeding
append is rejected. The resulting nonempty cursor set must still contain exactly
one active cursor, so an update that would leave zero or multiple active cursors
is rejected without mutating the Scene.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 2 | reserved | zero |
| 4 | 4 | `frame_generation` | `u32`, little-endian, nonzero and equal to the active frame |
| 8 | 56 | cursor record | the canonical 56-byte cursor record above |

The cursor must name a live window in the active Scene, have positive width and
height, and fit entirely inside that window.  A `WINDOW_PATCH` that would move
the cursor outside its shrunken owner is rejected without changing the window.
`cursor_kind` is transported as an opaque v1 value; cursor styles, IME-coupled
caret behavior, and redisplay-owned cursor semantics remain pending.

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

#### `GLYPH_RUN` v3 — bounded shaped atlas run (implemented adapter contract)

Schema 3 uses the same 60-byte header but changes the body to a bounded shaped
glyph array. It requires `flags = 0x0002`, LTR `direction = 1`, a live
generation-qualified face, a nonzero `font_id`, and `1..7` fixed 16-byte glyph
records. Each record contains `glyph_id`, `cluster`, signed `x_offset/y_offset`,
and unsigned `advance_x/advance_y`. The Scene validates the face/font linkage and
requires each referenced atlas glyph to exist. SDL may render the records by
atlas lookup. This is a bounded atlas-run contract, not complete OpenHarfbuzz-
level shaping, BiDi reordering, color fonts, or Emacs display parity.

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

### 13.3 `BEGIN_UPDATE` / `END_UPDATE` v1 (implemented bounded adapter contract)

`BEGIN_UPDATE = 0x0400` and `END_UPDATE = 0x0401` are exact 12-byte
little-endian transaction boundaries.  Fields are schema (`u16=1`), flags,
reserved, nonzero active-frame generation, and a nonzero update ID.  BEGIN may
not nest inside another active update; END must repeat the active update ID
exactly.  A new authoritative `FRAME_UPDATE` invalidates an open boundary.
These boundaries validate ordering and stale generation; they do not by
themselves capture or own redisplay state.

### 13.3 `BORDER_UPDATE` v1 (implemented bounded adapter contract)

`BORDER_UPDATE = 0x040a` is an exact 16-byte little-endian window-edge style
record.  It styles borders of windows owned by the active Scene frame; it does
not capture core border geometry or replace window-manager policy.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `sides` | bit 0 top, bit 1 right, bit 2 bottom, bit 3 left; nonzero and no unknown bits |
| 3 | 1 | reserved | zero |
| 4 | 4 | `thickness` | 1..64 logical pixels |
| 8 | 4 | color | RGBA bytes; alpha must be nonzero |
| 12 | 4 | `frame_generation` | nonzero, active-frame generation |

The codec validates schema, side mask, bounded thickness, opaque alpha, exact
length, and active generation.  Scene stores one latest border policy per active
frame and clears it on frame destruction, resync, or teardown.  The SDL draw
list renders only selected edges with the requested color and thickness.  Core
border geometry, resizable frame semantics, and complete WM policy remain
pending.

### 13.4 `DIVIDER_UPDATE` v1 (implemented bounded adapter contract)

`DIVIDER_UPDATE = 0x0409` is an exact 40-byte little-endian divider geometry
record.  v1 supports vertical and horizontal fixed-color dividers; draggable
hit-testing, resize layout, and redisplay-owned divider creation remain pending.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `orientation` | 1 vertical, 2 horizontal |
| 3 | 1 | reserved | zero |
| 4 | 4 | `divider_id` | nonzero |
| 8 | 4 | `divider_generation` | nonzero; replacement must be strictly newer |
| 12 | 8 | `window_id` | nonzero, exists in active frame |
| 20 | 4 | `position` | cross-axis window-relative coordinate |
| 24 | 4 | `offset` | start along divider |
| 28 | 4 | `span` | positive along divider |
| 32 | 4 | `thickness` | positive cross-section |
| 36 | 4 | `frame_generation` | nonzero, active-frame generation |

Scene owns at most 32 dividers, replaces same IDs only for strictly newer
generations, clears them on authoritative updates/teardown, and renders the
validated fixed-color geometry.  Invalid orientation, truncation, out-of-bounds
geometry, or stale generation is rejected before mutation.

### 13.4 `FRINGE_UPDATE` v1 (implemented bounded adapter contract)

`FRINGE_UPDATE = 0x0408` is an exact 40-byte little-endian color-band subset.
It supports left/right fringe geometry and generation replacement; bitmap glyph
patterns, scroll semantics, and redisplay-owned fringe capture remain pending.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `side` | 1 left, 2 right |
| 3 | 1 | reserved | zero |
| 4 | 4 | `fringe_id` | nonzero |
| 8 | 4 | `fringe_generation` | nonzero; replacement strictly newer |
| 12 | 8 | `window_id` | nonzero, exists in active frame |
| 20 | 4 | `y` | nonnegative window-relative coordinate |
| 24 | 4 | `height` | positive |
| 28 | 4 | `width` | positive and <= owner width |
| 32 | 4 | color | RGBA bytes; alpha nonzero |
| 36 | 4 | `frame_generation` | nonzero, active-frame generation |

`Scene` owns at most 32 fringe bands, replaces same IDs only for strictly newer
generations, and clears them on authoritative frame updates or teardown.  The
SDL draw list renders validated left/right bands.  Bitmap patterns and full
fringe semantics remain pending.

### 13.4 `CLEAR_AREA` v1 (implemented bounded adapter contract)

`CLEAR_AREA = 0x040b` is an exact 40-byte little-endian rectangle filled with a
live face's background color.  v1 intentionally uses a bounded render-control
subset; it does not capture or replace redisplay clear semantics.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `flags` | zero |
| 3 | 1 | reserved | zero |
| 4 | 8 | `window_id` | nonzero, exists in the active frame |
| 12 | 4 | `x` | nonnegative window-relative coordinate |
| 16 | 4 | `y` | nonnegative window-relative coordinate |
| 20 | 4 | `width` | positive |
| 24 | 4 | `height` | positive |
| 28 | 4 | `face_id` | nonzero |
| 32 | 4 | `face_generation` | nonzero and live |
| 36 | 4 | `frame_generation` | nonzero, active-frame generation |

The face must exist with the exact generation and must advertise a background
color.  `Scene` retains at most 64 validated areas and clears them on the next
authoritative `FRAME_UPDATE`, frame destruction, resync, or teardown.  Unknown
flags, nonzero reserved bytes, invalid coordinates, stale generations, missing
faces, and truncation are protocol errors.

### 13.5 `SCROLL_RUN` v1 (implemented bounded adapter contract)

`SCROLL_RUN = 0x040c` is an exact 32-byte little-endian vertical scroll-copy
hint.  v1 deliberately covers a full-window-width band only; horizontal scrolls,
composition, dirty redraw, and actual retained-frame copying remain future work.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `flags` | zero |
| 3 | 1 | reserved | zero |
| 4 | 8 | `window_id` | nonzero, exists in the active frame |
| 12 | 4 | `source_y` | nonnegative window-relative coordinate |
| 16 | 4 | `destination_y` | nonnegative window-relative coordinate |
| 20 | 4 | `width` | positive and exactly the owner width |
| 24 | 4 | `height` | positive |
| 28 | 4 | `frame_generation` | nonzero, active-frame generation |

Both `source_y + height` and `destination_y + height` must remain inside the
owner.  `Scene` retains at most 32 runs and clears them on the next
authoritative `FRAME_UPDATE`, frame destruction, resync, or teardown.  The
renderer policy computes overlap and an estimated RGBA upload saving; malformed
geometry, stale generations, horizontal runs, and truncation are errors.

### 13.6 `DAMAGE_RECTS` v1 (implemented bounded adapter contract)

`DAMAGE_RECTS = 0x040d` is a bounded variable-length damage array.  It carries
an explicitly enumerated conservative rectangle set after an accepted
`FRAME_UPDATE`; it does not itself create a new redisplay generation.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `flags` | zero in v1 |
| 3 | 1 | reserved | zero |
| 4 | 4 | `frame_generation` | nonzero, active-frame generation |
| 8 | 4 | `count` | 1..256 |
| 12 | 16*count | rectangles | canonical logical x/y/width/height records |

Every rectangle must fit the active `FRAME_UPDATE` logical bounds.  The codec
validates count, exact byte length, reserved bytes, rectangle form, and active
frame identity atomically.  Scene application replaces the previous damage
array only after every rectangle validates.  Empty arrays, truncation, trailing
bytes, stale generations, and out-of-frame rectangles are protocol errors.
Current bridge/smoke evidence carries the observed array through Scene; true
partial present and redisplay-owned incremental damage remain pending.

### 13.7 `FLUSH` v1 (implemented bounded adapter contract)

`FLUSH = 0x040e` is an exact 40-byte little-endian present boundary.  It marks
the Scene state that a frontend may treat as one render/present epoch; it does
not by itself make Emacs own a real `output_proto` terminal.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `flags` | bit 0 `present_required`, bit 1 `visible_only`; all other bits invalid |
| 3 | 1 | reserved | zero |
| 4 | 4 | `frame_generation` | nonzero, active-frame generation |
| 8 | 8 | `redisplay_generation` | nonzero |
| 16 | 8 | `frame_sequence` | nonzero |
| 24 | 8 | `deadline_ns` | monotonic nanoseconds; zero means advisory/no deadline |
| 32 | 1 | `damage_kind` | 0 none, 1 partial, 2 full, 3 state-only, 4 resource-only |
| 33 | 7 | reserved | zero |

The envelope frame ID must be nonzero and match the active Scene frame.
`redisplay_generation` and `frame_sequence` must exactly match the current
accepted `FRAME_UPDATE` header; otherwise the boundary is stale.  Accepting a
new `FRAME_UPDATE` invalidates the prior boundary.  The codec validates the
fixed form, reserved bytes, flags, identity, enum value, and length atomically.
Unknown flags, unknown damage kinds, truncation, and trailing bytes are protocol
errors.  Current smoke evidence proves Scene state and SDL acceptance; core
redisplay emission and adaptive present scheduling remain pending.

### 13.8 `RENDER_HINT` v1 (implemented bounded adapter contract)

`RENDER_HINT = 0x040f` is an exact 32-byte little-endian, non-authoritative
renderer preference.  A conformant frontend may honor it only when the selected
SDL renderer supports the mode and must otherwise continue rendering.

| Offset | Size | Field | Rule |
|---:|---:|---|---|
| 0 | 2 | `schema` | `u16`, little-endian, must be `1` |
| 2 | 1 | `flags` | bit 0 damage-only, bit 1 deadline present, bit 2 refresh interval present |
| 3 | 1 | reserved | zero |
| 4 | 1 | `preferred_mode` | 0 auto, 1 vsync, 2 adaptive vsync, 3 mailbox, 4 immediate |
| 5 | 1 | `workload` | 0 unspecified, 1 typing, 2 scroll, 3 animation, 4 resize, 5 idle |
| 6 | 2 | reserved | zero |
| 8 | 4 | `frame_generation` | nonzero, active-frame generation |
| 12 | 8 | `refresh_interval_ns` | nonzero iff flag bit 2 is set |
| 20 | 8 | `deadline_ns` | nonzero iff flag bit 1 is set |
| 28 | 4 | reserved | zero |

Unknown flags/modes/workloads, nonzero reserved bytes, missing paired values,
flag/value mismatch, truncation, and trailing bytes are protocol errors.  The
hint never changes buffer, layout, or input semantics.  Current smoke evidence
proves strict Scene acceptance, not guaranteed GPU throughput or actual
renderer-mode switching.

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
| `0x050c` | `ICON_DEFINE` | C→F | Complete RGBA8 metadata/payload (bounded v1) | Define icon |
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

### Face patch v1 (implemented bounded adapter contract)

`FACE_PATCH = 0x0501` is an exact 28-byte little-endian color patch.  Fields are
schema (`u16=1`), flags, reserved, face id, expected generation, new generation,
foreground RGBA, background RGBA, and four reserved bytes.  Flag bit 0 selects
foreground and bit 1 selects background; unselected color bytes must be zero,
selected colors require nonzero RGB and alpha, and unknown flags/reserved bytes
are invalid.  `new_generation` must be strictly greater than
`expected_generation`.  `Scene` requires the expected generation to be live,
applies only the selected colors, validates the complete face, removes dependent
debug runs from the old generation, and advances the face atomically.  This is
not full face-attribute parity.

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

#### `FONT_PATCH` v1 (implemented bounded scalar descriptor contract)

`FONT_PATCH = 0x0504` is an exact 44-byte little-endian scalar descriptor
patch.  Layout: schema (`u16=1`), zero flags and reserved byte, nonzero font id,
expected and strictly newer generation, weight (`1..1000`), width percentage
(`50..200`), pixel size, point size in tenths, X/Y DPI, slant, spacing,
scalable/fixed-pitch booleans, and four reserved bytes.  X and Y DPI remain
either both unspecified or both specified; mono/proportional spacing constraints
carry over from `FONT_DEFINE`.

The Scene requires an exact live expected generation, applies the scalar values
over the retained descriptor, revalidates the complete font, and advances the
generation atomically.  Family, foundry, style bytes, vertical metrics, advances,
underline metadata, and extension counts are retained.  Stale shaped glyph runs
that reference the font are removed so they cannot survive with stale font
semantics.  This is bounded adapter evidence only: no real font object, no
string/style metadata patch, no metric patch, no rasterization/shaping change,
and no Emacs frame-font or PGTK font parity claim is made.

#### `FRINGE_BITMAP_DEFINE` / `FRINGE_BITMAP_DELETE` v1 (implemented bounded monochrome contract)

`FRINGE_BITMAP_DEFINE = 0x050a` is an exact 144-byte little-endian monochrome
bitmap declaration.  Layout: schema (`u16=1`), zero flags/reserved, nonzero
bitmap id and generation, width and height (`1..32`), followed by 128 packed-bit
bytes.  Rows always use the 32-pixel fixed stride.  Bits are MSB-first; every
bit beyond the declared width, every row beyond the declared height, and every
reserved byte must be zero.  `FRINGE_BITMAP_DELETE = 0x050b` is exactly the
nonzero bitmap id and exact live generation.

The Scene owns a bounded table of 64 protocol-global bitmaps.  Define accepts a
new id or strictly newer generation; delete requires the exact live generation
and marks the shared registry record deleted.  Replacement or delete removes
existing fringe placements referencing that id so a stale bitmap cannot remain
visible.  `RESOURCE_SNAPSHOT` can restore a live monochrome bitmap and retain a
deleted tombstone.  The SDL renderer expands the validated bits into live fringe
placement cells; if no matching bitmap is defined, the existing color-band
fallback remains diagnostic-only.  This does not provide Emacs bitmap authoring,
color/alpha bitmaps, scaling policy, complete fringe semantics, or PGTK parity.

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

### Glyph atlas v1 (implemented bounded codec/Scene contract)

The atlas family is a bounded RGBA8 texture-publishing contract. It does not
rasterize glyphs, upload textures, shape text, or claim renderer parity.

`ATLAS_DEFINE = 0x0513` is an exact 32-byte record. It contains `schema=1`,
zero flags/reserved, nonzero `atlas_id/generation`, dimensions `1..4096`, and
`page_count` in `1..16`. The Scene keeps at most four live atlases.

`ATLAS_PAGE_UPDATE = 0x0514` has a 28-byte little-endian header followed by
exact RGBA8 bytes: `schema=1`, zero flags/reserved, live atlas identity,
`page_index/page_count`, destination `x/y`, `width/height`, and byte length.
A page region must fit the atlas; the declared length must equal
`width * height * 4` and is at most 1 MiB. A page replacement releases the old
owned bytes only after validation.

`ATLAS_GLYPH_ADD = 0x0515` is an exact 48-byte record with nonzero atlas, glyph,
and font identities, a matching atlas generation, positive glyph size and rect,
and a glyph rectangle contained by the atlas. Glyph IDs are unique per font.
The active table is bounded to 256 glyphs.

`ATLAS_INVALIDATE = 0x0516` is an exact 16-byte record with exactly one flag:
`all=1`, `page=2`, or `glyph=4`. `all` requires target zero and clears page
pixels and glyph entries; `page` requires a page index; `glyph` requires a nonzero glyph ID. A glyph
target is a glyph ID and invalidates matching entries for every font in the
atlas. Stale generation, wrong page ranges, unknown atlases, malformed flags,
and truncation are rejected. Authenticated resync and scene teardown release
atlas state. This is protocol/state groundwork, not production shaped-text
rendering.

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

### Bounded primary ownership state v1

`SELECTION_OWNER_SET` (`0x0800`), `SELECTION_OWNER_CLEAR` (`0x0801`), and
`SELECTION_LOST` (`0x0802`) now have bounded Scene state for primary ownership
only.  An owner records its generation, owner flags, and up to eight unique
target offers with priorities; a newer generation replaces it, while clear/lost
must match the live kind and generation.  The target list is ownership metadata,
not request/data transfer.  Platform ownership, target conversion, clipboard or
PRIMARY exchange, secondary selection, and request/data/error Scene handling
remain pending.

### Wheel event fields

```text
frame_id window_hint timestamp_ns
delta_x delta_y unit phase
source modifiers momentum
```

Units are pixel, line, or page. Sources include wheel, touchpad, gesture, and scrollbar.
#### Bounded touch, gesture, and platform-event v1

All integers are little-endian.  All payloads begin with `u16 schema=1`;
reserved bytes are zero on transmit and decode.  Coordinates are nonnegative
owner-relative values, IDs are nonzero, and IDs are adapter-side protocol
identities rather than Emacs terminal handles.  These are transport codecs;
SDL mapping, Scene/core application, platform ownership, and PGTK parity are
not claimed.

##### `TOUCH_EVENT = 0x0604`

Header, 20 bytes:

* `u16 schema @0`, `u8 phase @2`, `u8 contact_count @3`
* `u32 nonzero frame_id @4`, `u32 nonzero sdl_window_id @8`
* `u64 timestamp_ns @12`

Phases are begin=1, update=2, end=3, cancel=4.  Follow with 1..8 contacts.
Each contact is 16 bytes: `u16 nonzero contact_id @0`, `u16 reserved=0 @2`,
`i32 x @4`, `i32 y @8`, `u16 pressure_milli @12` (0..1000), and
`u16 major_radius @14`.  Contact IDs must be unique.

##### `GESTURE_EVENT = 0x0605`

Exact 36 bytes:

* `u16 schema @0`, `u8 kind @2`, `u8 phase @3`
* `u32 nonzero frame_id @4`, `u32 nonzero sdl_window_id @8`
* `i32 x @12`, `i32 y @16`, `i32 pan_x @20`, `i32 pan_y @24`
* `u32 nonzero scale_milli_percent @28`, `i32 rotation_milli_degrees @32`

Kinds are pan=1, pinch=2, rotate=3, long_press=4.  Phases match touch phases.
Long press requires scale 1000 milli-percent, zero rotation, and zero pan.

##### `MONITOR_EVENT = 0x0608`

Exact 36 bytes:

* `u16 schema @0`, `u8 kind @2`, `u8 reserved=0 @3`
* `u32 nonzero monitor_id @4`, `i32 x @8`, `i32 y @12`
* `i32 positive width @16`, `i32 positive height @20`
* `u32 nonzero scale_milli_percent @24`, `u32 refresh_milli_hz @28`
* `u8 flags @32`: bit 0 primary, bit 1 current, bits 2..7 zero
* 3 reserved bytes at 33

Kinds are added=1, removed=2, geometry_changed=3, primary_changed=4,
current_changed=5.

##### `DPI_EVENT = 0x0609`

Exact 28 bytes: `u16 schema`, `u16 reserved=0` at 2, `u32 nonzero frame_id @4`,
`u32 nonzero sdl_window_id @8`, `u32 nonzero scale_milli_percent @12`,
`u32 nonzero dpi_x_milli @16`, `u32 nonzero dpi_y_milli @20`, and 4 reserved
bytes at 24.

##### `THEME_EVENT = 0x060a`

Exact 16 bytes: `u16 schema`, `u8 appearance @2`, `u8 contrast @3`,
`u8 accessibility flags @4`, 3 reserved at 5, `u8[4] accent_rgba @8`, and 4
reserved at 12.  Appearance values are unknown=0, light=1, dark=2, system=3.
Flags are reduced_motion=1, reduced_transparency=2, high_contrast=4; all other
bits are invalid.

##### `INPUT_DEVICE_EVENT = 0x060b`

Exact 16 bytes: `u16 schema`, `u8 kind @2`, `u8 action @3`,
`u32 nonzero device_id @4`, `u32 capability_mask @8`, and 4 reserved at 12.
Kinds are keyboard=1, mouse=2, touchpad=3, touch=4, pen=5, gamepad=6.
Actions are added=1, removed=2, changed=3.  Added requires nonzero capabilities.

##### `INPUT_BATCH = 0x060c`

Bounded ordered framing envelope.  Header is 8 bytes: `u16 schema`,
`u16 reserved=0`, `u16 nonzero item_count` (1..16), and `u16 reserved=0`.
Each item is `u16 kind`, `u16 byte_length` (1..512), then bytes.  The sum of
item byte lengths is at most 4096 and excludes the four item-framing bytes.
`kind` must be an assigned input-class message ID and must not be
`INPUT_BATCH`; nested payload decoding/application is intentionally outside
this framing codec.

## 19. Diagnostic messages

### 19.0 Bounded diagnostics v1

All integers are little-endian.  Every diagnostic payload starts with
`u16 schema=1` at offset 0.  Reserved bytes are zero on transmit and decode.
Diagnostic messages may originate on either side except `FRAME_TIME` and
`INPUT_LATENCY`, which are frontend reports.  They are telemetry only:
receiving a diagnostic codec must not mutate Emacs or frontend scene state.

Fixed payload layouts:

| ID | Exact layout |
|---|---|
| `0x0a00 PERF_STATS` | `u16 schema`, `u16 reserved=0` at 2; `u64 frame_count @4`, `update_count @12`, `presented_count @20`, `dropped_count @28`, `input_count @36`, `resync_count @44`, `error_count @52`; total 60 |
| `0x0a01 FRAME_TIME` | `u16 schema`, `u16 reserved=0` at 2, `u32 nonzero frame_id @4`, `u64 nonzero present_sequence @8`, `u64 scheduled_ns @16`, `submit_ns @24`, `present_ns @32`, `u8 dropped` (`0`/`1`) at 40, 3 reserved at 41; total 44. Timestamps allow zero but must satisfy scheduled <= submit <= present |
| `0x0a02 BANDWIDTH_STATS` | `u16 schema`, `u16 reserved=0` at 2; `u64 bytes_sent @4`, `bytes_received @12`, `messages_sent @20`, `messages_received @28`; total 36 |
| `0x0a03 RESOURCE_STATS` | `u16 schema`, `u16 reserved=0` at 2; `u64 live_resources @4`, `cached_bytes @12`, `evictions @20`, `requests @28`; total 36 |
| `0x0a04 DAMAGE_STATS` | `u16 schema`, `u16 reserved=0` at 2; `u64 emitted_rects @4`, `merged_rects @12`, `affected_pixels @20`, `coalesced_updates @28`; total 36 |
| `0x0a05 INPUT_LATENCY` | `u16 schema`, `u16 reserved=0` at 2, `u64 nonzero input_sequence @4`, `u64 capture_ns @12`, `deliver_ns @20`, `apply_ns @28`, `u32 queue_depth @36`; total 40 with no trailing reserved bytes. Timestamps may be zero but must satisfy capture <= deliver <= apply |

Variable payloads have a fixed header followed by a `u16 byte_length` and exact
UTF-8 bytes.  The maximum byte length is 120.

| ID | Exact layout |
|---|---|
| `0x0a06 DESYNC_REPORT` | `u16 schema`, `u16 reserved=0` at 2, `u8 reason @4` (`1` sequence gap, `2` stale generation, `3` resource mismatch, `4` state digest mismatch), 3 reserved at 5, `u64 expected_sequence @8`, `u64 actual_sequence @16`, `u16 detail_length @24`, detail at 26 |
| `0x0a07 TRACE_BEGIN` / `0x0a08 TRACE_END` | Shared layout: `u16 schema`, `u16 reserved=0` at 2, `u64 nonzero trace_id @4`, `u64 timestamp_ns @12`, `u16 name_length @20` (`1..120`), name at 22 |
| `0x0a09 REPLAY_MARKER` | `u16 schema`, `u16 reserved=0` at 2, `u64 nonzero checkpoint_id @4`, `u64 nonzero sequence @12`, `u16 label_length @20` (`0..120`), label at 22 |

Diagnostic detail, trace names, and replay labels are bounded UTF-8 metadata.
They do not alter sequencing, request recovery by themselves, replace the
deterministic recovery differential, or imply a complete telemetry backend.

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
| `implemented_codec` | 108 | Concrete encode/decode plus Scene, bridge, transport, or smoke evidence |
| `partial` | 3 | Concrete local path exists; full payload/recovery semantics remain pending |
| `planned` | 53 | Assigned for the target protocol but not implemented |
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
3. `CURSORS` (kind 5), when cursors were captured.
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
index.  The cursor section is optional and contains one record per observed
window cursor, capped at 16 for the facts profile.  Window IDs must be unique;
each cursor must fit its live owner, and a nonempty section has exactly one
active cursor (the selected window).  Legacy publishers may emit one; non-GUI
proto paths may emit none.  The rejected W4c-b1-a real-row fixture used deterministic
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
without C0/C1 controls and DEL; the current producer limits lines to 32 and columns to 120
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

#### Frame title state

`FRAME_TITLE` (`0x0209`) is a core-to-frontend title reference, not an inline
string payload. The frontend resolves the exact string resource before applying
it.

```text
schema               u16 = 1
flags                u8  = 0
reserved             u8  = 0
string_resource_id   u32 (nonzero)
string_generation    u32 (nonzero)
frame_generation     u32 (nonzero)
```

The payload is exactly 16 bytes. The envelope frame ID, active frame identity,
and `frame_generation` must agree. The referenced string must be live with the
exact generation. Scene owns a zero-terminated copy of the resolved title and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge applies this Scene-owned title to the SDL window.  A
publisher snapshot that omits the optional title suppresses title transport and
leaves the prior diagnostic title unchanged.  This is bounded public-title
observation, not Emacs runtime title ownership, complete frame-parameter
parity, or `output_proto` registration.

#### Frame alpha state

`FRAME_ALPHA` (`0x020d`) carries Emacs-compatible opacity authority in fixed
point. Values are hundredths of a percent from `0` (fully transparent) through
`10000` (fully opaque):

```text
schema               u16 = 1
flags                u8  = 0
reserved             u8  = 0
active_opacity       u16 (0..10000)
inactive_opacity     u16 (0..10000)
background_opacity   u16 (0..10000)
reserved             u16 = 0
frame_generation     u32 (nonzero)
reserved             u32 = 0
```

The payload is exactly 20 bytes. The envelope frame ID, active frame identity,
and `frame_generation` must agree. `active_opacity` and `inactive_opacity`
model the two sides of Emacs frame focus opacity; `background_opacity` models
`alpha-background`. Scene replaces the complete triple only after validation.
The diagnostic SDL bridge probes active-window opacity and falls back to an
opaque window when the platform or compositor does not support it. This is not
redisplay blending policy, focus-runtime integration, or complete PGTK alpha
parity.

#### Frame decoration state

`FRAME_DECORATIONS` (`0x0214`) carries the Emacs `undecorated` frame-policy
inverse: `decorated=1` means normal window-manager decorations and
`decorated=0` means undecorated.

```text
schema                    u16 = 1
flags                     u8  = 0
reserved                  u8  = 0
decorated                 u8  (boolean)
reserved                  u24 = 0
frame_generation          u32 (nonzero)
```

The payload is exactly 12 bytes. The envelope frame ID, active frame identity,
and `frame_generation` must agree. Scene stores the authoritative policy and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge maps this state to `SDL_SetWindowBordered`, verifies the
platform borderless flag, then restores its normal smoke window. This does not
imply parent-frame, tooltip-frame, override-redirect, size-hint, or full WM
policy parity.

#### Frame scale state

`FRAME_SCALE` (`0x020f`) carries one frame's authoritative UI scale and DPI in
a fixed 24-byte payload:

```text
schema               u16 = 1
flags                u8  = 0
reserved             u8  = 0
scale                f32 (finite, > 0, <= 64)
dpi_x                f32 (finite, > 0, <= 4096)
dpi_y                f32 (finite, > 0, <= 4096)
frame_generation     u32 (nonzero)
reserved             u32 = 0
```

The envelope frame ID, active frame identity, and `frame_generation` must
agree. Scene replaces the complete scale/DPI triple only after validation and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge reads SDL's per-window display scale for comparison.
Production redisplay still receives scale and DPI through the `FRAME_UPDATE`
header; this message does not yet implement monitor migration, live scale
events, or core-driven resize/layout.

#### Frame fullscreen state

`FRAME_FULLSCREEN` (`0x020b`) carries Emacs's `fullscreen` frame parameter in
a fixed 12-byte payload:

```text
schema               u16 = 1
flags                u8  = 0
reserved             u8  = 0
mode                 u8
reserved             u24 = 0
frame_generation     u32 (nonzero)
```

Mode is `0=none`, `1=fullboth` (both width and height), `2=fullwidth`,
`3=fullheight`, or `4=maximized`. The envelope frame ID, active frame identity,
and `frame_generation` must agree. Scene stores the authoritative mode and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge maps `fullboth` to SDL's desktop-fullscreen request,
verifies the platform flag, and immediately restores windowed mode. SDL
mapping for width-only, height-only, and maximized modes remains pending;
these are state codec support only, not redisplay resize/layout parity.

#### Frame monitor state

`FRAME_MONITOR` (`0x020e`) identifies the monitor that owns a frame and its
authoritative logical bounds in a fixed 32-byte payload:

```text
schema               u16 = 1
flags                u8  (bit 0=primary; bits 1-7 reserved)
reserved             u8  = 0
monitor_id           u32 (nonzero)
x                    i32
y                    i32
width                i32 (> 0)
height               i32 (> 0)
frame_generation     u32 (nonzero)
reserved             u32 = 0
```

`x + width` and `y + height` must remain representable in `i32`. Flags outside
`primary` are invalid. The envelope frame ID, active frame identity, and
`frame_generation` must agree. Scene stores the complete monitor descriptor and
clears it on frame destruction, authenticated resync, or scene teardown. The
diagnostic SDL bridge queries the real SDL display ID and bounds. This does not
yet implement monitor-change events, frontend-to-core monitor events, display
hotplug recovery, or redisplay-driven frame migration.

#### Frame maximize state

`FRAME_MAXIMIZE` (`0x020c`) carries explicit horizontal and vertical maximize
policy in a fixed 12-byte payload:

```text
schema                 u16 = 1
flags                  u8  (bit 0=horizontal, bit 1=vertical)
reserved               u8  = 0
reserved               u32 = 0
frame_generation       u32 (nonzero)
```

At least one axis must be requested, and all other flags are invalid. The
envelope frame ID, active frame identity, and `frame_generation` must agree.
Scene stores the complete axis set and clears it on frame destruction,
authenticated resync, or scene teardown. The diagnostic SDL bridge applies and
restores the both-axis case through SDL's whole-window maximize command; SDL
cannot generally express independent horizontal/vertical maximization, so
single-axis mapping and redisplay geometry adaptation remain pending.

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
validated and committed atomically with the update.

Facts text uses extension section `0x8002` (`TEXT_LINE_V2`). Each record is
`u64 window_id`, `u32 row_index`, `u32 UTF-8 length`, and UTF-8 bytes. IDs must
match a live window in the same update and row indexes must match a live row
owned by that window. Duplicate `(window_id,row_index)` pairs, invalid UTF-8,
zero IDs, and reserved trailing bytes are invalid. `0x8000` remains a
single-window legacy migration section: it is accepted only when the update has
exactly one window and its records are assigned to that window. A
`FRAME_UPDATE` may contain at most one text section (`0x8000` or `0x8002`), not
both. The facts publisher emits `0x8002`; for each live window it carries up to
eight visible rows bounded to 120 UTF-8 bytes per line. A missing or empty
state list is a legacy fallback and projects text only on the selected window.
A state may carry a public point-derived cursor (`line`, `column`) and
`cursor_active`; at most one state may be active and only the selected window
may publish an active cursor. The facts profile projects at most one cursor per
live window, bounded to the window's projected rows and columns. Scene text is
bounded UTF-8, while the SDL debug renderer draws only its ASCII subset.

Facts mode lines use extension section `0x8003` (`WINDOW_MODE_LINE_V1`).  Each
record is a 30-byte header—`u64 window_id`, four window-relative `i32` values
`x/y/width/height`, `u16 flags`, and `u32 UTF-8 length`—followed by the UTF-8
payload.  A record is in bounds only when `x/y` are nonnegative, `width/height` are
positive, `x+width` fits its owner, and `y+height` fits its owner.  A payload
is 1..120 valid UTF-8 bytes and excludes C0/C1 controls and DEL. Window IDs are unique, at most 16 records are
accepted in the facts profile, exactly one record must set flag bit zero to
designate the selected/active mode line, and all other flags are invalid.  The
Mode-line publication is all-or-nothing: when the selected window's mode line is
unavailable, empty, oversized, or otherwise rejected, the publisher emits no
mode-line section records rather than publishing inactive observations alone.
The
batch public-fact publishers omit this field when the public mode-line format is
unavailable or empty rather than synthesizing placeholder text.  The diagnostic renderer draws the bar
and its ASCII subset; this public observation is not redisplay-owned mode-line
semantics, full item/face interaction, or complete mode-line parity.

Header and tab lines use extension section `0x8004` (`WINDOW_AUX_LINE_V1`).  It
reuses the same 30-byte header and bounded payload form as mode lines, but
`flags` bit 1 selects a header line and bit 2 selects a tab line; both kind bits
or any other flag bit is invalid.  A window may carry at most one header and one
tab line, while the facts profile accepts at most 32 records per update.  When both lines are present,
their heights must together fit the owner. Each record must fit its owner and
carry 1..120 valid UTF-8 bytes excluding C0/C1 controls and DEL.  These are public
text/height observations rendered as diagnostic bars; they are not mode/header/
tab item models, face-accurate lines, mouse targets, redisplay-owned capture, or
PGTK parity.

Bounded IME context lifecycle and policy are implemented for `IME_ATTACH`,
`DETACH`, `FOCUS`, `CURSOR_RECT`, `ALLOWED_INPUT`, `SURROUNDING_TEXT`, and
`RESET`.  Every payload starts at offset 0 with
nonzero `u64 context_id` then nonzero `u64 window_id`.  Exact forms are:

* `ATTACH` (20 bytes): `u32 flags = 0` at offset 16.
* `DETACH` (16 bytes): identity only.
* `FOCUS` (20 bytes): `u8 focused = 0|1` at offset 16 and three zero bytes.
* `CURSOR_RECT` (32 bytes): four window-relative `i32` values at offsets 16,
  20, 24, and 28; cursor width and height must be positive.
* `ALLOWED_INPUT` (20 bytes): `u32 flags` at offset 16.  Bits are text (0),
  multiline (1), surrounding text (2), and delete surrounding (3); unknown bits
  are invalid.
* `SURROUNDING_TEXT` (variable): `u32 cursor_offset`, `u32 selected_length`,
  `u32 byte_length` at offsets 16, 20, and 24, followed by UTF-8 bytes.  The
  cursor is the end of the selected range, so `selected_length <= cursor_offset
  <= byte_length`; `byte_length` is bounded to 0..120 and rejects C0/C1 controls and DEL.
* `RESET` (20 bytes): `u8 reason = 0` at offset 16 and three zero bytes.
* `IME_PREEDIT_START` / `IME_PREEDIT_END` (`0x0712` / `0x0714`, 8 bytes):
  identity is only nonzero `u64 context_id`; these messages do not carry a
  window ID because the live context owns it.
* `IME_PREEDIT_UPDATE` (`0x0713`, variable): `u32 cursor_offset`,
  `u32 selected_length`, and `u32 byte_length` at offsets 8, 12, and 16,
  followed by UTF-8 bytes.  `selected_length <= cursor_offset <= byte_length`
  and `byte_length` is bounded to 0..120; C0/C1 controls and DEL are invalid.
* `IME_COMMIT` (`0x0715`, variable): nonzero `u64 context_id`, `u32
  byte_length` at offset 8, then bounded UTF-8 text.  Length is 1..120; C0/C1
  controls and DEL are invalid.
* `IME_CANDIDATE_UPDATE` (`0x0718`, variable): nonzero context ID, four `u32`
  metadata fields at offsets 8/12/16/20 (selected index, candidate count, page
  index, page count), four window-relative `i32` placement fields at offsets
  24/28/32/36 (x, y, width, height), a `u32 selected-label byte length` at
  offset 40, then bounded UTF-8 label bytes.  Counts/pages and the selected
  index must agree; zero candidates require zero selection and no label, while
  placement width/height must be positive.  At most 64 candidates and 16 pages
  are accepted.
* `IME_CANCEL` (`0x0719`, 8 bytes): nonzero context ID only.

Scene accepts a context only for a live window in the active frame, rejects
duplicate contexts or a second context on a window, keeps at most four
contexts, validates cursor containment, and requires all later operations to
name the same window.  An authoritative `FRAME_UPDATE` reconciles contexts
against its replacement window set: contexts without live owners are removed,
and retained cursors that no longer fit are cleared.  `ALLOWED_INPUT` replaces the bounded policy mask; clearing surrounding-text
support also clears retained surrounding state.  `SURROUNDING_TEXT` requires
that policy bit and atomically replaces retained text, cursor, and selection.
`RESET` clears policy, surrounding state, focus, and cursor geometry while
retaining the attachment.  Deleting the owner removes its
context.  This is control-plane
preparation.  In addition, bounded `Scene` state is implemented for
`IME_PREEDIT_START`, `IME_PREEDIT_UPDATE`, and `IME_PREEDIT_END`: start creates
an empty composition, update atomically replaces at most 120 UTF-8 bytes plus
its cursor/selection offsets, and end/reset/detach clear it.  The SDL
diagnostic bridge has a bounded ASCII overlay only; this is not protocol-owned
or production preedit rendering.  Unicode preedit remains retained state.
There is no platform IME backend, commit application,
surrounding-text query, or full multibyte-input claim.
Every preedit message must use the active frame and the context's creating
frame; update also requires an active composition.  All integer fields are
little-endian.

`IME_CANDIDATE_UPDATE` also uses the active and creating frame, requires a
focused context, validates the placement against its live owner, and atomically
stores selected index/count/page metadata plus at most 120 UTF-8 label bytes.
A zero-count update clears candidates.  The SDL diagnostic bridge can draw one
bounded ASCII selected-label metadata overlay; Unicode labels remain retained
state.  `IME_CANCEL` clears candidates and preedit.  `IME_COMMIT` requires a focused
live context, records at most 120 UTF-8 committed bytes for diagnostics, and
clears preedit/candidates; it does not mutate Emacs buffer text.  There is no
platform IME backend, core commit application, full candidate-list UI, or
complete multibyte-input claim.

#### Standalone icon resource v1

`ICON_DEFINE` is a variable payload with a 32-byte little-endian header:
`u16 schema=1`, `u16 flags=1 (present)`, `u32 icon_id` (nonzero), `u32
generation` (nonzero), `u32 width` and `u32 height` (1..256), `u32 hotspot_x`
and `u32 hotspot_y` (inside the icon), and `u32 byte_length`.  The remaining
bytes are complete premultiplied RGBA8 pixels; `byte_length` must equal
`width * height * 4` and is at most 256 KiB.  `ICON_DELETE` is `u32 icon_id`
and `u32 generation`.  Scene stores standalone icons in its image-resource
namespace, so generation-aware `FRAME_ICON` references and resource deletion
behave consistently.  Multi-resolution bundles, animations, masks, and OS
taskbar guarantees remain pending.

The facts profile defines a deliberately bounded `WHEEL_EVENT` subset for
`0x0603`: `u8 unit` (`1=line`), `u8 source` (`1=wheel`), `u8 modifiers`
(`0=none`), `i8 x` and `i8 y`, and nine reserved zero bytes. Exactly one axis
is nonzero; its whole-line value is `-8..8`. The current diagnostic publisher
maps vertical ticks to public `scroll-up`/`scroll-down` and horizontal ticks to
public `scroll-right`/`scroll-left`. Diagonal, zero, pixel/page units,
touchpad/gesture sources, smooth deltas, and modifiers remain outside the
bounded profile. Wheel intents use the same frontend-to-core sequence and EPXL
`ACK` rules as other reverse input.

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
