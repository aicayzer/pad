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
      items.push(marker + task + clipboardText(item.content));
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
