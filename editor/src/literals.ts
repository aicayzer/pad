import { $node, $remark } from "@milkdown/kit/utils";
import type { Root, RootContent, Literal, Nodes } from "mdast";

interface PadLiteral extends Literal {
  type: "padLiteral";
}
declare module "mdast" {
  interface RootContentMap {
    padLiteral: PadLiteral;
  }
}

const unsupported = new Set([
  "html",
  "image",
  "imageReference",
  "definition",
  "linkReference",
]);
function containsUnsupported(node: Nodes): boolean {
  return (
    unsupported.has(node.type) ||
    ("children" in node && node.children.some(containsUnsupported))
  );
}

// Keep syntax we cannot faithfully edit as literal text, without making the rest
// of the document a source editor or allowing HTML and image network requests.
export const preserveLiterals = $remark(
  "preserveLiterals",
  () => () => (tree: Root, file: { value: unknown }) => {
    const source = String(file.value);
    const frontmatter =
      /^(?:---|\+\+\+)\r?\n[\s\S]*?\r?\n(?:---|\+\+\+)(?:\r?\n|$)/.exec(source);
    const frontmatterEnd = frontmatter?.[0].length ?? 0;
    const blocks: RootContent[] = [];
    if (frontmatter)
      blocks.push({ type: "padLiteral", value: frontmatter[0].trimEnd() });
    for (const node of tree.children) {
      const start = node.position?.start.offset;
      const end = node.position?.end.offset;
      if (start == null || end == null) {
        blocks.push(node);
        continue;
      }
      if (start < frontmatterEnd) continue;
      const raw = source.slice(start, end);
      const table = /^\s*\|?.*\|.*\r?\n\s*\|?\s*:?-{3,}/m.test(raw);
      const footnote = /\[\^[^\]]+\]/.test(raw);
      if (containsUnsupported(node) || table || footnote)
        blocks.push({ type: "padLiteral", value: raw });
      else blocks.push(node);
    }
    tree.children = blocks;
  },
);

export const literalBlock = $node("literal_markdown", () => ({
  group: "block",
  content: "text*",
  marks: "",
  code: true,
  defining: true,
  parseDOM: [{ tag: "pre.literal-markdown", preserveWhitespace: "full" }],
  toDOM: () => [
    "pre",
    { class: "literal-markdown", "aria-label": "Preserved Markdown" },
    0,
  ],
  parseMarkdown: {
    match: (node) => node.type === "padLiteral",
    runner: (state, node, type) => {
      state.openNode(type);
      state.addText(String(node.value ?? ""));
      state.closeNode();
    },
  },
  toMarkdown: {
    match: (node) => node.type.name === "literal_markdown",
    runner: (state, node) => {
      state.addNode("html", undefined, node.textContent);
    },
  },
}));
