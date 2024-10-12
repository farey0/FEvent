//! FEvent.Tcp.Request.Connect
//!
//! Author : Farey0
//! 
//! Connection Request : Handle an asynchronous request to connect a socket to a distant host

//                          ----------------   Declarations   ----------------

const Self = @This();

const Win = @import("../../Windows.zig");
const WTcp = Win.Tcp;

const Tcp = @import("../Tcp.zig");
const TimerReq = @import("../../Timer/Request.zig");

//                          ----------------      Members     ----------------

address: WTcp.Address = .{
    .port = undefined,
    .addr = undefined,
},

timerReq: TimerReq = .{},
timeout: u64 = undefined,

//                          ----------------      Public      ----------------

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
