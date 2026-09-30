import { editorViewCtx, serializerCtx } from "@milkdown/kit/core";
import type { Ctx, MilkdownPlugin } from "@milkdown/kit/ctx";
import type { Node as ProseNode } from "@milkdown/kit/prose/model";
import {
  commonmark,
  hardbreakSchema,
  paragraphSchema,
  remarkInlineLinkPlugin,
} from "@milkdown/kit/preset/commonmark";
import {
  extendListItemSchemaForTask,
  strikethroughAttr,
  strikethroughInputRule,
  strikethroughKeymap,
  strikethroughSchema,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
} from "@milkdown/kit/preset/gfm";
import { $remark } from "@milkdown/kit/utils";
import { autolinkInputRule } from "./autolink";
import { literalBlock, preserveLiterals } from "./literals";
import type { Link, Parents, PhrasingContent } from "mdast";
import {
  defaultHandlers,
  type Options as StringifyOptions,
} from "mdast-util-to-markdown";
import {
  gfmAutolinkLiteralFromMarkdown,
  gfmAutolinkLiteralToMarkdown,
} from "mdast-util-gfm-autolink-literal";
import {
  gfmStrikethroughFromMarkdown,
  gfmStrikethroughToMarkdown,
} from "mdast-util-gfm-strikethrough";
import {
  gfmTaskListItemFromMarkdown,
  gfmTaskListItemToMarkdown,
} from "mdast-util-gfm-task-list-item";
import { gfmAutolinkLiteral } from "micromark-extension-gfm-autolink-literal";
import { gfmStrikethrough } from "micromark-extension-gfm-strikethrough";
import { gfmTaskListItem } from "micromark-extension-gfm-task-list-item";
import type { Processor } from "unified";

const bareURL = /^https?:\/\/[^\s<>]+$/;
// The literal form stops at these, so a URL ending in one would come back shorter than it went out.
const endsInPunctuation = /[.,;:!?]$/;
// What may sit against a bare URL without the reader running the two together.
const beforeURL = /(^|[\s([*_~])$/;
const afterURL = /^([\s.,;:!?)\]}<]|$)/;

function balanced(url: string): boolean {
  let open = 0;
  for (const character of url) {
    if (character === "(") open += 1;
    else if (character === ")") open -= 1;
    if (open < 0) return false;
  }
  return open === 0;
}

function textAt(
  parent: Parents | undefined,
  node: Link,
  offset: number,
): PhrasingContent | undefined {
  const children = parent?.children as PhrasingContent[] | undefined;
  const index = children?.indexOf(node as PhrasingContent) ?? -1;
  return index < 0 ? undefined : children?.[index + offset];
}

/** A link whose text is its own URL is written as the bare URL, the way it was typed. Only where reading
 *  it back gives the same link again: nothing may run into it at either end. */
function writesBare(node: Link, parent: Parents | undefined): boolean {
  const [child, ...rest] = node.children;
  if (
    node.title ||
    rest.length > 0 ||
    child?.type !== "text" ||
    child.value !== node.url
  )
    return false;
  if (
    !bareURL.test(node.url) ||
    endsInPunctuation.test(node.url) ||
    !balanced(node.url)
  )
    return false;
  const before = textAt(parent, node, -1);
  if (before && (before.type !== "text" || !beforeURL.test(before.value)))
    return false;
  const after = textAt(parent, node, 1);
  if (after && (after.type !== "text" || !afterURL.test(after.value)))
    return false;
  return true;
}

const link: (typeof defaultHandlers)["link"] = (node, parent, state, info) =>
  writesBare(node, parent)
    ? node.url
    : defaultHandlers.link(node, parent, state, info);
link.peek = (node, parent, state) =>
  writesBare(node, parent)
    ? node.url[0]!
    : defaultHandlers.link.peek(node, parent, state);

// Tables and footnotes are deliberately left out.
function remarkDialect(this: Processor) {
  const data = this.data() as Record<string, unknown[] | undefined>;
  const add = (key: string, value: unknown) => {
    const list = (data[key] ??= []);
    list.push(value);
  };
  add("micromarkExtensions", gfmStrikethrough());
  add("micromarkExtensions", gfmTaskListItem());
  add("micromarkExtensions", gfmAutolinkLiteral());
  add("fromMarkdownExtensions", gfmStrikethroughFromMarkdown());
  add("fromMarkdownExtensions", gfmTaskListItemFromMarkdown());
  add("fromMarkdownExtensions", gfmAutolinkLiteralFromMarkdown());
  add("toMarkdownExtensions", gfmStrikethroughToMarkdown());
  add("toMarkdownExtensions", gfmTaskListItemToMarkdown());
  add("toMarkdownExtensions", gfmAutolinkLiteralToMarkdown());
  add("toMarkdownExtensions", { handlers: { link } });
}

export const remarkDialectPlugin = $remark(
  "remarkDialect",
  () => remarkDialect,
);

// Keep authored spacer paragraphs; references remain literal instead of becoming inline links.
const commonmarkWithLiteralReferences = commonmark.filter(
  (plugin) => !remarkInlineLinkPlugin.includes(plugin),
);

// The preset drops the final empty paragraph, which makes trailing spacers shrink on each reload.
const preserveSpacerParagraphs = paragraphSchema.extendSchema(
  (base) => (ctx) => {
    const schema = base(ctx);
    return {
      ...schema,
      toMarkdown: {
        ...schema.toMarkdown,
        runner(state, node) {
          if (node.content.size > 0)
            return schema.toMarkdown.runner(state, node);
          state.openNode("paragraph");
          state.addNode("html", undefined, "<br />");
          state.closeNode();
        },
      },
    };
  },
);

// Soft Markdown breaks still serialize as a single newline. Display the actual
// line boundary rather than a space, so changing editor mode never joins lines.
const visibleSoftbreaks = hardbreakSchema.extendSchema((base) => (ctx) => {
  const schema = base(ctx);
  return {
    ...schema,
    parseDOM: [
      {
        tag: 'br[data-type="softbreak"]',
        getAttrs: () => ({ isInline: true }),
      },
      ...(schema.parseDOM ?? []),
    ],
    toDOM: (node) =>
      node.attrs.isInline
        ? ["br", { "data-type": "softbreak" }]
        : schema.toDOM!(node),
  };
});

export const dialect: MilkdownPlugin[] = [
  // Protect unsupported inline HTML before the empty-line plugin consumes break nodes.
  preserveLiterals,
  commonmarkWithLiteralReferences,
  preserveSpacerParagraphs,
  visibleSoftbreaks,
  autolinkInputRule,
  extendListItemSchemaForTask,
  strikethroughAttr,
  strikethroughSchema,
  strikethroughInputRule,
  strikethroughKeymap,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
  remarkDialectPlugin,
  literalBlock,
].flat();

// One output form, so a document written back unchanged is byte-stable.
export const stringifyOptions: StringifyOptions = {
  bullet: "-",
  emphasis: "*",
  strong: "*",
  fences: true,
  listItemIndent: "one",
  rule: "-",
};

// Milkdown preserves authored spacer paragraphs with standalone Markdown HTML breaks.
export function serialize(
  ctx: Ctx,
  doc: ProseNode = ctx.get(editorViewCtx).state.doc,
): string {
  if (
    doc.childCount === 1 &&
    doc.firstChild?.type.name === "paragraph" &&
    doc.firstChild.content.size === 0
  )
    return "";
  return ctx.get(serializerCtx)(doc);
}
