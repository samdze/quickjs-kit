import { projectLead } from "host:workspace";

export async function plan(note) {
    const lead = await projectLead(note.project);

    return {
        title: `Follow up: ${note.title}`,
        ownerID: lead?.id ?? null,
        tasks: note.actionItems.map(title => ({ title }))
    };
}
