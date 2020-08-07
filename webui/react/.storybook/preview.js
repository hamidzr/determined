import 'styles/index.scss';
import 'styles/storybook.scss';
import 'prototypes';

import { addDecorator } from "@storybook/react"
import 'loki/configure-react';

import ThemeDecorator from "storybook/ThemeDecorator"

export const decorators = [ ThemeDecorator ];
export const parameters = { layout: 'centered' };
