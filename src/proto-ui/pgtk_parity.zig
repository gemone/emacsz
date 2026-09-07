//! Source-authoritative PGTK-to-Proto differential parity plan.
//!
//! This is planning policy, not parity evidence.  Every case starts planned;
//! `not_implemented` remains the overall status until a real PGTK reference and
//! pure SDL3 Proto runtime produce comparable evidence.

const std = @import("std");
const runtime = @import("runtime.zig");

pub const manifest_version: u32 = 1;
pub const plan_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/pgtk_parity.zig";
pub const minimum_case_count: usize = 40;

pub const PlanStatus = enum { planned, approved, active, complete, withdrawn };
pub const ParityStatus = enum { not_implemented, partial, complete };
pub const Priority = enum { p0, p1, p2 };
pub const CaseStatus = enum { planned, running, passed, failed, skipped };
pub const Backend = enum {
    pgtk_reference,
    proto_sdl3,
    both,

    pub fn name(self: Backend) []const u8 {
        return switch (self) {
            .pgtk_reference => "PGTK reference",
            .proto_sdl3 => "pure SDL3 Proto",
            .both => "PGTK and pure SDL3 Proto",
        };
    }
};

pub const Case = struct {
    id: []const u8,
    domain: []const u8,
    title: []const u8,
    procedure: []const u8,
    compared_evidence: []const []const u8,
    required_support: []const []const u8,
    priority: Priority,
    status: CaseStatus = .planned,
    blocking_final: bool,
};

pub const Plan = struct {
    plan_status: PlanStatus = .planned,
    parity_status: ParityStatus = .not_implemented,
    pgtk_role: []const u8 = "reference_only",
    proto_ui_backend: []const u8 = "sdl3",
    terminal_type: []const u8 = "output_proto",
    pgtk_runtime_fallback_allowed: bool = false,
    tty_runtime_fallback_allowed: bool = false,
    frontend_may_evaluate_elisp: bool = false,
    frontend_may_own_emacs_layout: bool = false,
};

pub const plan = Plan{};

pub const cases = [_]Case{
    .{ .id = "frame_create_delete", .domain = "frame_platform", .title = "Create and delete a graphic frame", .procedure = "Create a frame, wait for visible geometry, then delete it and compare lifecycle parameters and exit cleanup.", .compared_evidence = &.{ "window-system", "live/visible transitions", "geometry samples", "delete cleanup" }, .required_support = &.{ "terminal.lifecycle", "frame.create", "frame.delete", "EUP frame lifecycle" }, .priority = .p0, .blocking_final = true },
    .{ .id = "frame_geometry_resize", .domain = "frame_platform", .title = "Set and resize frame geometry", .procedure = "Set character and pixel sizes, resize twice, and compare stable frame/window geometry.", .compared_evidence = &.{ "frame-pixel-width", "frame-pixel-height", "window body geometry", "EUP frame header" }, .required_support = &.{ "frame.geometry", "window.geometry", "resize.redisplay" }, .priority = .p0, .blocking_final = true },
    .{ .id = "frame_title_parameters", .domain = "frame_platform", .title = "Frame title and parameters", .procedure = "Set title, name, icon name, and explicit frame parameters, then compare reported values.", .compared_evidence = &.{ "frame-parameter title", "frame-parameter name", "protocol frame metadata" }, .required_support = &.{ "frame.metadata", "window.title" }, .priority = .p1, .blocking_final = true },
    .{ .id = "frame_visibility_iconify", .domain = "frame_platform", .title = "Visibility and iconification", .procedure = "Make frame invisible, visible, iconified, and restored; sample state after each transition.", .compared_evidence = &.{ "frame-visible-p", "frame-visibility", "SDL window state" }, .required_support = &.{ "frame.visibility", "platform.window.events" }, .priority = .p0, .blocking_final = true },
    .{ .id = "frame_focus_states", .domain = "frame_platform", .title = "Focus gained and lost", .procedure = "Focus and unfocus the frame while multiple frames exist; compare focus and active state.", .compared_evidence = &.{ "selected-frame", "focus-state", "cursor active state" }, .required_support = &.{ "frame.focus", "platform.focus.events" }, .priority = .p0, .blocking_final = true },
    .{ .id = "frame_fullscreen_maximized", .domain = "frame_platform", .title = "Fullscreen and maximized states", .procedure = "Cycle maximized, fullscreen, and fullscreenboth states; compare restored geometry.", .compared_evidence = &.{ "frame-parameter fullscreen", "restored geometry", "platform window events" }, .required_support = &.{ "frame.state", "platform.window.requests" }, .priority = .p1, .blocking_final = true },
    .{ .id = "monitor_move_dpi_scale", .domain = "frame_platform", .title = "Monitor move and scale change", .procedure = "Move the frame between monitors or change scale; compare logical geometry and redisplay.", .compared_evidence = &.{ "logical frame size", "scale", "DPI", "text layout digest" }, .required_support = &.{ "platform.monitor.events", "frame.scale" }, .priority = .p1, .blocking_final = true },

    .{ .id = "window_split_horizontal", .domain = "window_display", .title = "Horizontal window split", .procedure = "Split window horizontally, resize, select both sides, then delete the window.", .compared_evidence = &.{ "window tree", "window edges", "selected window", "text digest" }, .required_support = &.{ "window.tree", "window.geometry", "redisplay.rows" }, .priority = .p0, .blocking_final = true },
    .{ .id = "window_split_vertical", .domain = "window_display", .title = "Vertical window split", .procedure = "Split window vertically, resize, select both sides, then delete the window.", .compared_evidence = &.{ "window tree", "window edges", "selected window", "text digest" }, .required_support = &.{ "window.tree", "window.geometry", "redisplay.rows" }, .priority = .p0, .blocking_final = true },
    .{ .id = "window_scroll_long_line", .domain = "window_display", .title = "Long line and horizontal scroll", .procedure = "Enable truncate lines, move across a long line, and scroll horizontally.", .compared_evidence = &.{ "window hscroll", "point", "visible text digest", "truncation markers" }, .required_support = &.{ "redisplay.rows", "window.hscroll" }, .priority = .p0, .blocking_final = true },
    .{ .id = "window_vertical_scroll", .domain = "window_display", .title = "Vertical scrolling and recenter", .procedure = "Scroll up/down, recenter, and compare window-start, point, cursor, and visible rows.", .compared_evidence = &.{ "window-start", "point", "cursor row/column", "visible row hashes" }, .required_support = &.{ "redisplay.rows", "viewport.facts", "cursor" }, .priority = .p0, .blocking_final = true },
    .{ .id = "display_ascii_wrapping", .domain = "window_display", .title = "ASCII wrapping and continuation", .procedure = "Resize through narrow widths with wrapping enabled and compare continuation rows.", .compared_evidence = &.{ "row count", "wrap points", "continuation glyphs", "visible text hashes" }, .required_support = &.{ "redisplay.rows", "font.metrics", "continuation.glyph" }, .priority = .p0, .blocking_final = true },
    .{ .id = "display_truncation_bidi", .domain = "window_display", .title = "Truncation and BiDi visual order", .procedure = "Display mixed LTR/RTL text with truncation and compare visual-order run data.", .compared_evidence = &.{ "visual glyph order", "truncation position", "row digest" }, .required_support = &.{ "redisplay.runs", "bidi.order", "font.metrics" }, .priority = .p0, .blocking_final = true },
    .{ .id = "display_cjk_ligature", .domain = "window_display", .title = "CJK and ligature shaping", .procedure = "Render CJK and Latin ligature fixtures; compare clusters, advances, and missing glyphs.", .compared_evidence = &.{ "glyph clusters", "advances", "row height", "rendered text digest" }, .required_support = &.{ "font.selection", "shaping.runs", "glyph.atlas" }, .priority = .p0, .blocking_final = true },
    .{ .id = "display_point_region", .domain = "window_display", .title = "Point, mark, and active region", .procedure = "Move point, set mark, select text, and compare point/region/cursor semantics.", .compared_evidence = &.{ "point", "mark", "region face", "cursor rectangle" }, .required_support = &.{ "redisplay.cursor", "region.face", "selection.model" }, .priority = .p0, .blocking_final = true },

    .{ .id = "face_foreground_background", .domain = "faces_fonts", .title = "Foreground and background faces", .procedure = "Apply disjoint foreground/background overlays and compare effective face spans.", .compared_evidence = &.{ "face resource generation", "color spans", "rendered scene digest" }, .required_support = &.{ "face.define", "redisplay.runs", "renderer.colors" }, .priority = .p0, .blocking_final = true },
    .{ .id = "face_inverse_video", .domain = "faces_fonts", .title = "Inverse video", .procedure = "Enable inverse video on text and the mode line; compare effective face colors.", .compared_evidence = &.{ "face foreground/background swap", "rendered region digest" }, .required_support = &.{ "face.merge", "face.define", "redisplay.runs" }, .priority = .p0, .blocking_final = true },
    .{ .id = "face_underline_overline_strike", .domain = "faces_fonts", .title = "Underline, overline, and strike", .procedure = "Apply each decoration and combinations; compare style and position evidence.", .compared_evidence = &.{ "decoration styles", "color/position", "draw commands" }, .required_support = &.{ "face.decorations", "renderer.text" }, .priority = .p1, .blocking_final = true },
    .{ .id = "face_box_line_spacing", .domain = "faces_fonts", .title = "Box face and line spacing", .procedure = "Apply box faces and line-spacing values; compare geometry and draw order.", .compared_evidence = &.{ "box rectangle", "line height", "spacing", "scene digest" }, .required_support = &.{ "face.box", "row.metrics", "renderer.rectangles" }, .priority = .p1, .blocking_final = true },
    .{ .id = "font_variable_pitch_metrics", .domain = "faces_fonts", .title = "Variable pitch metrics", .procedure = "Switch a buffer to variable pitch and compare font identity plus glyph metrics.", .compared_evidence = &.{ "font resource generation", "ascent/descent", "glyph advances", "row digest" }, .required_support = &.{ "font.define", "font.metrics", "redisplay.runs" }, .priority = .p0, .blocking_final = true },
    .{ .id = "font_missing_glyph_fallback", .domain = "faces_fonts", .title = "Missing glyph fallback", .procedure = "Render unsupported codepoints and compare fallback markers and subsequent text flow.", .compared_evidence = &.{ "glyphless representation", "fallback font", "advance/row digest" }, .required_support = &.{ "font.fallback", "glyphless.run", "glyph.atlas" }, .priority = .p0, .blocking_final = true },
    .{ .id = "resource_generation_invalidation", .domain = "resources_images", .title = "Resource generation invalidation", .procedure = "Redefine a face/font/image and verify stale-generation draws are rejected and refreshed.", .compared_evidence = &.{ "generation transition", "cache eviction", "next rendered frame" }, .required_support = &.{ "resource.generations", "resource.request", "renderer.cache" }, .priority = .p0, .blocking_final = true },
    .{ .id = "image_static_formats", .domain = "resources_images", .title = "Static image formats", .procedure = "Insert supported PNG/JPEG/SVG/XPM images and compare placement and scaling.", .compared_evidence = &.{ "image resource id", "display rectangle", "scaled scene digest" }, .required_support = &.{ "image.define", "image.data", "renderer.textures" }, .priority = .p0, .blocking_final = true },
    .{ .id = "image_mask_scaling_animation", .domain = "resources_images", .title = "Masks, scaling, and animation", .procedure = "Exercise masked, scaled, and animated images where PGTK supports them.", .compared_evidence = &.{ "alpha behavior", "filter", "animation frame", "resource lifecycle" }, .required_support = &.{ "image.format", "image.animation", "renderer.textures" }, .priority = .p1, .blocking_final = true },
    .{ .id = "fringe_margins_visual", .domain = "resources_images", .title = "Fringes and margins", .procedure = "Display continuation, wrap, truncation, and user fringe/margin content.", .compared_evidence = &.{ "fringe bitmap", "margin width", "visual row digest" }, .required_support = &.{ "fringe.bitmap", "margin.widget", "redisplay.rows" }, .priority = .p1, .blocking_final = true },

    .{ .id = "keyboard_basic_modifiers", .domain = "input", .title = "Basic keys and modifiers", .procedure = "Send letters, digits, control, meta, shift, super, and function keys through both stacks.", .compared_evidence = &.{ "key description", "command executed", "buffer result" }, .required_support = &.{ "input.key", "input.modifiers", "command.loop" }, .priority = .p0, .blocking_final = true },
    .{ .id = "keyboard_prefix_sequences", .domain = "input", .title = "Prefix and incomplete key sequences", .procedure = "Exercise C-x prefixes, escapes, incomplete sequences, and keyboard quit.", .compared_evidence = &.{ "pending key sequence", "quit signal", "command result" }, .required_support = &.{ "input.key", "keymap.prefix", "command.loop" }, .priority = .p0, .blocking_final = true },
    .{ .id = "keyboard_repeat_macros", .domain = "input", .title = "Repeat counts and keyboard macros", .procedure = "Record/run a macro with numeric prefix arguments and compare repeated edits.", .compared_evidence = &.{ "repeat count", "macro events", "buffer digest" }, .required_support = &.{ "input.repeat", "macro.recording", "command.loop" }, .priority = .p1, .blocking_final = true },
    .{ .id = "pointer_click_drag_position", .domain = "input", .title = "Mouse click, drag, and position", .procedure = "Click, drag region, right/middle click, and compare buffer/selection commands.", .compared_evidence = &.{ "point", "region", "command history", "button/click counts" }, .required_support = &.{ "pointer.v2", "mouse.commands", "selection.model" }, .priority = .p0, .blocking_final = true },
    .{ .id = "wheel_touch_scroll", .domain = "input", .title = "Wheel and touch scrolling", .procedure = "Send line/pixel wheel and touch scroll gestures; compare scroll semantics.", .compared_evidence = &.{ "window-start", "pixel scroll", "gesture command" }, .required_support = &.{ "wheel.events", "touch.events", "scroll.model" }, .priority = .p1, .blocking_final = true },
    .{ .id = "ime_preedit_commit", .domain = "input", .title = "IME preedit and commit", .procedure = "Use CJK IME composition; compare candidate placement, preedit updates, and final text.", .compared_evidence = &.{ "preedit geometry", "candidate state", "committed buffer text" }, .required_support = &.{ "ime.geometry", "ime.preedit", "text.commit" }, .priority = .p0, .blocking_final = true },

    .{ .id = "clipboard_unicode_targets", .domain = "selection_clipboard", .title = "Clipboard targets and Unicode", .procedure = "Copy/paste plain and Unicode text through platform clipboard with target negotiation.", .compared_evidence = &.{ "clipboard targets", "encoding", "kill-ring/yank result" }, .required_support = &.{ "clipboard.text", "selection.targets", "unicode.payload" }, .priority = .p0, .blocking_final = true },
    .{ .id = "primary_selection_ownership", .domain = "selection_clipboard", .title = "PRIMARY selection ownership", .procedure = "Select text in each backend and paste across an external owner where available.", .compared_evidence = &.{ "selection owner", "selected text", "yank result" }, .required_support = &.{ "selection.primary", "selection.ownership", "clipboard.text" }, .priority = .p1, .blocking_final = true },
    .{ .id = "secondary_selection", .domain = "selection_clipboard", .title = "SECONDARY selection", .procedure = "Exercise SECONDARY selection where the platform exposes it.", .compared_evidence = &.{ "selection value", "ownership transitions" }, .required_support = &.{ "selection.secondary", "selection.ownership" }, .priority = .p2, .blocking_final = false },
    .{ .id = "dnd_text_files", .domain = "selection_clipboard", .title = "Drag and drop text/files", .procedure = "Drop text and files; compare position feedback and Emacs actions.", .compared_evidence = &.{ "drop position", "payload URIs", "command result" }, .required_support = &.{ "dnd.events", "file.uri", "command.loop" }, .priority = .p1, .blocking_final = true },

    .{ .id = "menubar_model_activation", .domain = "widgets_desktop", .title = "Menu bar model", .procedure = "Update menu maps, activate entries, and compare menu model/commands.", .compared_evidence = &.{ "menu items", "enable state", "selected command" }, .required_support = &.{ "menu.model", "widget.events", "command.loop" }, .priority = .p1, .blocking_final = true },
    .{ .id = "popup_menu_radio_checkbox", .domain = "widgets_desktop", .title = "Popup, radio, and checkbox menus", .procedure = "Open context menus with separators and selectable states; compare selection.", .compared_evidence = &.{ "popup hierarchy", "selected value", "variable state" }, .required_support = &.{ "menu.popup", "menu.item.state", "widget.events" }, .priority = .p1, .blocking_final = true },
    .{ .id = "dialogs_prompts", .domain = "widgets_desktop", .title = "Dialogs and interactive prompts", .procedure = "Exercise yes/no, prompt, file, color, and font dialogs where PGTK uses them.", .compared_evidence = &.{ "dialog model", "result value", "Emacs callback" }, .required_support = &.{ "dialog.model", "file.dialog", "widget.result" }, .priority = .p1, .blocking_final = true },
    .{ .id = "tooltip_model_placement", .domain = "widgets_desktop", .title = "Tooltip placement and hide", .procedure = "Show help-echo tooltips and compare delay, text, placement, and hide.", .compared_evidence = &.{ "tooltip text", "position", "visibility timeout" }, .required_support = &.{ "tooltip.model", "pointer.position", "platform.surface" }, .priority = .p1, .blocking_final = true },
    .{ .id = "mode_header_tab_toolbar", .domain = "widgets_desktop", .title = "Mode, header, tab, and tool bars", .procedure = "Change mode-line/header-line/tab-line/tool-bar items and click them.", .compared_evidence = &.{ "item model", "face", "click command", "render digest" }, .required_support = &.{ "window.widgets", "face.resources", "mouse.commands" }, .priority = .p0, .blocking_final = true },
    .{ .id = "scrollbar_drag_model", .domain = "widgets_desktop", .title = "Scrollbar drag", .procedure = "Drag scrollbar through start, middle, end, and compare model scroll.", .compared_evidence = &.{ "window-start", "scroll ratio", "drag events" }, .required_support = &.{ "scrollbar.widget", "scroll.model", "pointer.events" }, .priority = .p1, .blocking_final = true },

    .{ .id = "frontend_disconnect_recovery", .domain = "recovery", .title = "Frontend disconnect and reconnect", .procedure = "Kill SDL frontend during editing, reconnect, and compare Emacs state/resync scene.", .compared_evidence = &.{ "Emacs frame alive", "resync digest", "event sequence" }, .required_support = &.{ "session.resync", "resource.snapshot", "transport.recovery" }, .priority = .p0, .blocking_final = true },
    .{ .id = "malformed_protocol_containment", .domain = "recovery", .title = "Malformed protocol containment", .procedure = "Inject malformed EUP messages while frames remain live; compare Emacs state.", .compared_evidence = &.{ "handled error count", "Emacs state unchanged", "frontend result" }, .required_support = &.{ "protocol.validation", "crash.isolation", "session.recovery" }, .priority = .p0, .blocking_final = true },
    .{ .id = "gpu_loss_software_recovery", .domain = "recovery", .title = "GPU loss and software recovery", .procedure = "Force renderer reset, then recover on GPU or software and compare next full frame.", .compared_evidence = &.{ "renderer recreation", "resource reload", "scene digest" }, .required_support = &.{ "renderer.reset", "resource.snapshot", "presentation" }, .priority = .p0, .blocking_final = true },
    .{ .id = "replay_resource_snapshot", .domain = "recovery", .title = "Replay and resource snapshot", .procedure = "Disconnect after resource changes and verify replay plus atomic snapshot restore.", .compared_evidence = &.{ "canonical scene digest", "resource digest", "accepted sequence" }, .required_support = &.{ "erp1.replay", "resource.snapshot", "ack.journal" }, .priority = .p0, .blocking_final = true },
    .{ .id = "typing_scroll_latency", .domain = "performance", .title = "Typing and scroll latency", .procedure = "Benchmark repeated insertion, deletion, and scrolling under identical buffers.", .compared_evidence = &.{ "p50/p95/p99 latency", "frame present/skip", "allocation counters" }, .required_support = &.{ "performance.benchmark", "damage.presentation", "protocol.counters" }, .priority = .p0, .blocking_final = true },
    .{ .id = "resize_resize_performance", .domain = "performance", .title = "Resize performance", .procedure = "Resize through increasing geometries and compare latency plus missed frames.", .compared_evidence = &.{ "resize latency", "redisplay generation", "frame counters" }, .required_support = &.{ "performance.benchmark", "redisplay.rows", "presentation" }, .priority = .p0, .blocking_final = true },
    .{ .id = "shutdown_clean_exit", .domain = "lifecycle", .title = "Clean shutdown and drain", .procedure = "Save-modified-prompt then kill Emacs and verify frame/session cleanup.", .compared_evidence = &.{ "session drain", "surface destruction", "daemon termination" }, .required_support = &.{ "lifecycle.drain", "frame.delete", "transport.close" }, .priority = .p0, .blocking_final = true },
};

pub const Counters = struct {
    total_cases: usize,
    planned: usize,
    running: usize,
    passed: usize,
    failed: usize,
    skipped: usize,
    p0: usize,
    p1: usize,
    p2: usize,
    blocking_final: usize,
};

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try runtime.appendJsonStringPublic(gpa, out, value);
}

fn appendJsonStringArray(gpa: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8) !void {
    try out.append(gpa, '[');
    for (values, 0..) |value, index| {
        if (index != 0) try out.append(gpa, ',');
        try appendJsonString(gpa, out, value);
    }
    try out.append(gpa, ']');
}

pub fn counters() Counters {
    var result = Counters{
        .total_cases = cases.len,
        .planned = 0,
        .running = 0,
        .passed = 0,
        .failed = 0,
        .skipped = 0,
        .p0 = 0,
        .p1 = 0,
        .p2 = 0,
        .blocking_final = 0,
    };
    for (cases) |item| {
        switch (item.status) {
            .planned => result.planned += 1,
            .running => result.running += 1,
            .passed => result.passed += 1,
            .failed => result.failed += 1,
            .skipped => result.skipped += 1,
        }
        switch (item.priority) {
            .p0 => result.p0 += 1,
            .p1 => result.p1 += 1,
            .p2 => result.p2 += 1,
        }
        if (item.blocking_final) result.blocking_final += 1;
    }
    return result;
}

fn validateCase(item: Case, index: usize, seen_ids: []const []const u8) ?[]const u8 {
    if (item.id.len == 0 or item.domain.len == 0 or item.title.len == 0 or item.procedure.len == 0)
        return "case identity or procedure is empty";
    if (item.compared_evidence.len == 0 or item.required_support.len == 0)
        return "case evidence/support is empty";
    for (item.compared_evidence) |value| {
        if (value.len == 0) return "empty compared evidence";
    }
    for (item.required_support) |value| {
        if (value.len == 0) return "empty required support";
    }
    for (seen_ids, 0..) |previous, previous_index| {
        if (previous_index != index and std.mem.eql(u8, previous, item.id))
            return "duplicate case id";
    }
    if (item.priority == .p0 and !item.blocking_final)
        return "P0 case does not block final acceptance";
    if (item.status != .planned)
        return "planning artifact contains a non-planned case";
    return null;
}

pub fn validateState() ?[]const u8 {
    if (cases.len < minimum_case_count) return "insufficient parity cases";
    if (plan.plan_status != .planned) return "parity plan is not in planned state";
    if (plan.parity_status != .not_implemented) return "parity unexpectedly claimed";
    if (!std.mem.eql(u8, plan.pgtk_role, "reference_only"))
        return "PGTK is not reference-only";
    if (!std.mem.eql(u8, plan.proto_ui_backend, "sdl3"))
        return "Proto UI backend is not SDL3";
    if (!std.mem.eql(u8, plan.terminal_type, "output_proto"))
        return "terminal type is not output_proto";
    if (plan.pgtk_runtime_fallback_allowed or plan.tty_runtime_fallback_allowed)
        return "runtime fallback is not forbidden";
    if (plan.frontend_may_evaluate_elisp or plan.frontend_may_own_emacs_layout)
        return "frontend ownership policy is invalid";

    var ids: [cases.len][]const u8 = undefined;
    for (cases, 0..) |item, index| {
        if (validateCase(item, index, ids[0..index])) |problem| return problem;
        ids[index] = item.id;
    }
    const counts = counters();
    if (counts.planned != counts.total_cases) return "unexpected non-planned counter";
    if (counts.p0 == 0 or counts.blocking_final == 0)
        return "parity plan has no blocking P0 coverage";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return error.InvalidParityPlan;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-pgtk-parity-plan\",");
    try out.appendSlice(gpa, "\"authoritative_source\":\"");
    try out.appendSlice(gpa, authoritative_source);
    try out.appendSlice(gpa, "\",\"plan_schema_version\":");
    try out.print(gpa, "{d}", .{plan_schema_version});
    try out.appendSlice(gpa, ",\"plan_status\":\"");
    try out.appendSlice(gpa, @tagName(plan.plan_status));
    try out.appendSlice(gpa, "\",\"parity_status\":\"");
    try out.appendSlice(gpa, @tagName(plan.parity_status));
    try out.appendSlice(gpa, "\",\"pgtk_role\":");
    try appendJsonString(gpa, out, plan.pgtk_role);
    try out.appendSlice(gpa, ",\"proto_ui_backend\":");
    try appendJsonString(gpa, out, plan.proto_ui_backend);
    try out.appendSlice(gpa, ",\"terminal_type\":");
    try appendJsonString(gpa, out, plan.terminal_type);
    try out.appendSlice(gpa, ",\"runtime_fallback\":{\"pgtk_allowed\":");
    try out.print(gpa, "{}", .{plan.pgtk_runtime_fallback_allowed});
    try out.appendSlice(gpa, ",\"tty_allowed\":");
    try out.print(gpa, "{}", .{plan.tty_runtime_fallback_allowed});
    try out.appendSlice(gpa, "},\"ownership\":{\"frontend_may_evaluate_elisp\":");
    try out.print(gpa, "{}", .{plan.frontend_may_evaluate_elisp});
    try out.appendSlice(gpa, ",\"frontend_may_own_emacs_layout\":");
    try out.print(gpa, "{}", .{plan.frontend_may_own_emacs_layout});
    try out.appendSlice(gpa, "},\"counters\":");
    try writeCounters(gpa, out);
    try out.appendSlice(gpa, ",\"cases\":[");
    for (cases, 0..) |item, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"id\":");
        try appendJsonString(gpa, out, item.id);
        try out.appendSlice(gpa, ",\"domain\":");
        try appendJsonString(gpa, out, item.domain);
        try out.appendSlice(gpa, ",\"title\":");
        try appendJsonString(gpa, out, item.title);
        try out.appendSlice(gpa, ",\"procedure\":");
        try appendJsonString(gpa, out, item.procedure);
        try out.appendSlice(gpa, ",\"compared_evidence\":");
        try appendJsonStringArray(gpa, out, item.compared_evidence);
        try out.appendSlice(gpa, ",\"required_support\":");
        try appendJsonStringArray(gpa, out, item.required_support);
        try out.appendSlice(gpa, ",\"priority\":\"");
        try out.appendSlice(gpa, @tagName(item.priority));
        try out.appendSlice(gpa, "\",\"status\":\"");
        try out.appendSlice(gpa, @tagName(item.status));
        try out.appendSlice(gpa, "\",\"blocking_final\":");
        try out.print(gpa, "{}", .{item.blocking_final});
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "]}\n");
}

fn writeCounters(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    const counts = counters();
    try out.appendSlice(gpa, "{\"total_cases\":");
    try out.print(gpa, "{d}", .{counts.total_cases});
    try out.appendSlice(gpa, ",\"planned\":");
    try out.print(gpa, "{d}", .{counts.planned});
    try out.appendSlice(gpa, ",\"running\":");
    try out.print(gpa, "{d}", .{counts.running});
    try out.appendSlice(gpa, ",\"passed\":");
    try out.print(gpa, "{d}", .{counts.passed});
    try out.appendSlice(gpa, ",\"failed\":");
    try out.print(gpa, "{d}", .{counts.failed});
    try out.appendSlice(gpa, ",\"skipped\":");
    try out.print(gpa, "{d}", .{counts.skipped});
    try out.appendSlice(gpa, ",\"p0\":");
    try out.print(gpa, "{d}", .{counts.p0});
    try out.appendSlice(gpa, ",\"p1\":");
    try out.print(gpa, "{d}", .{counts.p1});
    try out.appendSlice(gpa, ",\"p2\":");
    try out.print(gpa, "{d}", .{counts.p2});
    try out.appendSlice(gpa, ",\"blocking_final\":");
    try out.print(gpa, "{d}", .{counts.blocking_final});
    try out.append(gpa, '}');
}

test "parity plan is complete enough and remains honest" {
    try std.testing.expect(cases.len >= minimum_case_count);
    try std.testing.expectEqual(PlanStatus.planned, plan.plan_status);
    try std.testing.expectEqual(ParityStatus.not_implemented, plan.parity_status);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    const counts = counters();
    try std.testing.expectEqual(cases.len, counts.planned);
    try std.testing.expect(counts.p0 >= 20);
    try std.testing.expect(counts.blocking_final >= counts.p0);
}

test "parity manifest is deterministic JSON" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 256 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"plan_status\":\"planned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"parity_status\":\"not_implemented\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_fallback\":{\"pgtk_allowed\":false") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value{ .object = parsed.value.object }, parsed.value);
}

test "invalid case status and duplicate ids are rejected" {
    var running = cases[0];
    running.status = .running;
    try std.testing.expectEqualStrings("planning artifact contains a non-planned case", validateCase(running, 0, &.{}).?);

    const duplicated = [_][]const u8{cases[1].id};
    try std.testing.expectEqualStrings("duplicate case id", validateCase(cases[1], 1, &duplicated).?);
}
