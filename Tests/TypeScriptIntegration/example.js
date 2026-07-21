import { answer, metadata } from "host:answer";

const user = await loadUser(answer);
user?.name.toUpperCase();
metadata.source.toUpperCase();
