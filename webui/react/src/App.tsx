import React, { useEffect } from 'react';
import { GlobalHotKeys } from 'react-hotkeys';
import { Redirect, Route, Switch } from 'react-router-dom';

import NavBar from 'components/NavBar';
import Router from 'components/Router';
import SideBar from 'components/SideBar';
import Compose from 'Compose';
import ActiveExperiments from 'contexts/ActiveExperiments';
import Agents from 'contexts/Agents';
import Auth from 'contexts/Auth';
import ClusterOverview from 'contexts/ClusterOverview';
import { Commands, Notebooks, Shells, Tensorboards } from 'contexts/Commands';
import Info from 'contexts/Info';
import Users from 'contexts/Users';
import useRestApi from 'hooks/useRestApi';
import useRouteTracker from 'hooks/useRouteTracker';
import useTheme from 'hooks/useTheme';
import { ioDeterminedInfo } from 'ioTypes';
import Omnibar, { keymap as omnibarKeymap } from 'omnibar/Component';
import OmnibarCtx from 'omnibar/Context';
import { appRoutes, defaultAppRoute } from 'routes';
import { jsonToDeterminedInfo } from 'services/decoder';
import { DeterminedInfo } from 'types';
import { updateFaviconType } from 'utils/browser';

import css from './App.module.scss';

const globalKeymap = {
  HIDE_OMNIBAR: [ 'esc' ], // TODO scope it to the component
  SHOW_OMNIBAR: [ 'ctrl+space' ],
};

const AppView: React.FC = () => {
  const { isAuthenticated, user } = Auth.useStateContext();
  const cluster = ClusterOverview.useStateContext();
  const info = Info.useStateContext();
  const setInfo = Info.useActionContext();
  const OmnibarState = OmnibarCtx.useStateContext();
  const setOmnibar = OmnibarCtx.useActionContext();
  const username = user ? user.username : undefined;
  const [ infoResponse, requestInfo ] =
    useRestApi<DeterminedInfo>(ioDeterminedInfo, { mappers: jsonToDeterminedInfo });

  const globalKeyHandler = {
    HIDE_OMNIBAR: (): void => setOmnibar({ type: OmnibarCtx.ActionType.Hide }),
    SHOW_OMNIBAR: (): void => setOmnibar({ type: OmnibarCtx.ActionType.Show }),
  };
  updateFaviconType(cluster.allocation !== 0);

  useRouteTracker();
  useTheme();

  useEffect(() => requestInfo({ url: '/info' }), [ requestInfo ]);

  useEffect(() => {
    if (!info.telemetry.enabled || !info.telemetry.segmentKey) return;
    window.analytics.load(info.telemetry.segmentKey);
    window.analytics.identify(info.clusterId);
    window.analytics.page();
  }, [ info ]);

  useEffect(() => {
    if (!infoResponse.data) return;
    setInfo({ type: Info.ActionType.Set, value: infoResponse.data });
  }, [ infoResponse, setInfo ]);

  return (
    <div className={css.base}>
      {isAuthenticated && <NavBar username={username} />}
      <div className={css.body}>
        {isAuthenticated && <SideBar />}
        <Switch>
          <Route exact path="/">
            <Redirect to={defaultAppRoute.path} />
          </Route>
          <Router routes={appRoutes} />
        </Switch>
      </div>
      {OmnibarState.isShowing && <Omnibar />}
      <GlobalHotKeys handlers={globalKeyHandler} keyMap={globalKeymap} />
    </div>
  );
};

const App: React.FC = () => {

  return (
    <Compose components={[
      Auth.Provider,
      Info.Provider,
      Users.Provider,
      Agents.Provider,
      ClusterOverview.Provider,
      ActiveExperiments.Provider,
      Commands.Provider,
      Notebooks.Provider,
      Shells.Provider,
      Tensorboards.Provider,
      OmnibarCtx.Provider,
    ]}>
      <AppView />
    </Compose>
  );
};

export default App;
