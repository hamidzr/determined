import React from 'react';

import ResponsiveTable from './ResponsiveTable';

export default {
  component: ResponsiveTable,
  parameters: { layout: 'padded' },
  title: 'ResponsiveTable',
};

const columns = new Array(20).fill(null).map(() => {
  const str = 'lorem';
  return {
    dataIndex: str,
    sorter: true,
    title: str,
  };
});

const data = new Array(100).fill(null).map(() => {
  const row: Record<string, string> = {};
  columns.forEach(column => {
    row[column.dataIndex] = 'test';
  });
  return row;
});

export const Default = (): React.ReactNode => (
  <ResponsiveTable columns={columns} dataSource={data} />
);
