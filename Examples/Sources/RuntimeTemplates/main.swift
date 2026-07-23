import QuickJSKit

@main
private struct RuntimeTemplatesExample {
    static func main() async throws {
        let template = try JavaScriptRuntimeTemplate(
            configuration: .restricted
        ) {
            Globals {
                Function("sum") { (left: Int, right: Int) in
                    left + right
                }
            }
            Prepare(JavaScriptProgram("sum(20, 22)"))
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 2
        )
        try await provisioner.warmUp()

        let runtime = try await provisioner.makeRuntime()
        let answer: Int = try await runtime.evaluate("sum(20, 22)")
        print(answer)

        await provisioner.shutdown()
    }
}
