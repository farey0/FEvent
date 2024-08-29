//! FEvent.Tcp.Request
//! Author : Farey0
//!
//!

//                          ----------------   Declarations   ----------------

const Self = @This();

const Win = @import("../../Windows.zig");
const WTcp = Win.Tcp;

const Tcp = @import("../Tcp.zig");

//                          ----------------      Members     ----------------

buffer: []u8 = undefined,

//                          ----------------      Public      ----------------

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
