import axios, { AxiosResponse, CancelToken, Method } from 'axios';

import handleError, { ErrorLevel, ErrorType } from 'ErrorHandler';
import { isAuthFailure } from 'services/api';
import * as DetSwagger from 'services/api-ts-sdk';
import { serverAddress } from 'utils/routes';

/* eslint-disable @typescript-eslint/no-var-requires */
const ndjsonStream = require('can-ndjson-stream');
const ndjson = require('ndjson');

export const http = axios.create({
  responseType: 'json',
  withCredentials: true,
});

export interface HttpOptions {
  url?: string;
  method?: Method;
  headers?: Record<string, unknown>;
  body?: Record<keyof unknown, unknown> | string;
}

export interface Api<Input, Output>{
  name: string;
  httpOptions: (params: Input) => HttpOptions;
  postProcess?: (response: AxiosResponse<unknown>) => Output; // io type decoder.
  // middlewares?: Middleware[]; // success/failure middlewares
}

export const processApiError = (name: string, e: Error): void => {
  const isAuthError = isAuthFailure(e);
  const silent = !process.env.IS_DEV || isAuthError || axios.isCancel(e);
  handleError({
    error: e,
    level: isAuthError ? ErrorLevel.Fatal : ErrorLevel.Error,
    message: isAuthError ?
      `unauthenticated request ${name}` : `request ${name} failed.`,
    silent,
    type: isAuthError ? ErrorType.Auth : ErrorType.Server,
  });
  throw e;
};

export function generateApi<Input, Output>(api: Api<Input, Output>) {
  return async function(params: Input & { cancelToken?: CancelToken }): Promise<Output> {
    const httpOpts = api.httpOptions(params);

    try {
      const response = await http.request({
        cancelToken: params.cancelToken,
        data: httpOpts.body,
        headers: httpOpts.headers,
        method: httpOpts.method || 'GET',
        url: httpOpts.url as string,
      });

      return api.postProcess ? api.postProcess(response) : response.data as Output;
    } catch (e) {
      return processApiError(api.name, e) as unknown as Output;
    }
  };
}

/*
  consumeStream is used to consume streams from the generated TS client.
  We use the provided fetchParamCreator to create fetch arguments and use that
  to make a request and handle events one by one.
  Example:
  consumeStream<DetSwagger.V1TrialLogsResponse>(
    DetSwagger.ExperimentsApiFetchParamCreator().determinedTrialLogs(1),
    console.log,
  ).then(() => console.log('finished'));
*/
export const consumeStream = async <T = unknown>(
  fetchArgs: DetSwagger.FetchArgs, onEvent: (event: T) => void): Promise<void> => {
  try {
    const response = await fetch(serverAddress() + fetchArgs.url, fetchArgs.options);
    const exampleReader = ndjsonStream(response.body).getReader();
    let result;
    while (!result || !result.done) {
      result = await exampleReader.read();
      if (result.done) return;
      onEvent(result.value.result);
    }
  } catch (e) {
    processApiError(fetchArgs.url, e);
  }
};

export const consumeStream3 = async <T = unknown>(
  fetchArgs: DetSwagger.FetchArgs, onEvent: (event: T) => void): Promise<void> => {
  try {
    const response = await fetch(serverAddress() + fetchArgs.url, fetchArgs.options);
    if (response.body === null) throw new Error('null body');
    const reader = response.body.getReader();
    let result;
    while (!result || !result.done) {
      result = await reader.read();
      if (result.done) return;
      onEvent(result.value);
    }
  } catch (e) {
    processApiError(fetchArgs.url, e);
  }
};

export const consumeStream2 = <T = unknown>(
  fetchArgs: DetSwagger.FetchArgs, onEvent: (event: T) => void): Promise<void> => {
  return fetch('http://localhost:9090')
    .then(( response ) => {
      if (response.body === null) throw new Error('null body');
      return response.body.getReader();
      // return ndjsonStream( response.body ).getReader();
    })
    .then( ( reader ) => {
      //retain access to the reader so that you can cancel it
      console.log('here');

      const read = ( result: any ): any => {
        console.log('executing read');
        if ( result.done ) {
          return;
        }
        console.log( result.value ); //logs {item:"first"}
        return reader.read().then( read );
      };

      return reader.read()
        .then(read)
        .catch(console.error);
    })
    .catch(e => processApiError(fetchArgs.url, e));
};
