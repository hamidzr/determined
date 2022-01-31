import { telemetryInstance } from 'hooks/useTelemetry';
import { paths } from 'routes/utils';
import history from 'shared/routes/history';
import { sharedHandleError } from 'tmp-shared/utils/error';

import { DetError, DetErrorOptions, ERROR_NAMESPACE,
  ErrorType } from '../shared/utils/error';
import { filterOutLoginLocation } from '../shared/utils/routes';

const coreErrorHandlerCB = (e: DetError): void => {
  // Redirect to logout if Auth failure detected (auth token is no longer valid).`
  if (e.type === ErrorType.Auth) {
    // This check accounts for requestes that had not been aborted properly prior
    // to the page dismount and end up throwing after the user is logged out.
    const path = window.location.pathname;
    if (!path.includes(paths.login()) && !path.includes(paths.logout())) {
      history.push(paths.logout(), { loginRedirect: filterOutLoginLocation(window.location) });
    }
  }

  // Report to segment.
  telemetryInstance.track(`${ERROR_NAMESPACE}: ${e.level}`, e);
};

const handleError = (error: DetError | unknown, options?: DetErrorOptions): void => {
  sharedHandleError(error, options, coreErrorHandlerCB);
};

export default handleError;
