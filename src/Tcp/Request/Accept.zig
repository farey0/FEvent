//! FEvent.Tcp
//! Connection Request : Handle an asynchronous request to connect a socket to a distant host
//!
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

const Tcp = @import("../Tcp.zig");

pub const AddressSize = @sizeOf(ws2_32.sockaddr.storage) + 16;

pub const TotalAddressSize = AddressSize * 2;

//                          ----------------      Members     ----------------

accepting: *Tcp = undefined,
acceptBuffer: []u8 = undefined,

//                          ----------------      Public      ----------------

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
