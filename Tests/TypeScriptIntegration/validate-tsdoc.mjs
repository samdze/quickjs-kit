import { readFile } from "node:fs/promises";
import { TSDocParser } from "@microsoft/tsdoc";

const declarationPath = new URL("./quickjskit.generated.d.ts", import.meta.url);
const source = await readFile(declarationPath, "utf8");
const comments = source.match(/\/\*\*[\s\S]*?\*\//g) ?? [];

if (comments.length === 0) {
    throw new Error("The integration declaration contains no TSDoc comments.");
}

const parser = new TSDocParser();
const diagnostics = [];
for (const comment of comments) {
    const context = parser.parseString(comment);
    for (const message of context.log.messages) {
        diagnostics.push(`${message.messageId}: ${message.text}`);
    }
}

if (diagnostics.length > 0) {
    throw new Error(`Invalid generated TSDoc:\n${diagnostics.join("\n")}`);
}

for (const tag of [
    "@remarks",
    "@param",
    "@returns",
    "@throws",
    "@example",
    "@see",
    "@deprecated",
    "@defaultValue",
]) {
    if (!source.includes(tag)) {
        throw new Error(`The integration declaration does not exercise ${tag}.`);
    }
}
