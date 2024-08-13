//! FEvent.Tcp
//! AnyRequest : Union of all the tcp's requests with base type.
//! Use this one if you allocate memory for requests
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;

const Tcp = @import("Tcp.zig");

pub const ConnectRequest = @import("ConnectRequest.zig");
const BaseReq = @import("../Request.zig");

//                          ----------------      Members     ----------------

req: union(enum) {
    connection: ConnectRequest,
},

cb: union {
    con: ConnectRequest.Callback,
},

alive: bool = undefined,

base: BaseReq = .{},

//                          ----------------      Public      ----------------

// Public so the loop can access it. Don't use it as an user
pub fn HandleCompletion(baseReq: *BaseReq, err: ?win.Win32Error) void {
    const anyReq = @as(*Self, @fieldParentPtr("base", baseReq));
    const tcp = @as(*Tcp, @fieldParentPtr("handle", anyReq.base.handle));

    switch (anyReq.req) {
        .connection => {
            const connect = &anyReq.req.connection;

            anyReq.alive = false;
            tcp.DecReqCount();

            anyReq.cb.con(tcp, connect, err);
        },
    }
}

//                          ------------- Public Getters/Setters -------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    self.base.SetData(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    return self.base.GetData(T);
}

//                          ----------------      Private     ----------------
