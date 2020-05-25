import { LeafNode, NLNode } from 'omnibar/Tree';
import { archiveExperiment, getExperiments, killExperiment } from 'services/api';
import { activeRunStates, terminalRunStates } from 'utils/types';

const root: NLNode  = {
  options: [
    {
      title: 'showTime',
      onAction: () => alert(new Date()),
    },
    {
      options: async () => {
        const exps = await getExperiments({ states: activeRunStates });
        const options: LeafNode[] = exps.map(exp => (
          {
            title: `${exp.id}`,
            onAction: () => killExperiment({ experimentId: exp.id }),
          })); // is use of `this` discouraged?
        return options;
      },
      title: 'killExperiments',
    },
    {
      options: async () => {
        const exps = await getExperiments({ states: terminalRunStates });
        const options: LeafNode[] = exps.map(exp => (
          {
            onAction: () => archiveExperiment(exp.id, true),
            title: `${exp.id}`,
          })); // is use of `this` discouraged?
        return options;
      },
      title: 'archiveExperiments',
    },
    {
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
      title: 'manageCluster',
    },
  ],
  title: 'root',
};

export default root;
