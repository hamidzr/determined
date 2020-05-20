import Chart from 'chart.js';
import { PlotData } from 'plotly.js';
import React, { useEffect, useRef } from 'react';
import { Line as LineCJ } from 'react-chartjs-2';
import Plotly from 'react-plotly.js';
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip,
  XAxis, YAxis } from 'recharts';
import 'chartjs-plugin-zoom';

import trialResponse from 'assets/sample-trial.json';
import Grid from 'components/Grid';
import { generateSequence, generateSynData } from 'utils/data';

import css from './TrialDetails.module.scss';

// http://recharts.org/en-US/guide/getting-started
// https://plotly.com/javascript/react/
// https://www.chartjs.org/docs/latest/getting-started/usage.html

const trialData = trialResponse.steps
  .map(step => ({ x: step.id, y: step.validation.metrics.validation_metrics.validation_error }));
trialData.sort((a, b) => a.x > b.x ? 1 : -1);

// use synthetic data
const ys = generateSynData(1e+3);
const xs = generateSequence(ys.length);
const rechartsData = xs.map((x, idx) => ({ x, y: ys[idx] }));

// use trial data
// const xs = trialData.map(d => d.x);
// const ys = trialData.map(d => d.y);
// const rechartsData = trialData;

/* define the data */
const plotlyData: Partial<PlotData>[] = [
  {
    marker: { color: 'red' },
    mode: 'lines+markers',
    type: 'scatter',
    x: xs,
    y: ys,
  },
];

// used by both chartjs implementations (react and native)
const CJState = {
  datasets: [
    {
      // backgroundColor: 'rgba(75,192,192,1)',
      // borderColor: 'rgba(0,0,0,1)',
      // borderWidth: 2,
      data: ys,
      // fill: false,
      // label: 'Rainfall',
      // lineTension: 0.5,
    },
  ],
  labels: xs,
};

/* define the common options */
const plotlyConfig = { displaylogo: false };
const chartJsOptions = {
  plugins: {
    zoom: { // https://github.com/chartjs/chartjs-plugin-zoom
      pan: {
        enabled: false,
        mode: 'xy',
        // On category scale, factor of pan velocity
        // speed: 20,
        // Minimal pan distance required before actually applying pan
        // threshold: 10,
      },

      zoom: {
        drag: true,
        enabled: true,
        mode: 'xy',
      },
    },
  },
  title:{
    display:true,
    text:'Average Rainfall per month',
  },
};

const TrialDetails: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const canvasRef2 = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const chart = new Chart(canvasRef.current?.getContext('2d') as CanvasRenderingContext2D, {
      data: CJState,
      type: 'line',
    });
    chart.options = chartJsOptions;
    const chart2 = new Chart(canvasRef2.current?.getContext('2d') as CanvasRenderingContext2D, {
      data: CJState,
      type: 'line',
    });
    chart2.options = { ...chartJsOptions, responsive: true };
  }, []);

  return (
    <div className={css.base}>

      <Plotly
        config={plotlyConfig}
        data={plotlyData}
        layout={ {  height: 400, title: 'A Fancy Plot', width: 400  } }
      />

      <LineChart data={rechartsData} height={400} width={400}>
        <Line dataKey="y" stroke="#8884d8" type="monotone" />
        <Tooltip />
        <CartesianGrid stroke="#ccc" />
        <XAxis dataKey="x" />
        <YAxis />
      </LineChart>

      <LineCJ
        data={CJState}
        options={chartJsOptions}
      />
      <canvas height="400" ref={canvasRef} width="400" />

      <h2>Put them in a Grid</h2>

      <Grid minItemWidth={40}>
        <Plotly
          config={plotlyConfig}
          data={plotlyData}
          layout={ { title: 'A Fancy Plot' } }
        />

        <ResponsiveContainer>
          <LineChart data={rechartsData}>
            <Line dataKey="y" stroke="#8884d8" type="monotone" />
            <Tooltip />
            <CartesianGrid stroke="#ccc" />
            <XAxis dataKey="x" />
            <YAxis />
          </LineChart>
        </ResponsiveContainer>

        <LineCJ
          data={CJState}
          options={{ ...chartJsOptions, responsive: true }}
        />

        <canvas ref={canvasRef2} />
      </Grid>

    </div>
  );
};

export default TrialDetails;
