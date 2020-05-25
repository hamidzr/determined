import { toNullable } from 'fp-ts/lib/Option';

import { getExperiments, killExperiment } from 'services/api';
import { isAsyncFunction } from 'utils/data';

// interface ResultItem {
//   title: string; // to utilize the default renderer
//   onAction?: Action<ResultItem>;
// }

const SEPARATOR = ' ';

interface BaseNodeProps {
  title: string; // should work with the separator. no space?
}

interface TreeRequest {
  query: string;
  path: TreePath;
}

type TreePath = TreeNode[]
type TreeNode = LeafNode | NLNode;
type TreeGenerator = (arg?: NLNode) => TreeNode[] | Promise<TreeNode[]>

interface LeafNode extends BaseNodeProps {
  onAction: (arg: LeafNode) => void; // with potential response. could be shown
}

interface NLNode extends BaseNodeProps {
  options: TreeNode[] | TreeGenerator; // leaf nodes have no children
}

const isLeafNode = (node: any): node is LeafNode =>
  node.onAction !== undefined && node.options === undefined;
const isNLNode = (node: any): node is NLNode =>
  node.onAction === undefined && node.options !== undefined;
const isTreeNode = (node: any): node is TreeNode =>
  node.title !== undefined && (isLeafNode(node) || isNLNode(node));

const getNodeChildren = async (node: NLNode): Promise<TreeNode[]> => {
  let children: TreeNode[] = [];
  if (typeof node.options === 'function') {
    if (isAsyncFunction(node.options)) {
      children = await node.options(node);
    } else {
      children = node.options(node) as TreeNode[];
    }
  } else {
    children = node.options;
  }
  return children;
};

const root: NLNode  = {
  options: [
    {
      title: 'showTime',
      onAction: () => alert(new Date()),
    },
    {
      title: 'killExperiments',
      options: async () => {
        const exps = await getExperiments({});
        const options: LeafNode[] = exps.map(exp => (
          {
            title: `${exp.id}`,
            onAction: () => killExperiment({ experimentId: exp.id }),
          })); // is use of `this` discouraged?
        return options;
      },
    },
    {
      title: 'manageCluster',
      options: [
        {
          onAction: () => alert('restarted master'),
          title: 'restart',
        },
        {
          onAction: () => alert('reloaded master'),
          title: 'reload',
        },
        {
          onAction: () => alert('here are the logs..'),
          title: 'showlogs',
        },
      ],
    },
  ],
  title: 'root',
};

// traverses a tree to find subtrees.
// path has to end in a NLNode
const traverseTree = async (address: string[], startNode: NLNode): Promise<TreePath> => {
  let curNode: TreeNode = startNode;
  const path: TreePath = [ curNode ];
  let i = 0;
  while(isNLNode(curNode) && i<address.length) {
    const children: TreeNode[] = await getNodeChildren(curNode);
    const rv = children.find(n => n.title === address[i]);
    if (rv === undefined) break;
    curNode = rv;
    i++;
    path.push(curNode);
  }
  if (i < address.length) throw new Error('bad path');
  return path;
};

const parseInput = async (input: string): Promise<TreeRequest> => {
  const sections = input.trim().split(SEPARATOR);
  const query = sections[sections.length-1];
  const address = sections.slice(0,length-2);
  const path = await traverseTree(address, root);
  return {
    path,
    query,
  };
};

const absPathToAddress = (path: TreePath): string[] =>  (path.map(tn => tn.title).slice(1));

export const ext = async (input: string): Promise<TreeNode[]> => {
  const { path, query } = await parseInput(input);
  const node = path[path.length-1];
  if (isLeafNode(node)) {
    // this is after the leafnode onaction triggers
    // or trigger it directly?
    return [];
  }
  const children = await getNodeChildren(node);

  const matches = children.filter(it => it.title.match(new RegExp(query, 'i')));
  return matches;
};

const onTreeNodeAction = async (node: TreeNode): Promise<void> => {
  if (isLeafNode(node)) return node.onAction(node);
  await getNodeChildren(node);
  // TODO setup the omnibar with context and tree
};

export const onAction = async <T>(item: T): Promise<void> => {
  if (!!item && isTreeNode(item)) {
    const input: HTMLInputElement|null = document.querySelector('#omnibar input[type="text"]');
    if (input) {
      // TODO should be replaced, perhaps, with a update to the omnibar package's command decorator
      const { path } = await parseInput(input.value);
      input.value = absPathToAddress(path).join(SEPARATOR) + SEPARATOR + item.title;
      // trigger the onchange
      input.onchange && input.onchange(undefined as unknown as Event);
    }
    return onTreeNodeAction(item);
  }
  // else meh
  return Promise.resolve();
};
