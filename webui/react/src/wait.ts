import { w3cwebsocket as W3CWebSocket } from 'websocket';

import { globalStorage } from 'globalStorage';

// createWsUrl: Given an event url create the corresponding ws url.
function createWsUrl(eventUrl: string): string {
  const isFullUrl = /^https?:\/\//i;

  if (isFullUrl.test(eventUrl)) {
    return eventUrl.replace(/^http/, 'ws');
  } else {
    // Remove the preceding slash if it is an absolute path.
    eventUrl = eventUrl.replace(/^\//, '');
    let url = window.location.protocol.replace(/^http/, 'ws');
    url += '//' + window.location.host + '/' + eventUrl;
    return url;
  }
}

export const connect = (eventUrl: string): void => {
  const url = createWsUrl(eventUrl);
  const client = new W3CWebSocket(
    url,
    undefined,
    undefined,
    { authorization: 'Bearer ' + globalStorage.authToken },
  );

  client.onopen = () => {
    console.log('WebSocket Client Connected');
  };
  client.onmessage = (message) => {
    console.log(message);
  };
};
