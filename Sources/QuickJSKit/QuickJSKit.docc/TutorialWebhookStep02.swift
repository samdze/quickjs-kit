let workflowSource = """
    export function decide(event) {
        return {
            destination: "operations",
            label: `${event.tenant}:${event.kind}`
        };
    }
    """
