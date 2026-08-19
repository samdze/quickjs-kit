import QuickJSKit
import QuickJSKitMacros
import Testing

@Suite("Tutorial macro workflows")
struct ProgressiveTutorialMacroExamplesTests {
    @JavaScriptExport
    struct ProjectLead: Codable, Sendable {
        let id: String
        let name: String
    }

    @JavaScriptExport
    struct DeliveryDecision: Codable, Sendable, Equatable {
        let destination: String
        let label: String
    }

    struct WebhookEvent: Codable, Sendable {
        let tenant: String
        let kind: String
    }

    @JavaScriptExport
    actor DeliveryAudit {
        func record(_ decision: DeliveryDecision) -> String {
            "Recorded \(decision.destination)"
        }
    }

    @Test("the workspace SDK type appears in generated declarations")
    func macroTypeAppearsInModuleDeclarations() throws {
        let template = try JavaScriptRuntimeTemplate {
            SwiftModule("host:workspace") {
                JavaScriptType(ProjectLead.self)
                Function("exampleLead") {
                    ProjectLead(
                        id: "ava",
                        name: "Ava"
                    )
                }
            }
        }

        let declarations = try template.environmentDescription()
            .typeScriptDeclarations()
        #expect(declarations.contains("ProjectLead"))
        #expect(declarations.contains("host:workspace"))
        #expect(declarations.contains("exampleLead"))
    }

    @Test("a template automatically publishes a macro-exported audit actor")
    func macroActorPublishesFromRuntimeInstance() async throws {
        enum RuleError: Error { case unknownSpecifier }
        let ruleSources = ["rules:acme": "export function destinationFor(event) { return event.kind === 'invoice.created' ? 'billing' : 'operations'; }"]
        let loader = JavaScriptModuleLoader(
            resolve: { request in
                if request.specifier == "app:webhook-workflow" {
                    return request.specifier
                }
                guard ruleSources[request.specifier] != nil else {
                    throw RuleError.unknownSpecifier
                }
                return request.specifier
            },
            load: { request in
                guard let source = ruleSources[request.specifier] else {
                    throw RuleError.unknownSpecifier
                }
                return JavaScriptModuleSource(source: source, sourceURL: request.specifier)
            }
        )
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { DeliveryAudit() }) {
                RuntimeObject(as: "audit")
            }
            ModuleLoader(loader)
            SourceModule(
                """
                export async function decide(event) {
                    const { destinationFor } = await import("rules:acme");
                    const decision = {
                        destination: destinationFor(event),
                        label: `${event.tenant}:${event.kind}`
                    };
                    await audit.record(decision);
                    return decision;
                }
                """,
                as: "app:webhook-workflow",
                declarations: .init(
                    "export function decide(event: { tenant: string; kind: string }): Promise<{ destination: string; label: string }>;"
                )
            )
        }
        let runtime = try await template.makeRuntime()

        _ = try await runtime.importModule("rules:acme")
        let workflow = try await runtime.importModule("app:webhook-workflow")
        let decide = try await workflow.function(forExport: "decide")
        let result: DeliveryDecision = try await decide.call(
            WebhookEvent(tenant: "acme", kind: "invoice.created")
        )
        let declarations = try template.environmentDescription()
            .typeScriptDeclarations()

        #expect(result == DeliveryDecision(
            destination: "billing",
            label: "acme:invoice.created"
        ))
        #expect(declarations.contains("record"))
    }
}
