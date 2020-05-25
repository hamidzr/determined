import { getNodeChildren, isLeafNode, isTreeNode,
  traverseTree, TreeNode, TreePath } from 'AsyncTree';
import root from 'omnibar/sampleTree';

const SEPARATOR = ' ';

interface TreeRequest {
  query: string;
  path: TreePath;
}

const parseInput = async (input: string): Promise<TreeRequest> => {
  const sections = input.split(SEPARATOR);
  const query = sections[sections.length-1];
  const address = sections.slice(0,sections.length-1);
  const path = await traverseTree(address, root);
  return {
    path,
    query,
  };
};

const absPathToAddress = (path: TreePath): string[] =>  (path.map(tn => tn.title).slice(1));

const query = async (input: string): Promise<TreeNode[]> => {
  const { path, query } = await parseInput(input);
  const node = path[path.length-1];
  if (isLeafNode(node)) {
    // this is after the leafnode onaction triggers
    // or trigger it directly?
    // could do an execute confirmation?
    return [];
  }
  const children = await getNodeChildren(node);

  const matches = children.filter(it => it.title.match(new RegExp(query, 'i')));
  return matches;
};

export const ext = async(input: string): Promise<TreeNode[]> => {
  try {
    return await query(input);
  } catch (e) {
    console.error(e);
    // omnibar eatsup the exceptions
    // throw e;
    return [];
  }
};

const onTreeNodeAction = async (node: TreeNode): Promise<void> => {
  if (isLeafNode(node)) return node.onAction(node);
  // await getNodeChildren(node);
  // TODO setup the omnibar with context and tree
};

export const onAction = async <T>(item: T): Promise<void> => {
  if (!!item && isTreeNode(item)) {
    const input: HTMLInputElement|null = document.querySelector('#omnibar input[type="text"]');
    if (input) {
      // TODO should be replaced, perhaps, with a update to the omnibar package's command decorator
      const { path } = await parseInput(input.value);
      input.value = (path.length > 1 ?  absPathToAddress(path).join(SEPARATOR) + SEPARATOR  : '')
        + item.title;
      // trigger the onchange
      input.onchange && input.onchange(undefined as unknown as Event);
    }
    return onTreeNodeAction(item);
  }
  // else meh
  return Promise.resolve();
};
