import { answer } from "host:answer";

const user = await loadUser(answer);
user.id satisfies number;
user.name satisfies string;
