//! FEvent
//! Author : Farey0
//!
//!

//                          ----------------   Declarations   ----------------

const Self = @This();

pub const Callback = *const fn (req: *Self) void;

//                          ----------------      Members     ----------------

// Not sharing baseReq as it is not an overlapped operation
data: ?*anyopaque = null,

next: ?*Self = null,

fireTime: u64 = undefined,

cb: Callback = undefined,

//                          ----------------      Public      ----------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    if (@typeInfo(@TypeOf(dataPtr)) != .Pointer)
        @compileError("SetData can only hold pointers");

    self.data = @ptrCast(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    if (self.data == null)
        unreachable;

    return @ptrCast(@alignCast(self.data.?));
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
