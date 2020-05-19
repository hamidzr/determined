import { CopyOutlined } from '@ant-design/icons';
import { Button, Result } from 'antd';
import React, { useCallback } from 'react';

import Link from 'components/Link';
import { defaultAppRoute } from 'routes';
import { getCookie } from 'utils/browser';

import css from './AuthToken.module.scss';

interface Props {
  nextPage?: string;
}

const AuthToken: React.FC<Props> = ({ nextPage }: Props) => {
  const token = getCookie('auth') || 'Auth token not found.';

  const handleCopyToClipboard = useCallback(
    (): Promise<void> => navigator.clipboard.writeText(token),
    [ token ],
  );

  return (
    <Result
      className={css.base}
      extra={[
        <Button icon={<CopyOutlined />}
          key="copy" type="primary"
          onClick={handleCopyToClipboard}>
          Copy token to clipboard
        </Button>,
        <Button key="continue" type="primary">
          <Link path={nextPage || defaultAppRoute.path}>
            Continue
          </Link>
        </Button>,
      ]}
      status="success"
      subTitle={token}
      title="Your Determined Authentication Token"
    />
  );
};

export default AuthToken;
