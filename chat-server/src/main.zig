const std = @import("std");
const os = std.posix;
const net = std.net;
const mem = std.mem;
const expect = std.testing.expect;
const MessageSendError = os.SendError || error{MissingTerminatorError};

fn send_message(sockfd: os.socket_t, msg_buf: []const u8) MessageSendError!usize {
    if (msg_buf[msg_buf.len - 1] != '\n') {
        return MessageSendError.MissingTerminatorError;
    }
    const bytes_sent = os.send(sockfd, msg_buf, 0) catch |err| return err;
    return bytes_sent;
}

fn broadcast_message(msg_buf: []const u8, blacklist: []os.fd_t, pfds: []os.pollfd) MessageSendError!void {
    for (pfds) |pfd| {
        if (mem.indexOfScalar(os.fd_t, blacklist, pfd.fd) == null and pfd.fd != -1) {
            _ = try send_message(pfd.fd, msg_buf);
        }
    }
}

fn make_poll_fd(fd: os.fd_t, events: comptime_int) os.pollfd {
    return .{ .fd = fd, .events = events, .revents = 0 };
}

pub fn main() !void {
    const PORT = 2028;
    const INITIAL_PFD_COUNT = 5;
    const MAX_PFD_COUNT = 10;

    const stdout = std.io.getStdOut().writer();

    var alloc_buf: [1000]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(&alloc_buf);
    var allocator = fba.allocator();

    var pfds: []os.pollfd = try allocator.alloc(os.pollfd, INITIAL_PFD_COUNT);
    defer allocator.free(pfds);

    const listen_sock: i32 = try os.socket(os.AF.INET, os.SOCK.STREAM, 0);
    try os.setsockopt(listen_sock, os.SOL.SOCKET, os.SO.REUSEADDR, &mem.toBytes(@as(c_int, 1)));
    pfds[0] = make_poll_fd(listen_sock, os.POLL.IN);
    var fd_count: u8 = 1;

    for (fd_count..INITIAL_PFD_COUNT) |idx| {
        pfds[idx] = make_poll_fd(-1, 0);
    }

    var recv_buf: [100]u8 = undefined;
    var msg_buf: [100]u8 = undefined;
    var msg_buf_slice: []u8 = undefined;

    const my_addr: std.net.Address = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, PORT);
    var his_addr: std.net.Address = undefined;

    try os.bind(listen_sock, @ptrCast(&my_addr), my_addr.getOsSockLen());
    try os.listen(listen_sock, MAX_PFD_COUNT);
    try stdout.print("listening for connections on port {d}\n", .{PORT});
    defer os.close(listen_sock);

    while (true) {
        _ = try os.poll(pfds, -1);
        for (pfds, 0..) |pfd, idx| {
            if (pfd.fd < 0) {
                continue;
            }
            if (pfd.fd == listen_sock) {
                // listener socket
                if (pfd.revents & os.POLL.IN != 0) {
                    // ready to accept new connections
                    const conn_fd = try os.accept(listen_sock, @constCast(@ptrCast(&my_addr)), @constCast(@ptrCast(&my_addr.getOsSockLen())), 0);
                    var size_of_sockaddr: os.socklen_t = @sizeOf(os.sockaddr);
                    try os.getpeername(conn_fd, @ptrCast(&his_addr), &size_of_sockaddr);

                    if (fd_count + 1 > MAX_PFD_COUNT) {
                        _ = os.send(conn_fd, "Maximum number of connections reached on server, please try again later\n", 0) catch |err| {
                            try stdout.print("Unexpected error when sending connection rejected message to client: {!}", .{err});
                        };
                        os.close(conn_fd);
                        continue;
                    }
                    if (fd_count == INITIAL_PFD_COUNT) {
                        pfds = try allocator.realloc(pfds, MAX_PFD_COUNT);
                        for (INITIAL_PFD_COUNT..MAX_PFD_COUNT) |curr_idx| {
                            pfds[curr_idx] = make_poll_fd(-1, 0);
                        }
                    }
                    pfds[fd_count] = make_poll_fd(conn_fd, os.POLL.IN | os.POLL.HUP);
                    fd_count += 1;

                    try stdout.print("new connection: {?}\n", .{his_addr});
                }
            } else {
                var bytes_sent: usize = undefined;

                if (pfd.revents & (os.POLL.NVAL | os.POLL.HUP) != 0) {
                    // NVAL - fd closed unexpectedly
                    // HUP - fd closed on clientside
                    pfds[idx].fd = -1;
                    if (pfd.revents & (os.POLL.HUP) != 0) {
                        os.close(pfds[idx].fd);
                    }
                    continue;
                }

                if (pfd.revents & os.POLL.IN != 0) {
                    bytes_sent = try os.recv(pfd.fd, &recv_buf, 0);
                    if (bytes_sent == 0) {
                        os.close(pfds[idx].fd);
                        const last_index = fd_count - 1;
                        pfds[idx] = pfds[last_index];
                        pfds[last_index].fd = -1;
                        fd_count -= 1;
                        continue;
                    }

                    msg_buf_slice = try std.fmt.bufPrint(&msg_buf, "{d}: {s}", .{ pfd.fd, recv_buf[0..bytes_sent] });
                    var blacklist = [2]os.fd_t{ pfd.fd, listen_sock };
                    try broadcast_message(msg_buf_slice, &blacklist, pfds);
                }
            }
        }
    }
}
