//! FEvent.
//! Author : Farey0

//                          ----------------   Declarations   ----------------

const Self = @This();

const Mutex = @import("FLib").Mutex;
const TimerManager = @import("Timer/Manager.zig");

const Handle = @import("Handle.zig");
const BaseReq = @import("Request.zig");

const win = @import("std").os.windows;
const ws2_32 = win.ws2_32;

pub const StaticManager = struct {
    var data: struct {
        initialized: bool = false,
        loopCount: usize = 0,
        mutex: Mutex = .{},
        addrIPv4Any: ws2_32.sockaddr.in = undefined,
        ConnectExPtr: LPFN_CONNECTEX = undefined,
    } = .{};

    pub fn GetAddrIPv4Any() ws2_32.sockaddr.in {
        return data.addrIPv4Any;
    }

    pub extern "ntdll" fn RtlNtStatusToDosError(win.NTSTATUS) callconv(win.WINAPI) win.Win32Error;

    const LPFN_CONNECTEX = *const fn (
        s: ?ws2_32.SOCKET,
        // TODO: what to do with BytesParamIndex 2?
        name: ?*const ws2_32.sockaddr,
        namelen: i32,
        // TODO: what to do with BytesParamIndex 4?
        lpSendBuffer: ?*anyopaque,
        dwSendDataLength: u32,
        lpdwBytesSent: ?*u32,
        lpOverlapped: ?*win.OVERLAPPED,
    ) callconv(@import("std").os.windows.WINAPI) win.BOOL;

    pub fn ConnectEx(
        s: ws2_32.SOCKET,
        name: *const ws2_32.sockaddr.in,
        lpSendBuffer: ?*anyopaque,
        dwSendDataLength: win.DWORD,
        lpdwBytesSent: ?*win.DWORD,
        lpOverlapped: *win.OVERLAPPED,
    ) win.BOOL {
        return data.ConnectExPtr(s, @ptrCast(name), @sizeOf(ws2_32.sockaddr.in), lpSendBuffer, dwSendDataLength, lpdwBytesSent, lpOverlapped);
    }

    // Init WSA system and load function ConnectEx
    pub fn InitOnce() !void {
        data.mutex.Lock();
        defer data.mutex.Unlock();

        if (data.initialized)
            return;

        // divide by 1000 to get ms
        TimerManager.queryFrequency = win.QueryPerformanceFrequency() / 1000;

        try win.callWSAStartup();

        data.addrIPv4Any = .{
            .addr = ws2_32.inet_addr("0.0.0.0"),
            .port = ws2_32.htons(0),
        };

        var guid: win.GUID = ws2_32.WSAID_CONNECTEX;

        // need a dummy sock to load a function via WSAIoctl
        var dummyBytes: win.DWORD = undefined;
        const dummySock = ws2_32.socket(ws2_32.AF.INET, ws2_32.SOCK.STREAM, 0);

        // no reason that our dummy socket can't close
        defer win.closesocket(dummySock) catch unreachable;

        if (dummySock == ws2_32.INVALID_SOCKET) {
            return win.unexpectedError(win.kernel32.GetLastError());
        }

        const ret = ws2_32.WSAIoctl(
            dummySock,
            ws2_32.SIO_GET_EXTENSION_FUNCTION_POINTER,
            &guid,
            @sizeOf(@TypeOf(guid)),
            @ptrCast(&data.ConnectExPtr),
            @sizeOf(@TypeOf(data.ConnectExPtr)),
            &dummyBytes,
            null,
            null,
        );

        if (ret != 0)
            return win.unexpectedError(win.kernel32.GetLastError());

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
            win.WSACleanup() catch unreachable;

            data.initialized = false;
        }
    }
};

//                          ----------------      Members     ----------------

iocp: win.HANDLE = undefined,

activeReqCount: usize = 0,
firstHandle: ?*Handle = null,
lastHandle: ?*Handle = null,

timerManager: TimerManager = .{},

//                          ----------------      Public      ----------------

pub fn Make() !Self {
    var out: Self = .{};

    try StaticManager.InitOnce();

    out.iocp = try win.CreateIoCompletionPort(win.INVALID_HANDLE_VALUE, null, 0, 1);

    return out;
}

pub fn Run(self: *Self, defaultTimeOut: ?u32) !void {
    const TimeOut: u32 = if (defaultTimeOut == null) 1000 else defaultTimeOut.?;

    // OVERLAPPED_ENTRY is 32 octets, so we have largely enough stack size on windows (1mb so 16384 OVERLAPPED_ENTRY)
    var ovEntries: [512]win.OVERLAPPED_ENTRY = undefined;

    while (self.activeReqCount != 0) {
        const resolvedTimeOut = blk: {
            const timerRet = self.timerManager.ResolveAndNextTimeout();

            if (timerRet == null or timerRet.? > TimeOut)
                break :blk TimeOut;

            break :blk timerRet.?;
        };

        const removed = win.GetQueuedCompletionStatusEx(self.iocp, &ovEntries, @intCast(resolvedTimeOut), false) catch |err| {
            switch (err) {
                error.Timeout => continue,
                else => return err,
            }
        };

        for (ovEntries, 0..removed) |entry, _| {
            @import("std").log.warn("some entries have been dequeued", .{});

            const ntStatus = @as(win.NTSTATUS, @enumFromInt(entry.Internal));
            const err: ?win.Win32Error = if (ntStatus != .SUCCESS) StaticManager.RtlNtStatusToDosError(@enumFromInt(entry.Internal)) else null;

            const baseReq = @as(*BaseReq, @fieldParentPtr("overlapped", entry.lpOverlapped));

            switch (baseReq.handle.type) {
                .Tcp => @import("Tcp/AnyRequest.zig").HandleCompletion(baseReq, err),
            }
        }
    }
}

// Loop is invalidated after Close. Call
pub fn Close(self: *Self) error{ ReqStillOpen, HandleStillOpen }!void {
    if (self.activeReqCount != 0)
        return error.ReqStillOpen;

    if (self.firstHandle != null)
        return error.HandleStillOpen;

    win.CloseHandle(self.iocp);

    StaticManager.DeInit();
}

pub fn RegisterHandle(self: *Self, handle: *Handle) void {
    if (self.firstHandle != null) {
        handle.prevHandle = self.lastHandle;
        self.lastHandle = handle.prevHandle;
    } else {
        self.firstHandle = handle;
        self.lastHandle = handle;
    }
}

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
