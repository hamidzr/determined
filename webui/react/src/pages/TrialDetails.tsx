import Chart from 'chart.js';
import { PlotData } from 'plotly.js';
import React, { useEffect, useRef } from 'react';
import { Line as LineCJ } from 'react-chartjs-2';
import Plotly from 'react-plotly.js';
import { CartesianGrid, Line, LineChart, XAxis, YAxis } from 'recharts';

import trialResponse from 'assets/sample-trial.json';

// http://recharts.org/en-US/guide/getting-started
// https://plotly.com/javascript/react/
// https://www.chartjs.org/docs/latest/getting-started/usage.html

const plotlyData: Partial<PlotData>[] = [
  {
    marker: { color: 'red' },
    mode: 'lines+markers',
    type: 'scatter',
    x: [ 1, 2, 3 ],
    y: [ 2, 6, 3 ],
  },
  { type: 'bar', x: [ 1, 2, 3 ], y: [ 2, 5, 3 ] },
];

const rechartsData = [
  { name: 'Page A', uv: 400, zv: 2400 },
  { name: 'Page b', uv: 300, zv: 2400 },
  { name: 'Page c', uv: 200, zv: 2400 },
  { name: 'Page d', uv: 800, zv: 2400 },
];

const CJState = {
  datasets: [
    {
      backgroundColor: 'rgba(75,192,192,1)',
      borderColor: 'rgba(0,0,0,1)',
      borderWidth: 2,
      data: [ 65, 59, 80, 81, 56 ],
      fill: false,
      label: 'Rainfall',
      lineTension: 0.5,
    },
  ],
  labels: [ 'January',
    'February',
    'March',
    'April',
    'May' ],
};

const TrialDetails: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    new Chart(canvasRef.current?.getContext('2d') as CanvasRenderingContext2D, {
      data: CJState,
      type: 'line',
    });
  }, []);

  return (
    <div>
      <Plotly
        data={plotlyData}
        layout={ {  height: 400, title: 'A Fancy Plot', width: 400  } }
      />

      <LineChart data={rechartsData} height={400} width={400}>
        <Line dataKey="uv" stroke="#8884d8" type="monotone" />
        <CartesianGrid stroke="#ccc" />
        <XAxis dataKey="name" />
        <YAxis />
      </LineChart>

      <LineCJ
        data={CJState}
        options={{
          legend:{
            display:true,
            position:'right',
          },
          title:{
            display:true,
            fontSize:20,
            text:'Average Rainfall per month',
          },
        }}
      />
      <canvas height="400" id="myChartJs" ref={canvasRef} width="400" />

    </div>
  );
};

export default TrialDetails;
