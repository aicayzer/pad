import {
  DOMSerializer,
  type Fragment,
  type Node,
  type Schema,
} from "@milkdown/kit/prose/model";
import { Plugin, PluginKey } from "@milkdown/kit/prose/state";
import { $prose } from "@milkdown/kit/utils";

export interface ClipboardContent {
  text: string;
  html: string;
}

// Clipboard text is the visible document, not Markdown serialization: escaping
// punctuation or trailing spaces here leaks source syntax into other apps.
export function clipboardText(content: Fragment): string {
  const blocks: string[] = [];
  content.forEach((node) => blocks.push(nodeText(node)));
  const inline = content.firstChild?.isInline ?? false;
  return blocks.join(inline ? "" : "\n\n");
}

function nodeText(node: Node): string {
  if (node.isText) return node.text ?? "";
  if (node.type.name === "hardbreak" || node.type.name === "hard_break")
    return "\n";
  if (node.type.name === "bullet_list" || node.type.name === "ordered_list") {
    const items: string[] = [];
    node.forEach((item, _offset, index) => {
      const marker =
        node.type.name === "ordered_list"
          ? `${Number(node.attrs.order ?? 1) + index}. `
          : "- ";
      const task =
        item.attrs.checked == null ? "" : item.attrs.checked ? "[x] " : "[ ] ";
      const prefix = marker + task;
      const indent = " ".repeat(marker.length);
      const blocks: string[] = [];
      item.forEach((child, _childOffset, childIndex) => {
        const text = nodeText(child);
        const nestedList =
          child.type.name === "bullet_list" ||
          child.type.name === "ordered_list";
        const lines = text.split("\n");
        const indented = lines
          .map((line, lineIndex) =>
            childIndex === 0 && lineIndex === 0 ? prefix + line : indent + line,
          )
          .join("\n");
        // Nested lists follow their parent directly; subsequent paragraphs keep
        // their blank line and every continuation stays inside its list item.
        blocks.push((childIndex > 0 && !nestedList ? "\n" : "") + indented);
      });
      items.push(blocks.length ? blocks.join("\n") : prefix.trimEnd());
    });
    return items.join("\n");
  }
  return clipboardText(node.content);
}

export function clipboardContent(
  content: Fragment,
  schema: Schema,
): ClipboardContent {
  const container = document.createElement("div");
  container.append(DOMSerializer.fromSchema(schema).serializeFragment(content));
  return { text: clipboardText(content), html: container.innerHTML };
}

export const visibleClipboard = $prose(
  () =>
    new Plugin({
      key: new PluginKey("visibleClipboard"),
      props: {
        clipboardTextSerializer: (slice) => clipboardText(slice.content),
      },
    }),
);
