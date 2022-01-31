import { notification as antdNotification } from 'antd';
import { ArgsProps, NotificationApi } from 'antd/lib/notification';

import { DetError, DetErrorOptions, ErrorLevel } from '../../shared/utils/error';
import { LoggerInterface } from '../../shared/utils/Logger';
import { isAborted } from '../../shared/utils/service';
import { listToStr } from '../../shared/utils/string';

const errorLevelMap = {
  [ErrorLevel.Error]: 'error',
  [ErrorLevel.Fatal]: 'error',
  [ErrorLevel.Warn]: 'warn',
};

const openNotification = (e: DetError) => {
  const key = errorLevelMap[e.level] as keyof NotificationApi;
  const notification = antdNotification[key] as (args: ArgsProps) => void;

  notification?.({
    description: e.publicMessage || '',
    message: e.publicSubject || e.message || listToStr([ e.type, e.level ]),
  });
};

const log = (e: DetError) => {
  const key = errorLevelMap[e.level] as keyof LoggerInterface;
  const message = listToStr([ `${e.type}:`, e.publicMessage, e.message ]);
  e.logger[key](message);
  e.logger[key](e);
};
/** usage: handle an error at the point that you'd want to stop bubbling it up. Avoid handling
 * and re-throwing.
 */
export const sharedHandleError = (
  error: DetError | unknown,
  options?: DetErrorOptions,
  callback?: (e: DetError) => void,
): void => {
  // Wrap existing error with more info via `options`.
  const e: DetError = new DetError(error, options);

  // Ignore request cancellation errors.
  if (isAborted(e)) return;

  // Ensure `handleError` doesn't handle the same exact error more than once.
  if (e.isHandled) {
    if (process.env.IS_DEV) {
      console.warn(`Error "${e.message}" is handled twice.`);
    }
    return;
  }
  e.isHandled = true;

  // TODO add support for checking, saving, and dismissing class of errors as a user preference
  // using id.
  if (!e.silent) openNotification(e);

  // TODO generate stack trace if error is missing? http://www.stacktracejs.com/

  // Log the error if needed.
  if (!e.silent) log(e);

  // TODO SEP handle transient failures? eg only take action IF.. (requires keeping state)

  // TODO SEP capture a screenshot or more context (generate a call stack)?
  // https://stackblitz.com/edit/react-screen-capture?file=index.js

  if (callback) callback(e);
};
