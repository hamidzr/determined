import OmnibarNpm from 'omnibar';
import React from 'react';

import { funcExt, funcOnAction } from 'omnibar/Func';
import * as Tree from 'omnibar/Tree';

const titleData = [
  { title: 'Dropbox', url: 'https://dropbox.com' },
  { title: 'GitHub', url: 'https://google.com' },
  { title: 'Facebook', url: 'https://facebook.com' },
];
const ext1 = () => titleData;

const ext2 = () => (Promise.resolve({ items: [
  { name: 'Dropbox', website: 'https://dropbox.com' },
  { name: 'GitHub', website: 'https://google.com' },
  { name: 'Facebook', website: 'https://facebook.com' },
] }));

const data1 = [
  { name: 'Dropbox', website: 'https://dropbox.com' },
  { name: 'GitHub', website: 'https://google.com' },
  { name: 'Facebook', website: 'https://facebook.com' },
];

const openUrl = (it: {url: string})  => window.location.assign(it.url);
const actionMap = [
  { title: 'go to experiments', url: '/ui/experiments', onAction: openUrl },
];

const ext3 = (query: string) => {
  if (!query) return titleData;
  return titleData.filter(item => !!item.title.match(new RegExp(query, 'i')));
};

const ext4 = (query: string) => {
  if (!query) return actionMap;
  return actionMap.filter(item => !!item.title.match(new RegExp(query, 'i')));
};

interface ItemProps<T> {
  item: T;
  isSelected: boolean;
  isHighlighted: boolean;
}

// const ItemRenderer = (p: ItemProps<any>) => {
//   return (
//     <div>{p.item.name}</div>
//   );
// };

const Omnibar: React.FC = () => {
  return (
    <div id="omnibar">
      <OmnibarNpm
        autoFocus={true}
        extensions={[ Tree.ext ]}
        placeholder="Enter keyword"
        onAction={Tree.onAction}
        /*render={ItemRenderer}*/ />
    </div>
  );
};

export default Omnibar;
