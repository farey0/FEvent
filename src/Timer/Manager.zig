//! FEvent
//! Author : Farey0
//!
//! Simple Timer management

//                          ----------------   Declarations   ----------------

pub const Self = @This();

const win = @import("std").os.windows;
const TimerRequest = @import("Request.zig");

//                          ----------------      Members     ----------------

pub var queryFrequency: u64 = undefined;

first: ?*TimerRequest = null,

//                          ----------------      Public      ----------------

pub fn ResolveAndNextTimeout(self: *Self) ?u64 {
    if (self.first == null)
        return null;

    var curr = GetTime();

    while (self.first) |req| {
        if (req.fireTime > curr)
            break;

        req.cb(req);

        self.first = req.next;
    }

    // no more TimerReq
    if (self.first == null)
        return null;

    // we reget time to have precise timeout.
    // if the time is elapsed for the first Req since other cb taked time
    // it'll only be fired next round in case it could block the IO port
    curr = GetTime();
    const firstFireTime = self.first.?.fireTime;

    return if (curr < firstFireTime) 0 else @intCast(firstFireTime - curr);
}

pub fn RegisterReq(self: *Self, req: *TimerRequest, fireTimeMs: u64) void {
    req.fireTime = fireTimeMs + GetTime();

    if (self.first == null) {
        self.first = req;
        return;
    }

    if (self.first.?.fireTime > req.fireTime) {
        req.next = self.first;
        self.first = req;
    }

    var inserted: bool = false;
    var currReq = self.first;

    while (!inserted) {
        const next = currReq.?.next;

        if (next == null) {
            currReq.?.next = req;
            inserted = true;
        } else if (next.?.fireTime > req.fireTime) {
            currReq.?.next = req;
            req.next = next;
            inserted = true;
        } else {
            currReq = next;
        }
    }
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------

pub fn GetTime() u64 {
    return win.QueryPerformanceCounter() / queryFrequency;
}
