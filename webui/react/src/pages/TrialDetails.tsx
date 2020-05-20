import Chart from 'chart.js';
import { PlotData } from 'plotly.js';
import React, { useEffect, useRef } from 'react';
import { Line as LineCJ } from 'react-chartjs-2';
import Plotly from 'react-plotly.js';
import { CartesianGrid, Line, LineChart, ResponsiveContainer, XAxis, YAxis } from 'recharts';

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
      backgroundColor: 'rgba(75,192,192,1)',
      borderColor: 'rgba(0,0,0,1)',
      borderWidth: 2,
      data: ys,
      fill: false,
      label: 'Rainfall',
      lineTension: 0.5,
    },
  ],
  labels: xs,
};

const TrialDetails: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const canvasRef2 = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    new Chart(canvasRef.current?.getContext('2d') as CanvasRenderingContext2D, {
      data: CJState,
      type: 'line',
    });
    const chart2 = new Chart(canvasRef2.current?.getContext('2d') as CanvasRenderingContext2D, {
      data: CJState,
      type: 'line',
    });
    chart2.options.responsive = true;
  }, []);

  return (
    <div className={css.base}>

      <Plotly
        data={plotlyData}
        layout={ {  height: 400, title: 'A Fancy Plot', width: 400  } }
      />

      <LineChart data={rechartsData} height={400} width={400}>
        <Line dataKey="y" stroke="#8884d8" type="monotone" />
        <CartesianGrid stroke="#ccc" />
        <XAxis dataKey="x" />
        <YAxis />
      </LineChart>

      <LineCJ
        data={CJState}
        options={{
          legend:{
            display:true,
          },
          title:{
            display:true,
            fontSize:20,
            text:'Average Rainfall per month',
          },
        }}
      />
      <canvas height="400" ref={canvasRef} width="400" />

      <h2>Let's put them in a Grid</h2>

      <Grid minItemWidth={40}>
        <Plotly
          data={plotlyData}
          layout={ { title: 'A Fancy Plot' } }
        />

        <ResponsiveContainer>
          <LineChart data={rechartsData}>
            <Line dataKey="y" stroke="#8884d8" type="monotone" />
            <CartesianGrid stroke="#ccc" />
            <XAxis dataKey="x" />
            <YAxis />
          </LineChart>
        </ResponsiveContainer>

        <LineCJ
          data={CJState}
          options={{
            legend:{
              display:true,
            },
            responsive: true,
            title:{
              display:true,
              fontSize:20,
              text:'Average Rainfall per month',
            },
          }}
        />

        <canvas ref={canvasRef2} />
      </Grid>

    </div>
  );
};

export default TrialDetails;
