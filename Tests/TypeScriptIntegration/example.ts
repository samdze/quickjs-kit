import { answer, metadata, type AnswerMetadata } from "host:answer";
import { User, UserService, UserStatus } from "host:users";

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

const runtimeUser = new User({ id: 42, name: "Ada" });
const userService = new UserService();
await userService.save(runtimeUser, UserStatus.active);
