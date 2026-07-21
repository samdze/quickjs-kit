import { answer, metadata, type AnswerMetadata } from "host:answer";

declare const configuration: HostConfiguration;
declare const session: Example.Models.Session;

const user = await loadUser(answer);
const typedMetadata: AnswerMetadata = metadata;
if (user) {
    user.id satisfies number;
    user.name satisfies string;
}
configuration.environment satisfies string;
session.token satisfies string;
typedMetadata.source satisfies string;
