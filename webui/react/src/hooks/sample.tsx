import React, { useCallback, useEffect, useState } from 'react';

import useModal, { ModalHooks, ModalOpen } from 'shared/hooks/useModal/useModal';

interface Props {
  onClose?: () => void;
}

interface OnOpenProps {
  byRef: {
    text: string;
  };
  text: string;
}

interface ContentProps extends OnOpenProps {
  setInput: (value: string) => void;
  text2: string;
}

const ModalContent: React.FC<ContentProps> = (p) => {
  return (
    <div>
      <p>
        modal content: {p.text} {p.text2} {p.byRef.text}
      </p>
      <input onChange={(e) => p.setInput(e.target.value)} />
    </div>
  );
};

const useSampleModal = ({ onClose }: Props): ModalHooks<OnOpenProps> => {
  const { modalOpen: openOrUpdate, ...modalHooks } = useModal({ onClose });
  const [ isOpen, setIsOpen ] = useState(false);
  const [ input, setInput ] = useState<string>('');

  const onOk = useCallback(async () => {
    await (() => true)();
  }, [ ]);

  const modalOpen: ModalOpen<OnOpenProps> = useCallback((
    modalProps = {},
  ) => {
    const { context: newOpenProps, ...antdProps } = modalProps;
    setIsOpen(true);

    openOrUpdate({
      ...antdProps,
      content: newOpenProps && (
        <ModalContent
          byRef={newOpenProps.byRef}
          setInput={setInput}
          text="hi"
          text2={input}
        />
      ),
      okButtonProps: { disabled: input === 'disabled' },
      okText: newOpenProps && `Update ${newOpenProps.text }`,
      onOk,
    });
  }, [ onOk, openOrUpdate, input ]);

  // listen for changes and update the modal
  useEffect(() => {
    if (isOpen) openOrUpdate({ okButtonProps: { disabled: input === 'disabled' } });
  }, [ openOrUpdate, input, isOpen ]);

  return { modalOpen, ...modalHooks };
};

export default useSampleModal;
