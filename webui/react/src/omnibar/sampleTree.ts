import { Children, LeafNode, NLNode } from 'AsyncTree';
import { archiveExperiment, getExperiments, killExperiment } from 'services/api';
import { activeRunStates, terminalRunStates } from 'utils/types';

const root: NLNode  = {
  options: [
    {
      onAction: (): void => alert(new Date()),
      title: 'showTime',
    },
    {
      options: async (): Promise<Children> => {
        const exps = await getExperiments({ states: activeRunStates });
        const options: LeafNode[] = exps.map(exp => (
          {
            onAction: (): unknown => killExperiment({ experimentId: exp.id }),
            title: `${exp.id}`,
          })); // is use of `this` discouraged?
        return options;
      },
      title: 'killExperiments',
    },
    {
      options: async (): Promise<Children> => {
        const exps = await getExperiments({ states: terminalRunStates });
        const options: LeafNode[] = exps.map(exp => (
          {
            onAction: (): unknown => archiveExperiment(exp.id, true),
            title: `${exp.id}`,
          })); // is use of `this` discouraged?
        return options;
      },
      title: 'archiveExperiments',
    },
    {
      options: async (): Promise<Children> => {
        // const staticOptions = [
        //   {
        //     title: 'zeroSlot',
        //     onAction: ():
        //   },
        // ];
        const exps = await getExperiments({ states: terminalRunStates });
        const options: LeafNode[] = exps.map(exp => (
          {
            onAction: (): unknown => archiveExperiment(exp.id, true),
            title: `${exp.id}`,
          })); // is use of `this` discouraged?
        return options;
      },
      title: 'launchNotebook',
    },
    {
      options: [
        {
          onAction: (): void => alert('restarted master'),
          title: 'restart',
        },
        {
          onAction: (): void => alert('reloaded master'),
          title: 'reload',
        },
        {
          onAction: (): void => alert('here are the logs..'),
          title: 'showlogs',
        },
      ],
      title: 'manageCluster',
    },
  ],
  title: 'root',
};

export default root;
