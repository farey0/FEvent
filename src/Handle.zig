//! FEvent.Handle
//! 
//! Author : Farey0
//!
//! Base of every handle

//                          ----------------   Declarations   ----------------

const Self = @This();

const Loop = @import("Loop.zig");

const Windows = @import("Windows.zig");

pub const Type = enum {
    Tcp,
};

//                          ----------------      Members     ----------------

type: Type = undefined,
data: ?*anyopaque = null,
loop: *Loop = undefined,

prevHandle: ?*Self = null,
nextHandle: ?*Self = null,

//                          ----------------      Public      ----------------

//                          ------------- Public Getters/Setters -------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    if (@typeInfo(@TypeOf(dataPtr)) != .pointer)
        @compileError("SetData can only hold pointers");

    self.data = @ptrCast(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    if (self.data == null)
        unreachable;

    return @ptrCast(self.data.?);
}

//                          ----------------      Private     ----------------
