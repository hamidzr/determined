/* eslint-disable-file */
import React from 'react';

import { isDetError } from 'shared/utils/error';

interface Props {
  children: React.ReactNode;
  /**
   * fallback ui to show on caught exceptions.
   */
  fallback?: React.ReactNode;
  onError: (e: unknown) => void;
}

interface State {
  hasError: boolean;
  isDetError: boolean;
}

/**
 * ErrorBoundary is a wrapper component that catches and displays rendering errors.
 */
class ErrorBoundary extends React.Component<Props, State, unknown> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, isDetError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, isDetError: isDetError(error) };
  }

  componentDidCatch(error: Error): void {
    // sharedHandleError(error, undefined, this.props.onError);
    this.props.onError(error);
  }

  render(): React.ReactNode {
    const { hasError, isDetError } = this.state;
    if (!hasError) return this.props.children;

    if (this.props.fallback) return this.props.fallback;

    if (isDetError) return this.props.children;

    return (<p>TODO unexpected error. sad puppy page.</p>);
  }

}

export default ErrorBoundary;
