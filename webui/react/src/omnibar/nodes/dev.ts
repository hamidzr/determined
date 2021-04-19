import { setServerAddress } from 'dev';
import { globalStorage } from 'globalStorage';
import { alertAction } from 'omnibar/actions';
import { Children, TreeNode } from 'omnibar/AsyncTree';
import devExtension from 'omnibar/nodes/dev.rr.tmp';

const dev: TreeNode[] = [
  {
    options: [
      {
        onAction: () => globalStorage.removeServerAddress(),
        title: 'reset',
      },
      {
        onAction: alertAction(`address: ${globalStorage.serverAddress}`),
        title: 'show',
      },
      {
        onCustomInput: (inp: string): Children => {
          return [ {
            onAction: () => setServerAddress(inp),
            title: 'Ok',
          } ];
        },
        title: 'set',
      },
    ],
    title: 'serverAddress',
  },
  ...devExtension,
];

export default dev;
