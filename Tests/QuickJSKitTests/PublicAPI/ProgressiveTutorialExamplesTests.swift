import QuickJSKit
import Testing

@Suite("Progressive tutorial workflows")
struct ProgressiveTutorialExamplesTests {
    struct MeetingNote: Codable, Sendable {
        let project: String
        let title: String
        let actionItems: [String]
    }

    struct ProjectLead: Codable, Sendable {
        let id: String
        let name: String
    }

    struct FollowUpTask: Codable, Sendable, Equatable { let title: String }

    struct FollowUpPlan: Codable, Sendable, Equatable {
        let title: String
        let ownerID: String?
        let tasks: [FollowUpTask]
    }

    struct WebhookEvent: Codable, Sendable {
        let tenant: String
        let kind: String
    }

    struct DeliveryDecision: Codable, Sendable, Equatable {
        let destination: String
        let label: String
    }

    actor ProjectDirectory {
        func projectLead(for project: String) -> ProjectLead? {
            project == "Mobile" ? ProjectLead(id: "ava", name: "Ava") : nil
        }
    }

    func note(project: String = "Mobile") -> MeetingNote {
        MeetingNote(
            project: project,
            title: "Ship the new editor",
            actionItems: ["Confirm the rollout", "Write release notes"]
        )
    }

    @Test("a direct evaluation decodes a follow-up plan")
    func directEvaluationDecodesPlan() async throws {
        let runtime = try JavaScriptRuntime()
        let plan: FollowUpPlan = try await runtime.evaluate(
            """
            ({
                title: "Follow up: Team sync",
                ownerID: null,
                tasks: [{ title: "Send the summary" }]
            })
            """
        )

        #expect(plan == FollowUpPlan(
            title: "Follow up: Team sync",
            ownerID: nil,
            tasks: [FollowUpTask(title: "Send the summary")]
        ))
    }

    @Test("a recipe returns a detached follow-up plan")
    func recipeReturnsTypedPlan() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule(
            """
            export function plan(note) {
                return { title: `Follow up: ${note.title}`, ownerID: null,
                    tasks: note.actionItems.map(title => ({ title })) };
            }
            """,
            as: "app:follow-up",
            sourceURL: "Scripts/follow-up.js"
        )
        let module = try await runtime.importModule("app:follow-up")
        let makePlan = try await module.function(forExport: "plan")
        let plan: FollowUpPlan = try await makePlan.call(note())
        #expect(plan == FollowUpPlan(
            title: "Follow up: Ship the new editor",
            ownerID: nil,
            tasks: [
                FollowUpTask(title: "Confirm the rollout"),
                FollowUpTask(title: "Write release notes")
            ]
        ))
    }

    @Test("a recipe awaits project context and leaves unknown projects unassigned")
    func recipeUsesPromiseBackedProjectContext() async throws {
        let runtime = try JavaScriptRuntime()
        let directory = ProjectDirectory()
        try await runtime.function("projectLead", options: .init(parameterNames: ["project"])) {
            (project: String) async -> ProjectLead? in
            await directory.projectLead(for: project)
        }
        try await runtime.registerModule(
            """
            export async function plan(note) {
                const lead = await projectLead(note.project);
                return { title: `Follow up: ${note.title}`, ownerID: lead?.id ?? null,
                    tasks: note.actionItems.map(title => ({ title })) };
            }
            """,
            as: "app:follow-up",
            sourceURL: "Scripts/follow-up.js"
        )
        let module = try await runtime.importModule("app:follow-up")
        let makePlan = try await module.function(forExport: "plan")
        let assigned: FollowUpPlan = try await makePlan.call(note())
        let unassigned: FollowUpPlan = try await makePlan.call(note(project: "Unknown"))
        #expect(assigned.ownerID == "ava")
        #expect(unassigned.ownerID == nil)
    }

    @Test("the workspace module and recipe appear in generated tooling")
    func workspaceModuleAndRecipeAppearInTooling() async throws {
        let runtime = try JavaScriptRuntime()
        let directory = ProjectDirectory()
        try await runtime.defineModule("host:workspace") { module in
            module.function("projectLead", options: .init(parameterNames: ["project"])) {
                (project: String) async -> String? in
                await directory.projectLead(for: project)?.id
            }
        }
        try await runtime.registerModule(
            """
            import { projectLead } from "host:workspace";
            export async function plan(note) { return { ownerID: await projectLead(note.project) }; }
            """,
            as: "app:follow-up",
            sourceURL: "Scripts/follow-up.js",
            typeScriptDeclarations: .init(
                "export function plan(note: unknown): Promise<{ ownerID: string | null }>;"
            )
        )
        let declarations = try await runtime.environmentDescription().typeScriptDeclarations()
        let workspace = try await runtime.environmentDescription().typeScriptWorkspace(
            options: .init(sourceGlobs: ["Scripts/**/*.js"])
        )
        #expect(declarations.contains("host:workspace"))
        #expect(declarations.contains("app:follow-up"))
        #expect(workspace.files.contains { $0.path == "quickjskit.generated.d.ts" })
    }

    @Test("a template creates a webhook workflow with local audit state")
    func templateCreatesWebhookWorkflowWithLocalAuditState() async throws {
        actor DeliveryAudit {
            func record(_ decision: DeliveryDecision) -> String { "Recorded \(decision.destination)" }
        }
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { DeliveryAudit() }) {
                RuntimeObject(as: "audit") {
                    InstanceFunction("record") { (audit: DeliveryAudit, decision: DeliveryDecision) async -> String in
                        await audit.record(decision)
                    }
                }
            }
            SourceModule(
                """
                export async function decide(event) {
                    const decision = { destination: "operations", label: `${event.tenant}:${event.kind}` };
                    await audit.record(decision); return decision;
                }
                """,
                as: "app:webhook-workflow",
                sourceURL: "Scripts/webhook-workflow.js"
            )
        }
        let runtime = try await template.makeRuntime()
        let workflow = try await runtime.importModule("app:webhook-workflow")
        let decide = try await workflow.function(forExport: "decide")
        let decision: DeliveryDecision = try await decide.call(
            WebhookEvent(tenant: "acme", kind: "invoice.created")
        )
        #expect(decision == DeliveryDecision(destination: "operations", label: "acme:invoice.created"))
    }

    @Test("the tenant loader exposes only allowlisted rules")
    func tenantLoaderExposesOnlyAllowlistedRules() async throws {
        enum RuleError: Error { case unknownRule }
        let sources = ["rules:acme": """
            export function destinationFor(event) {
                return event.kind === "invoice.created" ? "billing" : "operations";
            }
            """]
        let loader = JavaScriptModuleLoader(
            resolve: { request in
                guard sources[request.specifier] != nil else { throw RuleError.unknownRule }
                return request.specifier
            },
            load: { request in
                guard let source = sources[request.specifier] else { throw RuleError.unknownRule }
                return JavaScriptModuleSource(source: source, sourceURL: "Rules/acme.js")
            }
        )
        let runtime = try await JavaScriptRuntimeTemplate { ModuleLoader(loader) }.makeRuntime()
        let destination: String = try await runtime.evaluateModule("""
            import { destinationFor } from "rules:acme";
            export const value = destinationFor({ kind: "invoice.created" });
            """).value(forExport: "value")
        #expect(destination == "billing")
        do {
            _ = try await runtime.evaluateModule("import 'rules:unknown';")
            Issue.record("Expected an unknown tenant rule to fail.")
        } catch is JavaScriptError {}
    }

    @Test("controlled templates support limits provisioning and tooling")
    func controlledTemplatesSupportLimitsProvisioningAndTooling() async throws {
        let looping = JavaScriptProgram("while (true) {}")
        let controlled = try JavaScriptRuntimeTemplate(configuration: .restricted) { Prepare(looping) }
        let runtime = try await controlled.makeRuntime()
        await #expect(throws: JavaScriptError.self) {
            let _: Int = try await runtime.evaluate(looping, options: .init(timeout: .after(.milliseconds(1))))
        }

        let template = try JavaScriptRuntimeTemplate {
            SourceModule(
                "export const workflowName = 'webhook-workflow';",
                as: "app:webhook-workflow",
                declarations: .init("export const workflowName: string;")
            )
        }
        let provisioner = try JavaScriptRuntimeProvisioner(template: template, warmCapacity: 1)
        try await provisioner.warmUp()
        let provisioned = try await provisioner.makeRuntime()
        let name: String = try await provisioned.importModule("app:webhook-workflow")
            .value(forExport: "workflowName")
        #expect(name == "webhook-workflow")
        await provisioner.shutdown()

        let workspace = try template.environmentDescription().typeScriptWorkspace(
            options: .init(sourceGlobs: ["Scripts/**/*.js", "Rules/**/*.js"])
        )
        #expect(workspace.files.contains { $0.path == "quickjskit.generated.d.ts" })
    }
}
