//! W2 Emacs-facing ABI for the opt-in proto-ui backend.
//!
//! This is deliberately a registration-only seam: C code can verify that the
//! Zig backend was linked and protocol-compatible without creating terminals,
//! frames, transport endpoints, or renderer state.  W3+ extends this ABI.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Bump only when the C-facing registration ABI changes.  EUP wire-version
/// changes are tracked separately by `protocol.major_version`.
pub const abi_version: u32 = 1;

export fn proto_ui_registration_compatible(
    requested_abi: c_uint,
    eup_major: c_uint,
    eup_minor: c_uint,
) bool {
    return requested_abi == abiVersion() and eup_major == protocol.major_version and eup_minor <= protocol.minor_version;
}

fn abiVersion() c_uint {
    return abi_version;
}

test "registration ABI remains versioned" {
    try std.testing.expectEqual(@as(u32, 1), abiVersion());
    try std.testing.expect(proto_ui_registration_compatible(1, 1, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 1, 1));
    try std.testing.expect(!proto_ui_registration_compatible(2, 1, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 2, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 1, 2));
}
