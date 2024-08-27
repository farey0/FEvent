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
pub const AcceptRequest = @import("AcceptRequest.zig");
const BaseReq = @import("../Request.zig");

pub const ReqUnion = union(enum) {
    connection: ConnectRequest,
    accept: AcceptRequest,
};

//                          ----------------      Members     ----------------

req: ReqUnion,

cb: union {
    con: ConnectRequest.Callback,
    accept: AcceptRequest.Callback,
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

            if (err != null) tcp.state = .Connected;
            anyReq.cb.con(tcp, connect, err);
        },
        .accept => {},
    }
}

pub fn CleanOV(self: *Self) void {
    self.base.overlapped = @import("std").mem.zeroes(win.OVERLAPPED);
}

//                          ------------- Public Getters/Setters -------------

pub fn SetData(self: *Self, dataPtr: anytype) void {
    self.base.SetData(dataPtr);
}

pub fn GetData(self: *Self, comptime T: type) *T {
    return self.base.GetData(T);
}

//                          ----------------      Private     ----------------
