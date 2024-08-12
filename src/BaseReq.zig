//! FEvent.
//! Author : Farey0
//!
//!

//                          ----------------   Declarations   ----------------

const Self = @This();

const Handle = @import("Handle.zig");
const win = @import("std").os.windows;

//                          ----------------      Members     ----------------

data: ?*anyopaque = null,
handle: *Handle = undefined,
overlapped: win.OVERLAPPED = undefined,

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

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
