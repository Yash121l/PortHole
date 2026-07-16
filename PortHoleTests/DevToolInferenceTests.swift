import XCTest
@testable import PortHole

final class DevToolInferenceTests: XCTestCase {
    // Captured from a real machine: vite dev server on a custom port (8787),
    // where the process name alone ("node") says nothing.
    func testViteViaNodeModulesBinPath() {
        let tool = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "/Users/admin/code/almanac/node_modules/.bin/vite", "dev"])
        XCTAssertEqual(tool?.label, "Vite")
    }

    func testViteViaWrappedScriptPath() {
        let tool = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "/x/node_modules/vite/bin/vite.js"])
        XCTAssertEqual(tool?.label, "Vite")
    }

    func testNextDevBeatsBareNext() {
        let dev = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "/x/node_modules/.bin/next", "dev", "--turbopack"])
        XCTAssertEqual(dev?.label, "Next.js dev")

        let start = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "/x/node_modules/.bin/next", "start"])
        XCTAssertEqual(start?.label, "Next.js")
    }

    // Next.js dev retitles its process ("next-server (v16.2.10)"), so the
    // name alone is enough even when argv is unavailable.
    func testNextServerProcessTitle() {
        let tool = DevToolInference.infer(processName: "next-server (v16.2.10)", arguments: nil)
        XCTAssertEqual(tool?.label, "Next.js dev")
    }

    func testWranglerDev() {
        let tool = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "/x/node_modules/.bin/wrangler", "dev"])
        XCTAssertEqual(tool?.label, "Wrangler dev")
    }

    func testPythonServers() {
        XCTAssertEqual(DevToolInference.infer(
            processName: "python3.12",
            arguments: ["python", "manage.py", "runserver", "0.0.0.0:8000"])?.label, "Django dev")
        XCTAssertEqual(DevToolInference.infer(
            processName: "python3.12",
            arguments: ["/opt/homebrew/bin/uvicorn", "app:app", "--reload"])?.label, "Uvicorn")
        XCTAssertEqual(DevToolInference.infer(
            processName: "python3.12",
            arguments: ["python3", "-m", "http.server", "8080"])?.label, "http.server")
    }

    func testRailsAndLaravel() {
        XCTAssertEqual(DevToolInference.infer(
            processName: "ruby",
            arguments: ["ruby", "bin/rails", "server"])?.label, "Rails dev")
        XCTAssertEqual(DevToolInference.infer(
            processName: "php",
            arguments: ["php", "artisan", "serve"])?.label, "Laravel dev")
    }

    func testPlainNodeScriptStaysUnlabeled() {
        XCTAssertNil(DevToolInference.infer(
            processName: "node",
            arguments: ["node", "server.js"]))
        XCTAssertNil(DevToolInference.infer(processName: "node", arguments: nil))
    }

    func testSubcommandMustFollowTheBinary() {
        // "dev" appearing *before* wrangler shouldn't satisfy "wrangler dev".
        let tool = DevToolInference.infer(
            processName: "node",
            arguments: ["node", "dev", "/x/.bin/wrangler"])
        XCTAssertEqual(tool?.label, "Wrangler") // falls back to the bare signature
    }
}

final class ListeningPortDerivedFieldsTests: XCTestCase {
    private func port(arguments: [String]? = nil, cwd: String? = nil) -> ListeningPort {
        ListeningPort(port: 8787, networkProtocol: .tcp, bindAddress: "::1",
                      pid: 42, processName: "node", executablePath: nil,
                      user: nil, processStartDate: nil,
                      arguments: arguments, workingDirectory: cwd)
    }

    func testCommandLineJoinsArgv() {
        XCTAssertEqual(port(arguments: ["node", "x.js", "--port", "8787"]).commandLine,
                       "node x.js --port 8787")
        XCTAssertNil(port().commandLine)
    }

    func testProjectNameFromWorkingDirectory() {
        XCTAssertEqual(port(cwd: "/Users/admin/code/almanac").projectName, "almanac")
        XCTAssertNil(port(cwd: "/").projectName, "root cwd is noise, not identity")
        XCTAssertNil(port(cwd: NSHomeDirectory()).projectName, "home cwd is noise, not identity")
        XCTAssertNil(port().projectName)
    }
}
