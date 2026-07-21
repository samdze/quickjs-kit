import { answer } from "host:answer";

const user = await loadUser(answer);
user.name.toUpperCase();
