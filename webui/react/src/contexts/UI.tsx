import { generateContext } from 'contexts';
import { globalStorage } from 'utils/storage';

enum ActionType {
  CollapseChrome,
  ExpandChrome,
  HideChrome,
  HideSpinner,
  ShowChrome,
  ShowSpinner,
}

type State = {
  chromeCollapsed: boolean;
  showChrome: boolean;
  showSpinner: boolean;
}

export const CHROME_COLLAPSED_KEY = 'chromeCollapsed';
type Action =
  | { type: ActionType.CollapseChrome }
  | { type: ActionType.ExpandChrome }
  | { type: ActionType.HideChrome }
  | { type: ActionType.HideSpinner }
  | { type: ActionType.ShowChrome }
  | { type: ActionType.ShowSpinner }

const defaultState = {
  chromeCollapsed: globalStorage.getWithDefault(CHROME_COLLAPSED_KEY, false),
  showChrome: true,
  showSpinner: false,
};

const reducer = (state: State, action: Action): State => {
  switch (action.type) {
    case ActionType.CollapseChrome:
      globalStorage.set(CHROME_COLLAPSED_KEY, true);
      return { ...state, chromeCollapsed: true };
    case ActionType.ExpandChrome:
      globalStorage.set(CHROME_COLLAPSED_KEY, false);
      return { ...state, chromeCollapsed: false };
    case ActionType.HideChrome:
      return { ...state, showChrome: false };
    case ActionType.HideSpinner:
      if (!state.showSpinner) return state;
      return { ...state, showSpinner: false };
    case ActionType.ShowChrome:
      return { ...state, showChrome: true };
    case ActionType.ShowSpinner:
      if (state.showSpinner) return state;
      return { ...state, showSpinner: true };
    default:
      return state;
  }
};

const contextProvider = generateContext<State, Action>({
  initialState: defaultState,
  name: 'Spinner',
  reducer,
});

export default { ...contextProvider, ActionType };
