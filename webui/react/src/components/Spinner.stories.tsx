import React from 'react';

import Spinner from './Spinner';

export default {
  component: Spinner,
  title: 'Spinner',
};

export const Default = (): React.ReactNode => <Spinner />;

export const WithTip = (): React.ReactNode => <Spinner
  tip="Fetching trials."
/>;
