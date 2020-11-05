import React, { MouseEvent, MouseEventHandler, PropsWithChildren, useCallback } from 'react';

import { handlePath, isAbsolutePath, isFullPath, serverAddress,
  windowOpenFeatures } from 'routes/utils';

import css from './Link.module.scss';

export interface Props {
  className?: string;
  disabled?: boolean;
  inherit?: boolean;
  isButton?: boolean;
  // is this external to the assets hosted by React?
  external?: boolean;
  path?: string;
  popout?: boolean;
  onClick?: MouseEventHandler;
}

const Link: React.FC<Props> = ({
  external,
  popout,
  onClick,
  ...props
}: PropsWithChildren<Props>) => {
  const classes = [ css.base ];
  const rel = windowOpenFeatures.join(' ');

  if (props.className) classes.push(props.className);
  if (!props.disabled) classes.push(css.link);
  if (props.inherit) classes.push(css.inherit);
  if (props.isButton) classes.push('ant-btn');

  let path: string;
  if (external && props.path) {
    if (isAbsolutePath(props.path) && !isFullPath(props.path)) {
      path = serverAddress() + props.path;
    } else {
      path = props.path;
    }
  } else {
    path = process.env.PUBLIC_URL + (props.path + '#');
  }

  const handleClick = useCallback((event: MouseEvent) => {
    handlePath(event, { onClick, path, popout });
  }, [ onClick, popout, path ]);

  return props.disabled ? (
    <span className={classes.join(' ')}>{props.children}</span>
  ) : (
    <a
      className={classes.join(' ')}
      href={path}
      rel={rel}
      onClick={handleClick}>
      {props.children}
    </a>
  );
};

export default Link;
