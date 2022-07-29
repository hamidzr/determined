import { act, render, screen } from '@testing-library/react';
import React, { useCallback, useEffect, useState } from 'react';

import { Eventually } from 'shared/types';
import { isEqual } from 'shared/utils/data';

const OPEN_BTN = 'open-modal';

import useModal, { ModalOpen } from './useModal';

interface OnOpenProps {
  id: string;
}

interface TestProps {
  onClose: () => Eventually<any>;
  onOk: (p: OnOpenProps) => Eventually<any>;
}

const ModalContent: React.FC<OnOpenProps> = ({ id }) => {
  return <p>{id}</p>;
};

const TestComp: React.FC<TestProps> = ({ onClose, onOk }) => {
  // const [ openProps, setOpenProps ] = useState<OnOpenProps | undefined>();
  const { modalOpen: openOrUpdate, ...modalHooks } = useModal<OnOpenProps>({ onClose });

  const modalOpen: ModalOpen<OnOpenProps> = useCallback((newModalProps) => {
    const newOpenProps = newModalProps?.context;
    // remember the passed in open props so we can update the content if needed.
    // if (!!newOpenProps && !isEqual(openProps, newOpenProps))
    //   setOpenProps(newOpenProps);

    // const curOpenProps = newOpenProps || openProps;
    if (!newOpenProps) return; // cannot open modal without open props

    openOrUpdate({
      content: <ModalContent id={newOpenProps.id} />,
      onOk: () => onOk(newOpenProps),
      ...newModalProps,
    });
  }, [ openOrUpdate, onOk ]);

  return (
    <div>
      <p>hi</p>
      <button onClick={() => modalOpen({ context: { id: 'openByButton' } })}>{OPEN_BTN}</button>
      {modalHooks.contextHolder}
    </div>
  );
};

const setup = (props: TestProps) => {
  const handleOnChange = jest.fn();
  const view = render(<TestComp {...props} />);
  return { handleOnChange, view };
};

describe('hooks/useModal', () => {
  it('ensure onOk and onClose get called', async () => {
    const onClose = jest.fn();
    const onOk = jest.fn();
    act(() => {
      setup({ onClose, onOk });
    });
    expect(screen.getByText('hi')).toBeInTheDocument();

    // click on the button to open the modal
    act(() => {
      screen.getByText(OPEN_BTN).click();
    });
    await screen.findByText('OK');

    expect(screen.getByText('OK')).toBeInTheDocument();
    expect(screen.getByText('Cancel')).toBeInTheDocument();
    expect(screen.getByText('openByButton')).toBeInTheDocument();

    // close the modal
    act(() => {
      screen.getByText('Cancel').click();
    });
    // expect(screen.getByText('openByButton')).not.toBeInTheDocument();

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onOk).toHaveBeenCalledTimes(0);

    // click on the button to open the modal
    act(() => {
      screen.getByText(OPEN_BTN).click();
    });

    await act(async () => {
      // confirm the modal
      await screen.findByText('OK');
      screen.getByText('OK').click();
    });
    expect(onOk).toHaveBeenCalledTimes(1);
    expect(onClose).toHaveBeenCalledTimes(2);
  });

});
