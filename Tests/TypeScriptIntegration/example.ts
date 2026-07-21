import { answer } from "host:answer";

const user = await loadUser(answer);
if (user) {
    user.id satisfies number;
    user.name satisfies string;
}
