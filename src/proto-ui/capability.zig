//! Adapter-owned capability negotiation policy and implementation manifest.
//!
//! EUP defines arbitrary name/value capabilities.  This module binds the local
//! EPXL profile to a small, versioned subset, intersects the backend/frontend
//! sets, and records implementation status for generated tooling.  Unknown
//! optional names are ignored, as required by EUP; known names with malformed
//! values fail the session deterministically.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const manifest_version: u32 = 1;
pub const session_id: u64 = 0x1001;
pub const hash_len: usize = 32;

pub const Error = protocol.Error || error{
    MissingRequiredCapability,
    InvalidCapabilityValue,
    InvalidNegotiationMessage,
    CapabilityHashMismatch,
};

pub const Status = enum {
    implemented,
    degraded,
    pending,

    pub fn name(self: Status) []const u8 {
        return switch (self) {
            .implemented => "implemented",
            .degraded => "degraded",
            .pending => "pending",
        };
    }
};

pub const Feature = enum {
    protocol_v1,
    capability_negotiation,
    session_control_v1,
    transport_epxl_local,
    session_resync,
    frame_facts_profile,
    text_ascii_bounded,
    input_text_ascii,
    input_text_unicode,
    input_key_bounded,
    input_key_full_v2,
    input_pointer_bounded,
    input_pointer_v2,
    input_pointer_selection_left,
    input_pointer_middle_paste,
    input_wheel_line,
    platform_focus_window_events,
    clipboard_ascii_bounded,
    clipboard_text_unicode,
    damage_retained_clip,
    scroll_copy_policy,
    renderer_sdl3,
    window_tree_snapshot_v1,
    window_lifecycle_v1,
    window_patch_v1,
    window_geometry_v1,
    window_zones_v1,
    window_position_v1,
    window_face_state_v1,
    cursor_update_v1,
    render_glyph_face_debug_v2,
    render_image_debug_v1,
    render_glyph_run_debug_v1,
    render_flush_v1,
    render_hint_v1,
    render_update_boundary_v1,
    frame_border_style_v1,
    window_fringe_style_v1,
    window_divider_style_v1,
    window_scrollbar_state_v1,
    window_scroll_request_v1,
    frame_output_proto,
    frame_lifecycle,
    frame_visibility_focus_contract,
    frame_title_v1,
    frame_alpha_v1,
    frame_decorations_v1,
    frame_scale_v1,
    frame_fullscreen_v1,
    frame_monitor_v1,
    frame_maximize_v1,
    frame_present_feedback_v1,
    frame_geometry_v1,
    frame_icon_v1,
    frame_size_hints_v1,
    frame_z_order_v1,
    frame_parent_v1,
    resource_generation_contract,
    resource_payload_eviction_contract,
    resource_string_v1,
    resource_face_v1,
    resource_face_patch_v1,
    face_decoration_bars_v1,
    resource_font_v1,
    resource_font_metrics_v1,
    resource_image_v1,
    resource_snapshot_v1,
    host_frame_state_seam,
    redisplay_glyph_rows,
    resource_v1,
    runtime_host_registration_contract,
    runtime_frame_service_mapping,
    runtime_terminal_service_v1,
    runtime_host_adapter_selection,
    runtime_activation_contract,
    runtime_fail_closed_manifest,
    adapter_generated_c_shim,
    adapter_host_shim_library,
    capture_atomic_batches,
    policy_host_registration_contract,
    protocol_fuzz_hardening,
    protocol_frontend_crash_isolation,
    recovery_differential_gate,
    recovery_resource_snapshot_gate,
    performance_adapter_hotpath_benchmark,
    compatibility_pgtk_base_gate,
    compatibility_backend_semantic_matrix,
    isolation_disabled_default_gate,

    pub fn name(self: Feature) []const u8 {
        return switch (self) {
            .protocol_v1 => "protocol.v1",
            .capability_negotiation => "capability.negotiation",
            .session_control_v1 => "session.control_v1",
            .transport_epxl_local => "transport.epxl_local",
            .session_resync => "session.resync",
            .frame_facts_profile => "frame.facts_profile",
            .text_ascii_bounded => "text.ascii_bounded",
            .input_text_ascii => "input.text_ascii",
            .input_text_unicode => "input.text_unicode",
            .input_key_bounded => "input.key_bounded",
            .input_key_full_v2 => "input.key_full_v2",
            .input_pointer_bounded => "input.pointer_bounded",
            .input_pointer_v2 => "input.pointer_v2",
            .input_pointer_selection_left => "input.pointer_selection_left",
            .input_pointer_middle_paste => "input.pointer_middle_paste",
            .input_wheel_line => "input.wheel_line",
            .platform_focus_window_events => "platform.focus_window_events",
            .clipboard_ascii_bounded => "clipboard.ascii_bounded",
            .clipboard_text_unicode => "clipboard.text_unicode",
            .damage_retained_clip => "damage.retained_clip",
            .scroll_copy_policy => "render.scroll_copy_policy",
            .renderer_sdl3 => "renderer.sdl3",
            .window_tree_snapshot_v1 => "window.tree_snapshot_v1",
            .window_lifecycle_v1 => "window.lifecycle_v1",
            .window_patch_v1 => "window.patch_v1",
            .window_geometry_v1 => "window.geometry_v1",
            .window_zones_v1 => "window.zones_v1",
            .window_position_v1 => "window.position_v1",
            .window_face_state_v1 => "window.face_state_v1",
            .cursor_update_v1 => "cursor.update_v1",
            .render_glyph_face_debug_v2 => "render.glyph_face_debug_v2",
            .render_image_debug_v1 => "render.image_debug_v1",
            .render_glyph_run_debug_v1 => "render.glyph_run_debug_v1",
            .render_flush_v1 => "render.flush_v1",
            .render_hint_v1 => "render.hint_v1",
            .render_update_boundary_v1 => "render.update_boundary_v1",
            .frame_border_style_v1 => "frame.border_style_v1",
            .window_fringe_style_v1 => "window.fringe_style_v1",
            .window_divider_style_v1 => "window.divider_style_v1",
            .window_scrollbar_state_v1 => "window.scrollbar_state_v1",
            .window_scroll_request_v1 => "window.scroll_request_v1",
            .frame_output_proto => "frame.output_proto",
            .frame_lifecycle => "frame.lifecycle",
            .frame_visibility_focus_contract => "frame.visibility_focus_contract",
            .frame_title_v1 => "frame.title_v1",
            .frame_alpha_v1 => "frame.alpha_v1",
            .frame_decorations_v1 => "frame.decorations_v1",
            .frame_scale_v1 => "frame.scale_v1",
            .frame_fullscreen_v1 => "frame.fullscreen_v1",
            .frame_monitor_v1 => "frame.monitor_v1",
            .frame_maximize_v1 => "frame.maximize_v1",
            .frame_present_feedback_v1 => "frame.present_feedback_v1",
            .frame_geometry_v1 => "frame.geometry_v1",
            .frame_icon_v1 => "frame.icon_v1",
            .frame_size_hints_v1 => "frame.size_hints_v1",
            .frame_z_order_v1 => "frame.z_order_v1",
            .frame_parent_v1 => "frame.parent_v1",
            .resource_generation_contract => "resource.generation_contract",
            .resource_payload_eviction_contract => "resource.payload_eviction_contract",
            .resource_string_v1 => "resource.string_v1",
            .resource_face_v1 => "resource.face_v1",
            .resource_face_patch_v1 => "resource.face_patch_v1",
            .face_decoration_bars_v1 => "face.decoration_bars_v1",
            .resource_font_v1 => "resource.font_v1",
            .resource_font_metrics_v1 => "resource.font_metrics_v1",
            .resource_image_v1 => "resource.image_v1",
            .resource_snapshot_v1 => "resource.snapshot_v1",
            .host_frame_state_seam => "adapter.host_frame_state_seam",
            .redisplay_glyph_rows => "redisplay.glyph_rows",
            .resource_v1 => "resource.v1",
            .runtime_host_registration_contract => "runtime.host_registration_contract",
            .runtime_frame_service_mapping => "runtime.frame_service_mapping",
            .runtime_terminal_service_v1 => "runtime.terminal_service_v1",
            .runtime_host_adapter_selection => "runtime.host_adapter_selection",
            .runtime_activation_contract => "runtime.activation_contract",
            .runtime_fail_closed_manifest => "runtime.fail_closed_manifest",
            .adapter_generated_c_shim => "adapter.generated_c_shim",
            .adapter_host_shim_library => "adapter.host_shim_library",
            .capture_atomic_batches => "capture.atomic_batches",
            .policy_host_registration_contract => "policy.host_registration_contract",
            .protocol_fuzz_hardening => "protocol.fuzz_hardening",
            .protocol_frontend_crash_isolation => "protocol.frontend_crash_isolation",
            .recovery_differential_gate => "recovery.differential_gate",
            .recovery_resource_snapshot_gate => "recovery.resource_snapshot_gate",
            .performance_adapter_hotpath_benchmark => "performance.adapter_hotpath_benchmark",
            .compatibility_pgtk_base_gate => "compatibility.pgtk_base_gate",
            .compatibility_backend_semantic_matrix => "compatibility.backend_semantic_matrix",
            .isolation_disabled_default_gate => "isolation.disabled_default_gate",
        };
    }

    pub fn required(self: Feature) bool {
        return switch (self) {
            .protocol_v1, .session_control_v1, .transport_epxl_local, .session_resync, .frame_facts_profile, .text_ascii_bounded, .renderer_sdl3 => true,
            else => false,
        };
    }

    pub fn negotiable(self: Feature) bool {
        return switch (self) {
            .frame_output_proto,
            .frame_lifecycle,
            .frame_visibility_focus_contract,
            .resource_generation_contract,
            .resource_payload_eviction_contract,
            .resource_string_v1,
            .resource_face_v1,
            .resource_font_v1,
            .resource_image_v1,
            .resource_snapshot_v1,
            .redisplay_glyph_rows,
            .resource_v1,
            => false,
            .runtime_host_registration_contract,
            .runtime_frame_service_mapping,
            .runtime_terminal_service_v1,
            .runtime_host_adapter_selection,
            .runtime_activation_contract,
            .runtime_fail_closed_manifest,
            => false,
            .adapter_generated_c_shim => false,
            .adapter_host_shim_library => false,
            .capture_atomic_batches => false,
            .policy_host_registration_contract => false,
            .protocol_fuzz_hardening => false,
            .protocol_frontend_crash_isolation => false,
            .recovery_differential_gate => false,
            .recovery_resource_snapshot_gate => false,
            .performance_adapter_hotpath_benchmark => false,
            .compatibility_pgtk_base_gate => false,
            .compatibility_backend_semantic_matrix => false,
            .isolation_disabled_default_gate => false,
            .host_frame_state_seam => false,
            else => true,
        };
    }
};

pub const FeatureDescriptor = struct {
    feature: Feature,
    status: Status,
    evidence: []const u8,
};

pub const feature_descriptors = [_]FeatureDescriptor{
    .{ .feature = .protocol_v1, .status = .implemented, .evidence = "proto-ui-conformance" },
    .{ .feature = .capability_negotiation, .status = .implemented, .evidence = "proto-ui-unit and sdl3-epxl-facts-smoke" },
    .{ .feature = .session_control_v1, .status = .implemented, .evidence = "proto-ui-unit terminal states and sdl3-live-smoke EPXL transport for all eight controls, including automatic PONG and fatal VERSION_MISMATCH" },
    .{ .feature = .transport_epxl_local, .status = .implemented, .evidence = "sdl3-live-smoke" },
    .{ .feature = .session_resync, .status = .implemented, .evidence = "sdl3-epxl-resync-smoke" },
    .{ .feature = .frame_facts_profile, .status = .degraded, .evidence = "sdl3-epxl-facts-smoke" },
    .{ .feature = .text_ascii_bounded, .status = .degraded, .evidence = "sdl3-epxl-input-smoke" },
    .{ .feature = .input_text_ascii, .status = .degraded, .evidence = "sdl3-epxl-input-smoke" },
    .{ .feature = .input_text_unicode, .status = .degraded, .evidence = "sdl3-epxl-unicode-input-smoke" },
    .{ .feature = .input_key_bounded, .status = .degraded, .evidence = "sdl3-epxl-edit-smoke" },
    .{ .feature = .input_key_full_v2, .status = .degraded, .evidence = "sdl3-epxl-key-v2-smoke" },
    .{ .feature = .input_pointer_bounded, .status = .degraded, .evidence = "sdl3-pointer-smoke" },
    .{ .feature = .input_pointer_v2, .status = .degraded, .evidence = "sdl3-pointer-v2-smoke" },
    .{ .feature = .input_pointer_selection_left, .status = .degraded, .evidence = "sdl3-pointer-selection-smoke" },
    .{ .feature = .input_pointer_middle_paste, .status = .degraded, .evidence = "sdl3-pointer-middle-paste-smoke" },
    .{ .feature = .input_wheel_line, .status = .degraded, .evidence = "sdl3-wheel-smoke" },
    .{ .feature = .platform_focus_window_events, .status = .degraded, .evidence = "sdl3-focus-window-smoke" },
    .{ .feature = .clipboard_ascii_bounded, .status = .degraded, .evidence = "sdl3-clipboard-smoke" },
    .{ .feature = .clipboard_text_unicode, .status = .degraded, .evidence = "sdl3-clipboard-unicode-smoke" },
    .{ .feature = .damage_retained_clip, .status = .degraded, .evidence = "sdl3-pointer-smoke and sdl3-epxl-interactive-smoke" },
    .{ .feature = .scroll_copy_policy, .status = .degraded, .evidence = "proto-ui-unit vertical scroll codec and copy-plan metrics; SDL retained-frame copy pending" },
    .{ .feature = .renderer_sdl3, .status = .degraded, .evidence = "sdl3-renderer-smoke" },
    .{ .feature = .window_tree_snapshot_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .window_lifecycle_v1, .status = .degraded, .evidence = "proto-ui-unit bounded create/delete and dependent-state rejection; patch/zones pending" },
    .{ .feature = .window_patch_v1, .status = .degraded, .evidence = "proto-ui-unit bounded geometry/parent/visibility/face/depth patch; zones/scroll pending" },
    .{ .feature = .window_geometry_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke bounded content/body geometry and body-boundary render; full zone/layout parity pending" },
    .{ .feature = .window_zones_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke bounded disjoint zones and boundary render; redisplay-owned layout and full PGTK parity pending" },
    .{ .feature = .window_position_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke bounded diagnostic buffer/start/point state; buffer text, layout, and full point semantics pending" },
    .{ .feature = .window_face_state_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke bounded default-face state/background render; full core-owned face semantics pending" },
    .{ .feature = .cursor_update_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; cursor style/IME integration pending" },
    .{ .feature = .render_glyph_face_debug_v2, .status = .degraded, .evidence = "sdl3-runtime-bridge-smoke" },
    .{ .feature = .render_image_debug_v1, .status = .degraded, .evidence = "sdl3-runtime-bridge-smoke" },
    .{ .feature = .render_glyph_run_debug_v1, .status = .degraded, .evidence = "sdl3-glyph-run-smoke" },
    .{ .feature = .render_flush_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; redisplay-owned flush emission pending" },
    .{ .feature = .render_hint_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; renderer pacing integration pending" },
    .{ .feature = .render_update_boundary_v1, .status = .degraded, .evidence = "proto-ui-unit strict BEGIN/END nesting, generation, and close validation; redisplay wiring pending" },
    .{ .feature = .frame_border_style_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; window-manager border semantics pending" },
    .{ .feature = .window_fringe_style_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; bitmap glyphs and draggable fringe semantics pending" },
    .{ .feature = .window_divider_style_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; draggable divider semantics pending" },
    .{ .feature = .window_scrollbar_state_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke vertical state/thumb rendering; drag and horizontal scrollbars pending" },
    .{ .feature = .window_scroll_request_v1, .status = .degraded, .evidence = "proto-ui-unit bounded absolute/relative intent codec and queue; EPXL transport pending" },
    .{ .feature = .frame_output_proto, .status = .pending, .evidence = "W12/W16 real proto frame acceptance pending" },
    .{ .feature = .frame_lifecycle, .status = .degraded, .evidence = "proto-ui-unit frame lifecycle contract and sdl3-frame-smoke" },
    .{ .feature = .frame_visibility_focus_contract, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .frame_title_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_alpha_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_decorations_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_scale_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_fullscreen_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_monitor_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_maximize_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke" },
    .{ .feature = .frame_present_feedback_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke codec/counter conformance; core consumer pending" },
    .{ .feature = .frame_geometry_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke; core-owned platform geometry pending" },
    .{ .feature = .frame_icon_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke RGBA icon surface; taskbar/app-icon parity pending" },
    .{ .feature = .frame_size_hints_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke min/max/aspect constraints; size increments pending" },
    .{ .feature = .frame_z_order_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke top/always-on-top probe; relative stacking and bottom mapping pending" },
    .{ .feature = .frame_parent_v1, .status = .degraded, .evidence = "proto-ui-unit and sdl3-runtime-bridge-smoke nullable-parent unparent probe; linked/modal child windows pending" },
    .{ .feature = .resource_generation_contract, .status = .degraded, .evidence = "proto-ui-unit resource generation contract" },
    .{ .feature = .resource_payload_eviction_contract, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .resource_string_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .resource_face_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .resource_face_patch_v1, .status = .degraded, .evidence = "proto-ui-unit bounded color patch and strict generation replacement; full face attributes pending" },
    .{ .feature = .face_decoration_bars_v1, .status = .degraded, .evidence = "proto-ui-unit policy bars and sdl3-runtime-bridge-smoke face background; shaped text/font metrics pending" },
    .{ .feature = .resource_font_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .resource_font_metrics_v1, .status = .degraded, .evidence = "proto-ui-unit bounded metrics patch and strict generation replacement; real font metrics pending" },
    .{ .feature = .resource_image_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .resource_snapshot_v1, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .host_frame_state_seam, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .redisplay_glyph_rows, .status = .pending, .evidence = "W12 redisplay capture pending" },
    .{ .feature = .resource_v1, .status = .pending, .evidence = "W12 resource model pending" },
    .{ .feature = .runtime_host_registration_contract, .status = .pending, .evidence = "runtime manifest reports host_registration_contract_missing" },
    .{ .feature = .runtime_frame_service_mapping, .status = .degraded, .evidence = "proto-ui-unit" },
    .{ .feature = .runtime_terminal_service_v1, .status = .degraded, .evidence = "proto-ui-unit and proto-ui-terminal-service fake-host lifecycle; R7 approval and Emacs terminal registration pending" },
    .{ .feature = .runtime_host_adapter_selection, .status = .pending, .evidence = "proto-ui-host-adapter records the pure-SDL3 candidate unselected until R7 approval" },
    .{ .feature = .runtime_activation_contract, .status = .pending, .evidence = "proto-ui-runtime-activation records an explicit blocked activation/rollback plan until R7 approval" },
    .{ .feature = .runtime_fail_closed_manifest, .status = .degraded, .evidence = "proto-ui-runtime-manifest" },
    .{ .feature = .adapter_generated_c_shim, .status = .degraded, .evidence = "proto-ui-shim-conformance" },
    .{ .feature = .adapter_host_shim_library, .status = .degraded, .evidence = "proto-ui-shim-library-conformance" },
    .{ .feature = .capture_atomic_batches, .status = .degraded, .evidence = "proto-ui-unit continuous capture-generation reset; redisplay capture pending" },
    .{ .feature = .policy_host_registration_contract, .status = .degraded, .evidence = "proto-ui-host-contract" },
    .{ .feature = .protocol_fuzz_hardening, .status = .degraded, .evidence = "proto-ui-fuzz" },
    .{ .feature = .protocol_frontend_crash_isolation, .status = .degraded, .evidence = "proto-ui-crash-isolation" },
    .{ .feature = .recovery_differential_gate, .status = .degraded, .evidence = "proto-ui-recovery-diff" },
    .{ .feature = .recovery_resource_snapshot_gate, .status = .degraded, .evidence = "proto-ui-recovery-diff" },
    .{ .feature = .performance_adapter_hotpath_benchmark, .status = .degraded, .evidence = "proto-ui-bench" },
    .{ .feature = .compatibility_pgtk_base_gate, .status = .degraded, .evidence = "proto-ui-compat" },
    .{ .feature = .compatibility_backend_semantic_matrix, .status = .degraded, .evidence = "proto-ui-compat" },
    .{ .feature = .isolation_disabled_default_gate, .status = .degraded, .evidence = "proto-ui-isolation-audit" },
};

pub const feature_count = @typeInfo(Feature).@"enum".fields.len;

pub const Set = struct {
    bits: [feature_count]bool = [_]bool{false} ** feature_count,

    pub fn contains(self: Set, feature: Feature) bool {
        return self.bits[@intFromEnum(feature)];
    }

    pub fn insert(self: *Set, feature: Feature) void {
        self.bits[@intFromEnum(feature)] = true;
    }

    pub fn intersection(self: Set, other: Set) Set {
        var result: Set = .{};
        for (0..feature_count) |index| {
            result.bits[index] = self.bits[index] and other.bits[index];
        }
        return result;
    }
};

pub fn backendSupported() Set {
    var set: Set = .{};
    for (feature_descriptors) |item| {
        if (item.feature.negotiable() and item.status != .pending)
            set.insert(item.feature);
    }
    return set;
}

pub const frontendSupported = backendSupported;

fn descriptor(feature: Feature) FeatureDescriptor {
    for (feature_descriptors) |candidate| {
        if (candidate.feature == feature) return candidate;
    }
    unreachable;
}

fn setFromCapabilities(capabilities: []const protocol.Capability, allocator: std.mem.Allocator) !Set {
    // `decodeCapabilities` requires an allocator even though this profile does
    // not retain decoded names/values.
    _ = allocator;
    var result: Set = .{};
    for (capabilities) |capability| {
        for (feature_descriptors) |item| {
            const feature = item.feature;
            if (!feature.negotiable()) continue;
            if (!std.mem.eql(u8, capability.name, feature.name())) continue;
            if (!std.mem.eql(u8, capability.value, "1")) return Error.InvalidCapabilityValue;
            result.insert(feature);
        }
    }
    return result;
}

pub fn decodeSet(allocator: std.mem.Allocator, payload: []const u8) !Set {
    const decoded = try protocol.decodeCapabilities(allocator, payload);
    defer allocator.free(decoded);
    return setFromCapabilities(decoded, allocator);
}

pub const Negotiated = struct {
    effective: Set,
    hash: [hash_len]u8,
};

pub fn negotiate(backend: Set, frontend: Set) Error!Negotiated {
    var effective = backend.intersection(frontend);
    // The pointer semantics are adapter phases over v2 transport, not
    // independent wire capabilities. Keep intersection honest for peers that
    // advertise the upper semantic without its prerequisite.
    if (!effective.contains(.input_pointer_v2)) {
        effective.bits[@intFromEnum(Feature.input_pointer_selection_left)] = false;
        effective.bits[@intFromEnum(Feature.input_pointer_middle_paste)] = false;
    }
    if (!effective.contains(.input_pointer_selection_left))
        effective.bits[@intFromEnum(Feature.input_pointer_middle_paste)] = false;
    for (feature_descriptors) |item| {
        if (item.feature.required() and !effective.contains(item.feature))
            return Error.MissingRequiredCapability;
    }
    var negotiated: Negotiated = .{ .effective = effective, .hash = undefined };
    hashEffective(effective, &negotiated.hash);
    return negotiated;
}

pub fn hashEffective(set: Set, out: *[hash_len]u8) void {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (feature_descriptors) |item| {
        const feature = item.feature;
        if (!feature.negotiable()) continue;
        const present: u8 = if (set.contains(feature)) 1 else 0;
        hasher.update(feature.name());
        hasher.update(&.{0});
        hasher.update(&.{present});
    }
    hasher.final(out);
}

pub fn encodePayload(
    gpa: std.mem.Allocator,
    set: Set,
    out: *std.ArrayList(u8),
) !void {
    var capabilities: [feature_count]protocol.Capability = undefined;
    var count: usize = 0;
    for (feature_descriptors) |item| {
        const feature = item.feature;
        if (!feature.negotiable() or !set.contains(feature)) continue;
        capabilities[count] = .{ .name = feature.name(), .value = "1" };
        count += 1;
    }
    try protocol.encodeCapabilities(gpa, capabilities[0..count], out);
}

pub fn encodeMessage(
    gpa: std.mem.Allocator,
    set: Set,
    message_type: u16,
    sequence: u64,
    ack_sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try encodePayload(gpa, set, &payload);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.idempotent,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = ack_sequence,
        .session_id = session_id,
        .timestamp_ns = sequence,
    }, payload.items, out);
}

pub fn encodeReadyAck(
    gpa: std.mem.Allocator,
    hash: *const [hash_len]u8,
    sequence: u64,
    ack_sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.idempotent,
        .message_type = protocol.Message.ready_ack,
        .sequence = sequence,
        .ack_sequence = ack_sequence,
        .session_id = session_id,
        .timestamp_ns = sequence,
    }, hash, out);
}

pub fn validateStatusManifest() ?[]const u8 {
    var seen = [_]bool{false} ** feature_count;
    for (feature_descriptors) |item| {
        const index = @intFromEnum(item.feature);
        if (seen[index]) return "duplicate feature status";
        seen[index] = true;
        if (item.evidence.len == 0) return "missing status evidence";
        if (item.status == .implemented and !item.feature.negotiable())
            return "implemented feature must be negotiable";
        if (item.status == .pending and item.feature.required())
            return "required feature cannot remain pending";
    }
    for (seen) |seen_item| {
        if (!seen_item) return "feature missing status";
    }
    return null;
}

pub fn writeStatusManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateStatusManifest() != null) return Error.InvalidCapabilityValue;
    try out.appendSlice(gpa,
        \\{
        \\  "manifest_version": 1,
        \\  "authoritative_source": "src/proto-ui/capability.zig",
        \\  "scope": "proto-ui-epxl-profile",
        \\  "features": [
    );
    for (feature_descriptors, 0..) |item, index| {
        try out.appendSlice(gpa, "\n    {\"name\":\"");
        try out.appendSlice(gpa, item.feature.name());
        try out.appendSlice(gpa, "\",\"status\":\"");
        try out.appendSlice(gpa, item.status.name());
        try out.appendSlice(gpa, "\",\"required\":");
        try out.appendSlice(gpa, if (item.feature.required()) "true" else "false");
        try out.appendSlice(gpa, ",\"negotiable\":");
        try out.appendSlice(gpa, if (item.feature.negotiable()) "true" else "false");
        try out.appendSlice(gpa, ",\"evidence\":\"");
        // Descriptors use repository-local ASCII evidence names and never
        // contain quotes/backslashes, so this remains valid JSON.
        for (item.evidence) |byte| {
            if (byte == '"' or byte == '\\' or byte < 0x20) return Error.InvalidCapabilityValue;
            try out.append(gpa, byte);
        }
        try out.appendSlice(gpa, "\"}");
        if (index + 1 != feature_descriptors.len) try out.appendSlice(gpa, ",");
    }
    try out.appendSlice(gpa, "\n  ]\n}\n");
}

test "status manifest is complete and generated JSON is bounded" {
    try std.testing.expect(validateStatusManifest() == null);
    const gpa = std.testing.allocator;
    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(gpa);
    try writeStatusManifest(gpa, &json);
    try std.testing.expect(json.items.len > 100);
    try std.testing.expect(json.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"name\":\"resource.v1\"") != null);
}

test "capability payload round trip and unknown optional names are ignored" {
    const gpa = std.testing.allocator;
    var set = backendSupported();
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try encodePayload(gpa, set, &payload);
    const decoded = try decodeSet(gpa, payload.items);
    try std.testing.expectEqual(set.contains(.session_resync), decoded.contains(.session_resync));
    try std.testing.expect(decoded.contains(.protocol_v1));
    try std.testing.expect(!decoded.contains(.frame_output_proto));

    const unknown = protocol.Capability{ .name = "vendor.unknown", .value = "1" };
    const decoded_capabilities = try protocol.decodeCapabilities(gpa, payload.items);
    defer gpa.free(decoded_capabilities);
    var capabilities = try gpa.alloc(protocol.Capability, decoded_capabilities.len + 1);
    defer gpa.free(capabilities);
    @memcpy(capabilities[0..decoded_capabilities.len], decoded_capabilities);
    capabilities[capabilities.len - 1] = unknown;
    var combined: std.ArrayList(u8) = .empty;
    defer combined.deinit(gpa);
    try protocol.encodeCapabilities(gpa, capabilities, &combined);
    const decoded_unknown = try decodeSet(gpa, combined.items);
    try std.testing.expectEqual(set.contains(.text_ascii_bounded), decoded_unknown.contains(.text_ascii_bounded));
}

test "known malformed capability values are rejected" {
    const gpa = std.testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    const capabilities = [_]protocol.Capability{.{ .name = "protocol.v1", .value = "yes" }};
    try protocol.encodeCapabilities(gpa, &capabilities, &payload);
    try std.testing.expectError(Error.InvalidCapabilityValue, decodeSet(gpa, payload.items));
}

test "negotiation reports a stable effective-set hash" {
    const all = backendSupported();
    var without_renderer = all;
    without_renderer.bits[@intFromEnum(Feature.clipboard_ascii_bounded)] = false;
    const left = try negotiate(all, without_renderer);
    const right = try negotiate(without_renderer, all);
    try std.testing.expectEqualSlices(u8, &left.hash, &right.hash);
    try std.testing.expect(left.effective.contains(.protocol_v1));
    try std.testing.expect(!left.effective.contains(.clipboard_ascii_bounded));
}

test "negotiation intersects and enforces required features" {
    const all = backendSupported();
    const negotiated = try negotiate(all, all);
    var expected_hash: [hash_len]u8 = undefined;
    hashEffective(all, &expected_hash);
    try std.testing.expectEqualSlices(u8, &expected_hash, &negotiated.hash);

    var missing_text = all;
    missing_text.bits[@intFromEnum(Feature.text_ascii_bounded)] = false;
    try std.testing.expectError(Error.MissingRequiredCapability, negotiate(all, missing_text));

    var left_only = all;
    left_only.bits[@intFromEnum(Feature.clipboard_ascii_bounded)] = false;
    const effective = try negotiate(left_only, all);
    try std.testing.expect(!effective.effective.contains(.clipboard_ascii_bounded));
}

test "text Unicode negotiation remains optional alongside ASCII" {
    const all = backendSupported();
    const effective = try negotiate(all, all);
    try std.testing.expect(effective.effective.contains(.input_text_ascii));
    try std.testing.expect(effective.effective.contains(.input_text_unicode));

    var ascii_only = all;
    ascii_only.bits[@intFromEnum(Feature.input_text_unicode)] = false;
    const negotiated = try negotiate(all, ascii_only);
    try std.testing.expect(negotiated.effective.contains(.input_text_ascii));
    try std.testing.expect(!negotiated.effective.contains(.input_text_unicode));

    var no_text = all;
    no_text.bits[@intFromEnum(Feature.input_text_ascii)] = false;
    no_text.bits[@intFromEnum(Feature.input_text_unicode)] = false;
    const no_text_negotiated = try negotiate(all, no_text);
    try std.testing.expect(!no_text_negotiated.effective.contains(.input_text_ascii));
    try std.testing.expect(!no_text_negotiated.effective.contains(.input_text_unicode));
}

test "full key v2 remains optional for ASCII-only peers" {
    const all = backendSupported();
    const negotiated = try negotiate(all, all);
    try std.testing.expect(negotiated.effective.contains(.input_key_bounded));
    try std.testing.expect(negotiated.effective.contains(.input_key_full_v2));

    var ascii_only = all;
    ascii_only.bits[@intFromEnum(Feature.input_key_full_v2)] = false;
    const effective = try negotiate(all, ascii_only);
    try std.testing.expect(effective.effective.contains(.input_key_bounded));
    try std.testing.expect(!effective.effective.contains(.input_key_full_v2));
}

test "left pointer selection remains optional for v2-only peers" {
    const all = backendSupported();
    const negotiated = try negotiate(all, all);
    try std.testing.expect(negotiated.effective.contains(.input_pointer_v2));
    try std.testing.expect(negotiated.effective.contains(.input_pointer_selection_left));

    var transport_only = all;
    transport_only.bits[@intFromEnum(Feature.input_pointer_selection_left)] = false;
    const effective = try negotiate(all, transport_only);
    try std.testing.expect(effective.effective.contains(.input_pointer_v2));
    try std.testing.expect(!effective.effective.contains(.input_pointer_selection_left));
}

test "middle paste remains optional and selection-gated" {
    const all = backendSupported();
    const negotiated = try negotiate(all, all);
    try std.testing.expect(negotiated.effective.contains(.input_pointer_v2));
    try std.testing.expect(negotiated.effective.contains(.input_pointer_selection_left));
    try std.testing.expect(negotiated.effective.contains(.input_pointer_middle_paste));

    var v2_only = all;
    v2_only.bits[@intFromEnum(Feature.input_pointer_selection_left)] = false;
    v2_only.bits[@intFromEnum(Feature.input_pointer_middle_paste)] = false;
    const effective = try negotiate(all, v2_only);
    try std.testing.expect(effective.effective.contains(.input_pointer_v2));
    try std.testing.expect(!effective.effective.contains(.input_pointer_selection_left));
    try std.testing.expect(!effective.effective.contains(.input_pointer_middle_paste));

    var middle_only = all;
    middle_only.bits[@intFromEnum(Feature.input_pointer_selection_left)] = false;
    const selection_missing = try negotiate(all, middle_only);
    try std.testing.expect(!selection_missing.effective.contains(.input_pointer_middle_paste));
}
