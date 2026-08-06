//! Disable address-space randomization for this process and its children.
//!
//! The dumped image (temacs.pdmp / bootstrap-emacs.pdmp) relocates
//! absolute pointers at load time, and that relocation is sensitive to
//! the address layout: with ASLR on, a load can intermittently land with
//! corrupted statics (e.g. the allocator's mem_root) and crash at the
//! first allocation.  The shell-based pipeline worked around this by
//! running emacs under `setarch -R`; these native Zig tools reproduce
//! the same effect with the personality(2) syscall (ADDR_NO_RANDOMIZE),
//! which is inherited across exec, so a single call before spawning
//! temacs covers every child.

const std = @import("std");
const builtin = @import("builtin");

pub fn disableAslr() void {
    if (comptime builtin.os.tag != .linux) return;
    // linux/personality.h: ADDR_NO_RANDOMIZE = 0x0040000.
    _ = std.os.linux.syscall1(.personality, 0x0040000);
}
