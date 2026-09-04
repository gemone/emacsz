# Proto-UI Performance Baseline

Status: normative performance design
Protocol: EUP v1

## 1. Goals

The performance goal is real interactive responsiveness, not only a synthetic score.

Primary goals:

1. Low visible typing and scrolling latency.
2. Stable frame pacing.
3. Minimal hot-path allocation.
4. Partial damage for common edits.
5. Predictable behavior when the frontend is slow.
6. Measurable GPU acceleration without making GPU mandatory.

## 2. Reference environments

### 2.1 Baseline host

```text
Linux x86_64
ReleaseFast Zig build
1920x1080 display
60 Hz
scale = 1.0
local shared memory or Unix socket
default monospace font
single active frame
100 columns x 40 lines
14 px default font
no image-heavy workload
```

### 2.2 High-density host

```text
3840x2160 display
60 Hz minimum
scale = 2.0
four visible windows
font-lock enabled
mixed ASCII, CJK, and BiDi content
reasonable icon/image workload
```

### 2.3 High-refresh host

```text
1080p or 1440p
120 Hz or 144 Hz
GPU_BASIC or GPU_ADVANCED frontend
typing and smooth scroll workloads
```

## 3. Renderer tiers

| Tier | Purpose | Minimum expectation |
|---|---|---|
| Software | Correctness and fallback | Usable editing; no GPU requirement |
| GPU Basic | Production minimum | 1080p60 normal editing |
| GPU Advanced | Performance target | Damage present, atlas reuse, 1440p60/4K60 on capable hardware |
| Low latency | Optional | VRR, mailbox present, 120Hz+ scheduling |

GPU absence must never prevent correctness.

## 4. Latency budgets

Numbers are targets on the baseline host unless stated otherwise.

### 4.1 Backend encode

| Workload | P50 | P95 | P99 |
|---|---:|---:|---:|
| Typical typing/cursor update | <= 0.5 ms | <= 1.0 ms | <= 2.0 ms |
| Partial mode-line/face update | <= 0.5 ms | <= 1.0 ms | <= 2.0 ms |
| Full 1080p text redraw | <= 1.0 ms | <= 2.0 ms | <= 4.0 ms |
| Full 4K text redraw | <= 3.0 ms | <= 6.0 ms | <= 10.0 ms |

### 4.2 Frontend apply

| Workload | P50 | P95 | P99 |
|---|---:|---:|---:|
| Partial decode + scene apply | <= 0.5 ms | <= 1.0 ms | <= 2.0 ms |
| Full 1080p text update | <= 1.0 ms | <= 2.5 ms | <= 5.0 ms |
| Full 4K text update | <= 4.0 ms | <= 8.0 ms | <= 12.0 ms |

### 4.3 Transport

| Path | Target |
|---|---|
| Shared-memory enqueue/dequeue | <= 0.1 ms P95 |
| Local Unix socket | <= 0.5 ms P95 |
| Local pipe | <= 1.0 ms P95 |

### 4.4 Input

| Stage | Target |
|---|---|
| SDL event captured to EUP input queued | <= 0.5 ms P95 |
| EUP input delivered to backend queue | <= 1.0 ms P95 shared memory; <= 3.0 ms socket |
| Backend translation to Emacs input entry | <= 1.0 ms P95 |

### 4.5 Visible end-to-end latency

| Scenario | Target |
|---|---|
| Key-to-present at 60 Hz | P50 <= 16 ms; P95 <= 33 ms |
| Key-to-present at 120 Hz capable | P95 <= 25 ms |
| Cursor blink | No visible stall |
| Single-window scroll | Typical one-frame increment; P95 <= 33 ms |
| Window resize first response | <= 2 refresh intervals |
| Menu open | P95 <= 50 ms |

Latency is measured from platform event timestamp to compositor/present timestamp where available, not merely internal render submit.

## 5. Frame-rate targets

| Scenario | Software | GPU Basic | GPU Advanced |
|---|---:|---:|---:|
| 1080p typing | usable | 60 FPS | 60+ FPS |
| 1080p cursor blink | 60 FPS target | 60 FPS | 120 FPS capable |
| 1080p normal scroll | usable | 60 FPS | 60/120 FPS capable |
| 1440p normal scroll | degraded | 60 FPS | 60 FPS |
| 4K text scroll | degraded | >= 30 FPS | >= 60 FPS capable |
| Image-heavy workload | workload-dependent | negotiated | negotiated |

Drops are acceptable only under overload and must be reported. Sustained protocol-induced stalls are failures.

## 6. Bandwidth budgets

Baseline is uncompressed EUP unless compression is separately measured.

| Workload | Target |
|---|---|
| Typing in 80x24 to 100x40 single window | P95 <= 64 KiB/frame |
| Scroll with scroll optimization | P95 <= 128 KiB/frame |
| Full 1080p text-only redraw | P95 <= 1 MiB/frame |
| Full 4K text-only redraw | P95 <= 4 MiB/frame |
| Sustained 1080p60 text-only | <= 32 MiB/s |
| Burst | <= 128 MiB/s |

Image-heavy workloads are excluded from text-only budgets but remain bounded by negotiated resource limits.

## 7. Memory budgets

| Component | Baseline |
|---|---|
| Backend session state | <= 8 MiB typical |
| Default frame ring | 8 MiB |
| Default resource arena | 32 MiB |
| Backend ceiling | Configured, never unbounded |
| Frontend normal text cache | <= 128 MiB |
| Frontend image-heavy cache | Configured and reported |
| Glyph atlas | Configurable and bounded |

Cache exhaustion triggers eviction or quality fallback, not failure.

## 8. Hot-path requirements

### 8.1 Backend

1. One encode pass per emitted frame.
2. No per-glyph heap allocation.
3. No per-row heap allocation in steady state.
4. Reuse output slabs and damage arrays.
5. Avoid full snapshot during typing.
6. Merge overlapping damage.
7. Encode only changed rows when safe.

### 8.2 Transport

1. Frame updates are coalescable.
2. Resources and input are never dropped.
3. Shared-memory mode targets zero extra copy after encode.
4. Socket mode allows at most one transport copy.
5. Backpressure uses latest coherent frame semantics.

### 8.3 Frontend

1. Decode and scene apply are in-place where possible.
2. Do not rebuild unchanged glyph atlas entries.
3. Do not reupload unchanged images.
4. Use scissor/damage to avoid drawing unchanged regions.
5. Do not create renderer objects per frame.
6. Batch draw items by texture and state where possible.

## 9. Instrumentation

### 9.1 Backend counters

```text
redisplay_finish_to_encode_start_ns
encode_duration_ns
encoded_bytes
frame_update_count
coalesced_frame_count
damage_rect_count
damage_pixel_area
resource_publish_count
resource_evict_count
transport_queue_depth
dropped_diagnostic_count
input_translation_ns
```

### 9.2 Frontend counters

```text
receive_to_apply_start_ns
apply_duration_ns
render_cpu_ns
gpu_submit_ns
present_timestamp_ns
present_mode
frame_dropped_count
frame_late_count
texture_upload_bytes
texture_upload_ns
atlas_hit_count
atlas_miss_count
evicted_resource_count
scene_object_count
memory_usage
```

### 9.3 End-to-end timestamps

Benchmarks must correlate:

```text
platform input timestamp
Emacs command completion
redisplay finish
encode finish
transport send
frontend receive
scene apply finish
GPU submit
present timestamp
```

## 10. Required benchmark scenarios

### 10.1 Frame creation

Measure protocol negotiation, initial resource publication, snapshot size, and first visible present.

Target: first present after `SESSION_READY` <= 100 ms on baseline host.

### 10.2 Typing

Run ASCII insertion, IME CJK insertion, backward/forward delete, undo/redo, self-insert in fundamental mode, and self-insert with font-lock.

Measure latency, bandwidth, damage, and atlas hit rate.

### 10.3 Cursor movement

Run line/column jumps, beginning/end of buffer, word/paragraph movement, and scroll around point.

Measure cursor latency and partial damage.

### 10.4 Scrolling

Run line scroll, screen scroll, smooth touchpad scroll, scroll-other-window, very long lines, and CJK/BiDi buffers.

Measure pacing, drops, bandwidth, and damage correctness.

### 10.5 Window operations

Run split, delete, resize, balance, switch, and scroll-other-window.

Measure geometry latency and redraw frequency.

### 10.6 Faces and fonts

Run font-lock activation, face changes, variable pitch, CJK fallback, bold/italic, and frame font resize.

Measure resource churn and full-redraw frequency.

### 10.7 Images

Run repeated icons, large images, animation, and image scrolling.

Measure uploads, cache hit rate, and frame pacing.

### 10.8 Widgets

Run menu open/select/cancel, dialog open/result, tooltip show/hide, and scrollbar drag.

Measure interaction latency and semantic correctness.

### 10.9 Multi-frame

Run frame creation, focus switching, monitor movement, DPI change, and many-frame stress.

Measure isolation and update fan-out.

### 10.10 Backpressure

Produce updates faster than presentation.

Verify:

1. Emacs is not blocked.
2. Frame updates coalesce.
3. Latest coherent frame becomes visible.
4. Input is not dropped.
5. Resources are not dropped.

## 11. Regression gates

Tests must fail if any of these regress beyond tolerance:

```text
P95 encode latency
P95 frontend apply latency
P95 key-to-present latency
bytes/frame for standard workloads
steady-state allocations/frame
dropped-frame ratio
atlas hit rate
resource misses
memory ceiling
```

Each gate must emit machine-readable results, not only prose.

## 12. Report format

Every performance run records:

```text
protocol version
renderer tier
transport type
host profile
frame size
scale
workload name
iteration count
latency percentiles
bandwidth percentiles
frame drop ratio
allocation count
memory peak
atlas hit rate
damage coverage
```

Machine-readable output is required.

## 13. Correctness precedence

Optimization must never:

1. Drop required resources.
2. Drop input events.
3. Present a partially decoded update.
4. Reorder glyphs.
5. Let frontend metrics override Emacs layout.
6. Block Emacs redisplay on frontend work.
7. Leave stale pixels inside declared damage.

An optimization that cannot preserve these invariants is rejected.

## 14. Initial acceptance targets

The first real SDL3-backed frame is performance-successful when, on the baseline host:

1. Protocol negotiation completes in <= 100 ms after backend readiness.
2. First visible frame appears in <= 100 ms after `SESSION_READY`.
3. Visible typing latency P95 <= 33 ms.
4. Normal scrolling remains usable at 60 Hz.
5. Typical typing update stays below 64 KiB.
6. Typical typing update does not require full-frame redraw.
7. Frontend slowdown does not block Emacs batch evaluation.
8. Measured counters prove all of the above.

Complete production acceptance requires all tier-specific budgets in this document to pass with machine-readable evidence.
