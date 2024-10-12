//! FEvent.Loop
//! 
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const Mutex = @import("FLib").Mutex;
const TimerManager = @import("Timer/Manager.zig");

const Handle = @import("Handle.zig");
const BaseReq = @import("Request.zig");

const Win = @import("Windows.zig");
const WLoop = Win.Loop;

pub const StaticManager = struct {
    var data: struct {
        initialized: bool = false,
        loopCount: usize = 0,
        mutex: Mutex = .{},
    } = .{};

    pub fn InitOnce() Win.Error!void {
        data.mutex.Lock();
        defer data.mutex.Unlock();

        if (data.initialized)
            return;

        try Win.InitSystem();

        data.initialized = true;
        data.loopCount += 1;
    }

    // Decrease Loop Event count and call WSACleanup when it reaches 0
    pub fn DeInit() void {
        data.mutex.Lock();
        defer data.mutex.Unlock();

        data.loopCount -= 1;

        if (data.loopCount == 0) {

            // we already made sure that no network handle is opened and no operation is in progress
            Win.DeInitSystem();

            data.initialized = false;
        }
    }
};

//                          ----------------      Members     ----------------

loop: WLoop = .{},

activeReqCount: usize = 0,
firstHandle: ?*Handle = null,
lastHandle: ?*Handle = null,

timerManager: TimerManager = .{},

//                          ----------------      Public      ----------------

pub fn Make() !Self {
    try StaticManager.InitOnce();

    return .{
        .loop = try WLoop.Make(),
    };
}

pub fn Run(self: *Self, defaultTimeOut: ?u32) !void {
    const TimeOut: u32 = if (defaultTimeOut == null) 200 else defaultTimeOut.?;

    // OVERLAPPED_ENTRY is 32 octets, so we have largely enough stack size on windows (1mb so 16384 OVERLAPPED_ENTRY)
    var entries: [512]WLoop.Entry = undefined;

    while (self.activeReqCount != 0) {
        const resolvedTimeOut = blk: {
            const timerRet = self.timerManager.ResolveAndNextTimeout();

            if (timerRet == null or timerRet.? > TimeOut)
                break :blk TimeOut;

            break :blk @as(u32, @intCast(timerRet.?));
        };

        const removed = self.loop.DequeueEntries(&entries, resolvedTimeOut) catch |err| {
            switch (err) {
                error.TimeOut => continue,
                else => return err,
            }
        };

        for (entries[0..removed]) |entry| {
            const err: ?Win.ErrorCode = entry.GetError();
            const req = entry.GetRequest();

            switch (req.handle.type) {
                .Tcp => @import("Tcp/AnyRequest.zig").HandleCompletion(req, err, entry.dwNumberOfBytesTransferred),
            }
        }
    }
}

// Loop is invalidated after Close. Call Make to redo a loop
pub fn Close(self: *Self) error{ ReqStillOpen, HandleStillOpen }!void {
    if (self.activeReqCount != 0)
        return error.ReqStillOpen;

    if (self.firstHandle != null)
        return error.HandleStillOpen;

    self.loop.Close();

    StaticManager.DeInit();
}

// used internally
pub fn RegisterHandle(self: *Self, handle: *Handle, osHandle: Win.Handle) !void {
    try self.loop.AssociateHandle(osHandle);

    if (self.firstHandle != null) {
        handle.prevHandle = self.lastHandle;
        self.lastHandle = handle.prevHandle;
    } else {
        self.firstHandle = handle;
        self.lastHandle = handle;
    }
}

// used internally
pub fn UnregisterHandle(self: *Self, handle: *Handle) void {
    if (self.firstHandle == null)
        unreachable;

    if (self.firstHandle.? != handle and self.lastHandle.? != handle and handle.prevHandle == null and handle.nextHandle == null)
        unreachable;

    if (self.firstHandle.? == handle)
        self.firstHandle = handle.nextHandle;

    if (self.lastHandle.? == handle)
        self.lastHandle = handle.prevHandle;

    if (handle.prevHandle) |prevHandle|
        prevHandle.nextHandle = handle.nextHandle;

    if (handle.nextHandle) |nextHandle|
        nextHandle.prevHandle = handle.prevHandle;
}

//                          ------------- Public Getters/Setters -------------

//                          ----------------      Private     ----------------
