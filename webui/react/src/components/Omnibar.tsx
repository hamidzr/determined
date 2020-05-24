import OmnibarNpm from 'omnibar';
import React from 'react';

const ext1 = () => [
  { title: 'Dropbox', url: 'https://dropbox.com' },
  { title: 'GitHub', url: 'https://google.com' },
  { title: 'Facebook', url: 'https://facebook.com' },
];

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

interface ItemProps<T> {
  item: T;
  isSelected: boolean;
  isHighlighted: boolean;
}

const ItemRenderer = (p: ItemProps<any>) => {
  console.log(p.item, p.isHighlighted, p.isSelected);
  return (
    <div>{p.item.name}</div>
  );

};

const Omnibar: React.FC = () => {
  return (
    <div>
      <OmnibarNpm
        extensions={[ () => data1 ]}
        placeholder="Enter keyword"
        render={ItemRenderer} />
    </div>
  );
};

export default Omnibar;
