import Foundation

/// The v1 production scanner: shells out to the system `lsof` and parses its
/// machine-readable `-F` output.
///
/// Security/distribution tradeoff, documented in the README: spawning `lsof`
/// and signalling arbitrary processes is incompatible with the App Sandbox,
/// so this app targets Developer ID distribution. If sandboxing is ever
/// required, replace this type with a `libproc`-based `PortScanning`
/// implementation — nothing above this layer knows `lsof` exists.
actor LsofPortScanner: PortScanning {
    /// Fixed system path — deliberately not user-configurable so the app can
    /// never be steered into executing an arbitrary binary.
    private static let lsofPath = "/usr/sbin/lsof"

    func scan() async throws -> [ListeningPort] {
        guard FileManager.default.isExecutableFile(atPath: Self.lsofPath) else {
            throw PortScanError(message: "lsof was not found at \(Self.lsofPath).")
        }

        // -n/-P skip DNS and port-name lookups (fast, stable output),
        // -w suppresses warnings, -F selects field output:
        // p=pid, c=command, u=uid, L=login name, P=protocol, n=address.
        async let tcpOutput = Self.runLsof(["-nPw", "-iTCP", "-sTCP:LISTEN", "-FpcuLPn"])
        async let udpOutput = Self.runLsof(["-nPw", "-iUDP", "-FpcuLPn"])
        let (tcp, udp) = try await (tcpOutput, udpOutput)

        let records = LsofParser.records(from: tcp) + LsofParser.records(from: udp)
        var ports = LsofParser.listeningPorts(from: records)

        // Enrich with executable path, start time, argv, and working
        // directory via libproc/sysctl (cheap kernel queries, no subprocess
        // spawns). Cache per pid within a scan — one process usually owns
        // several sockets.
        var pathByPid: [Int32: String?] = [:]
        var startByPid: [Int32: Date?] = [:]
        var argsByPid: [Int32: [String]?] = [:]
        var cwdByPid: [Int32: String?] = [:]
        var toolByPid: [Int32: InferredTool?] = [:]
        for index in ports.indices {
            let pid = ports[index].pid
            if pathByPid[pid] == nil {
                pathByPid[pid] = ProcessInfoProvider.executablePath(pid: pid)
                startByPid[pid] = ProcessInfoProvider.startDate(pid: pid)
                argsByPid[pid] = ProcessInfoProvider.arguments(pid: pid)
                cwdByPid[pid] = ProcessInfoProvider.workingDirectory(pid: pid)
                // Inference runs here — once per process per scan — rather
                // than in row renders, which must stay allocation-free for
                // smooth scrolling.
                toolByPid[pid] = DevToolInference.infer(processName: ports[index].processName,
                                                        arguments: argsByPid[pid] ?? nil)
            }
            ports[index].executablePath = pathByPid[pid] ?? nil
            ports[index].processStartDate = startByPid[pid] ?? nil
            ports[index].arguments = argsByPid[pid] ?? nil
            ports[index].workingDirectory = cwdByPid[pid] ?? nil
            ports[index].inferredTool = toolByPid[pid] ?? nil
        }
        return ports
    }

    /// Runs lsof and returns its stdout. A dedicated thread reads stdout to
    /// EOF while the process runs, so a full pipe buffer can never deadlock
    /// the scan no matter how many sockets are open.
    private static func runLsof(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: PortScanError(
                        message: "Failed to launch lsof: \(error.localizedDescription)"))
                    return
                }

                // Drain stderr concurrently so it can't block lsof either.
                var errorData = Data()
                let stderrDone = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    stderrDone.signal()
                }

                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stderrDone.wait()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                // lsof exits 1 for "nothing matched", which is a valid empty
                // result — only treat it as failure when we also got no output.
                if process.terminationStatus > 1, output.isEmpty {
                    let detail = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: PortScanError(
                        message: "lsof exited with status \(process.terminationStatus)."
                            + (detail.isEmpty ? "" : " \(detail)")))
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }
}
