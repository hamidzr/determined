import React, { useCallback, useEffect, useRef } from 'react';
import ReactMonacoEditor, { EditorDidMount, EditorWillMount, MonacoEditorProps } from 'react-monaco-editor';

import useResize from 'hooks/useResize';
import useUI from 'shared/contexts/stores/UI';
import { DarkLight } from 'shared/themes';

import css from './MonacoEditor.module.scss';

const PADDING = 8;

const MonacoEditor: React.FC<MonacoEditorProps> = ({
  height = '100%',
  language = 'yaml',
  options = {},
  ...props
}: MonacoEditorProps) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<ReactMonacoEditor>(null);
  const resize = useResize(containerRef);
  const { ui } = useUI();

  const handleEditorDidMount: EditorDidMount = useCallback((editor) => editor.focus(), []);
  const handleEditorWillMount: EditorWillMount = useCallback((monaco) => {
    const opts = {
      enableSchemaRequest: true,
      schemas: [
        // TODO based on config type
        {
          // id of the first schema
fileMatch: ['*'],
          uri:
            'https://hzdl.netlify.app/dai/schemas/expconf/v0/experiment.json', // associate with our model
        },
      ],
      validate: true,
    };
    monaco.languages.setLanguageConfiguration('yaml', opts);
  }, []);

  useEffect(() => {
    if (!editorRef.current) return;
    editorRef.current?.editor?.layout();
      }, [resize]);

  return (
    <div className={css.base} ref={containerRef}>
      <ReactMonacoEditor
      editorDidMount={handleEditorDidMount}
        editorWillMount={handleEditorWillMount}
        height={height}
        language={language}
        options={{
          minimap: { enabled: false },
          padding: { bottom: PADDING, top: PADDING },
          scrollBeyondLastLine: false,
          selectOnLineNumbers: true,
          ...options,
        }}
        ref={editorRef}
        theme={ui.darkLight === DarkLight.Dark ? 'vs-dark' : 'vs-light'}
        {...props}
      />
    </div>
  );
};

export default MonacoEditor;
