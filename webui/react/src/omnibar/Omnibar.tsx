import OmnibarNpm from 'omnibar';
import React from 'react';

import { funcExt, funcOnAction } from 'omnibar/Func';
import * as Tree from 'omnibar/Tree';

interface ItemProps<T> {
  item: T;
  isSelected: boolean;
  isHighlighted: boolean;
}

const ItemRenderer = (p: ItemProps<any>) => {
  return (
    <div>{p.item.name}</div>
  );
};

const Omnibar: React.FC = () => {
  return (
    <>
      <OmnibarNpm
        autoFocus={true}
        extensions={[ funcExt ]}
        placeholder="Type a function name"
        onAction={funcOnAction}
      />
      <div id="omnibar">
        <OmnibarNpm
          autoFocus={true}
          extensions={[ Tree.extension ]}
          placeholder="Enter keyword"
          onAction={Tree.onAction}
        /*render={ItemRenderer}*/ />
      </div>
    </>
  );
};

export default Omnibar;
