import { getExperiments, killExperiment } from 'services/api';
import { isAsyncFunction } from 'utils/data';

// interface ResultItem {
//   title: string; // to utilize the default renderer
//   onAction?: Action<ResultItem>;
// }

interface BaseNodeProps {
  title: string; // should work with the separator. no space?
}

interface Input {
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
const traverseTree = async (path: string[], startNode: NLNode): Promise<TreeNode> => {
  let curNode: TreeNode = startNode;
  let i = 0;
  while(isNLNode(curNode) && i<path.length) {
    const children: TreeNode[] = await getNodeChildren(curNode);
    const rv = children.find(n => n.title === path[i]);
    if (rv === undefined) break;
    curNode = rv;
    i++;
  }
  if (i < path.length) throw new Error('bad path');
  return curNode;
};

const parseInput = (input: string) => {

};

export const ext = async (input: string): Promise<TreeNode[]> => {
  const sections = input.trim().split(' ');
  if (sections.length === 0) return [];
  const query = sections[sections.length-1];
  const path = sections.slice(0,length-2);
  // path.splice(0,0,'root'); // start traversing from root
  const node = await traverseTree(path, root);
  if (isLeafNode(node)) {
    // this is after the leafnode onaction triggers
    // or trigger it directly?
    return [];
  }
  const children = await getNodeChildren(node);

  const matchingSibilings = children.filter(it => it.title.match(new RegExp(query, 'i')));
  return matchingSibilings;
};

const onTreeNodeAction = async (node: TreeNode): Promise<void> => {
  if (isLeafNode(node)) return node.onAction(node);
  await getNodeChildren(node);
  // TODO setup the omnibar with context and tree
};

export const onAction = <T>(item: T): Promise<void> => {
  if (!!item && isTreeNode(item)) {
    const input: HTMLInputElement|null = document.querySelector('#omnibar input[type="text"]');
    if (input) {
      // TODO should be replaced, perhaps, with a update to the omnibar package's command decorator
      input.value = item.title;
      // trigger the onchange
      input.onchange && input.onchange(undefined as unknown as Event);
    }
    return onTreeNodeAction(item);
  }
  // else meh
  return Promise.resolve();
};
