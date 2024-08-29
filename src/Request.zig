//! FEvent.
//! Author : Farey0
//!
//!

//                          ----------------   Declarations   ----------------

const Self = @This();

const Handle = @import("Handle.zig");
const Win = @import("Windows.zig");

//                          ----------------      Members     ----------------

data: ?*anyopaque = null,
handle: *Handle = undefined,
overlapped: Win.Request = undefined,

//                          ----------------      Public      ----------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    if (@typeInfo(@TypeOf(dataPtr)) != .Pointer)
        @compileError("SetData can only hold pointers");

    self.data = @ptrCast(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    if (self.data == null)
        unreachable;

    return @ptrCast(self.data.?);
}

pub fn Make(handle: *Handle) Self {
    return .{
        .handle = handle,
        .overlapped = @import("std").mem.zeroes(Win.Request),
    };
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
