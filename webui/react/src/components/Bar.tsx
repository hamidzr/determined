import { Tooltip } from 'antd';
import React from 'react';

import { ShirtSize } from 'themes';
import { floatToPercent } from 'utils/string';

import css from './Bar.module.scss';

export interface BarPart {
  percent: number; // between 0-1
  color: string; // css color
  label?: string;
}

export interface Props {
  barOnly?: boolean;
  parts: BarPart[];
  size?: ShirtSize;
}

const partStyle = (part: BarPart) => {
  return {
    backgroundColor: part.color,
    width: floatToPercent(part.percent, 0),
  };
};

const Bar: React.FC<Props> = ({ barOnly, parts, size }: Props) => {
  const classes: string[] = [ css.base ];

  if (barOnly) classes.push(css.barOnly);

  return (
    <div className={classes.join(' ')}>
      <div
        className={css.bar}
        style={{ height: `var(--theme-sizes-layout-${size || ShirtSize.tiny})` }}>
        <ol>
          {parts.map(part => {
            return (
              <Tooltip key={part.label} title={part.label}>
                <li style={partStyle(part)} />
              </Tooltip>
            );
          })}
        </ol>

      </div>
    </div>
  );
};

export default Bar;
