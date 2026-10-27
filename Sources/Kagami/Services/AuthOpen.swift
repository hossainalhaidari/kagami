import Darwin
import Foundation

enum AuthOpenError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Administrator authorization was cancelled."
        case .failed(let message): return message
        }
    }
}

/// Opens a device node with administrator rights using `/usr/libexec/authopen`.
///
/// `authopen` shows the system authorization prompt, opens the file as root and
/// hands the open descriptor back over a UNIX socket (`-stdoutpipe`). This is the
/// same approach Raspberry Pi Imager uses on macOS and avoids having to install
/// a privileged helper tool. Blocks until the user responds to the prompt.
enum AuthOpen {
    static func open(_ path: String, flags: Int32 = O_RDWR) throws -> Int32 {
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw AuthOpenError.failed("socketpair failed: \(String(cString: strerror(errno)))")
        }
        let (parentSocket, childSocket) = (sockets[0], sockets[1])
        defer { close(parentSocket) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, childSocket, STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&actions, parentSocket)

        let arguments = ["/usr/libexec/authopen", "-stdoutpipe", "-o", String(flags), path]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, argv[0], &actions, nil, argv, envp)
        // The child owns its copy now; closing ours lets recvmsg see EOF if authopen exits early.
        close(childSocket)
        guard spawnStatus == 0 else {
            throw AuthOpenError.failed("Could not launch authopen: \(String(cString: strerror(spawnStatus)))")
        }

        let fd = receiveDescriptor(from: parentSocket)

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1

        if let fd { return fd }
        // authopen exits with 1 both on cancel and on denied authorization.
        if exitCode == 1 { throw AuthOpenError.cancelled }
        throw AuthOpenError.failed("authopen could not open \(path) (exit code \(exitCode)).")
    }

    /// Reads one SCM_RIGHTS control message and returns the descriptor it carries.
    private static func receiveDescriptor(from socket: Int32) -> Int32? {
        let headerSize = MemoryLayout<cmsghdr>.size
        // CMSG_DATA offset: header size rounded up to 4-byte alignment on Darwin.
        let dataOffset = (headerSize + 3) & ~3
        let controlSize = dataOffset + MemoryLayout<Int32>.size

        var payload = [UInt8](repeating: 0, count: 256)
        let control = UnsafeMutableRawPointer.allocate(byteCount: controlSize, alignment: MemoryLayout<cmsghdr>.alignment)
        defer { control.deallocate() }
        control.initializeMemory(as: UInt8.self, repeating: 0, count: controlSize)

        return payload.withUnsafeMutableBytes { buffer -> Int32? in
            var iov = iovec(iov_base: buffer.baseAddress, iov_len: buffer.count)
            return withUnsafeMutablePointer(to: &iov) { iovPointer -> Int32? in
                var message = msghdr()
                message.msg_iov = iovPointer
                message.msg_iovlen = 1
                message.msg_control = control
                message.msg_controllen = socklen_t(controlSize)

                var received: Int
                repeat { received = recvmsg(socket, &message, 0) } while received == -1 && errno == EINTR
                guard received > 0, message.msg_controllen >= socklen_t(controlSize) else { return nil }

                let header = control.load(as: cmsghdr.self)
                guard header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_RIGHTS else { return nil }
                return control.load(fromByteOffset: dataOffset, as: Int32.self)
            }
        }
    }
}
