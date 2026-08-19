export function destinationFor(event) {
    return event.kind === "invoice.created" ? "billing" : "operations";
}
