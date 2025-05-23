var RUN_TIME_AXIS_TITLE = "Run Time in nanoseconds";

var drawGraph = function(node, data, layout) {
  Plotly.newPlot(node, data, layout, {
    displaylogo: false,
    modeBarButtonsToRemove: ['sendDataToCloud']
  });
};

var comparisonData = function(scenarios, statistics_key, value_key, std_dev_key) {
  return [
    {
      type: "bar",
      x: scenarios.map(function(scenario) { return scenario.name; }),
      y: scenarios.map(function(scenario) { return scenario[statistics_key].statistics[value_key]; }),
      error_y: {
        type: "data",
        array: scenarios.map(function(scenario) { return scenario[statistics_key].statistics[std_dev_key]; }),
        visible: true
      }
    }
  ];
};

window.drawIpsComparisonChart = function(scenarios, inputHeadline) {
  var layout = {
    title: "Average Iterations per Second" + inputHeadline,
    yaxis: { title: "Iterations per Second" }
  };

  drawGraph(
    document.getElementById("ips-comparison"),
    comparisonData(scenarios, "run_time_data", "ips", "std_dev_ips"),
    layout
  );
};

window.drawMemoryComparisonChart = function(scenarios, inputHeadline) {
  var layout = {
    title: "Average Memory Usages (lower is better)" + inputHeadline,
    yaxis: { title: "Memory Usages in Bytes" }
  };

  drawGraph(
    document.getElementById("memory-comparison"),
    comparisonData(scenarios, "memory_usage_data", "average", "std_dev"),
    layout
  );
};


var boxPlotData = function(scenarios, data_key) {
  return scenarios.map(function(scenario) {
    return {
      name: scenario.name,
      y: scenario[data_key].samples,
      type: "box"
    };
  });
};

window.drawRunTimeComparisonBoxPlot = function(scenarios, inputHeadline) {
  var layout = {
    title: "Run Time Boxplot" + inputHeadline,
    yaxis: { title: RUN_TIME_AXIS_TITLE }
  };

  drawGraph(
    document.getElementById("run-time-box-plot"),
    boxPlotData(scenarios, "run_time_data"),
    layout
  );
};

window.drawMemoryComparisonBoxPlot = function(scenarios, inputHeadline) {
  var layout = {
    title: "Memory Consumption Boxplot" + inputHeadline,
    yaxis: { title: "Memory Consumption in Bytes" }
  };

  drawGraph(
    document.getElementById("memory-box-plot"),
    boxPlotData(scenarios, "memory_usage_data"),
    layout
  );
};

const rawChartLayout = function(title, y_axis_title, statistics) {
  var minY = statistics.minimum * 0.9;
  var maxY = statistics.maximum;

  return {
    title: title,
    yaxis: { title: y_axis_title, range: [minY, maxY] },
    xaxis: { title: "Sample number"},
    annotations: [{ x: 0, y: minY, text: parseInt(minY), showarrow: false, xref: "x", yref: "y", xshift: -10 }]
  };
}

const barChart = function(data) {
  return [
    {
      y: data,
      type: "bar"
    }
  ];
};

window.drawRawRunTimeChart = function(scenario, inputHeadline) {
  var layout = rawChartLayout(
    scenario.name + " Raw Run Times" + inputHeadline,
    RUN_TIME_AXIS_TITLE,
    scenario.run_time_data.statistics
  )

  drawGraph(
    document.getElementById("raw-run-times"),
    barChart(scenario.run_time_data.samples),
    layout
  );
};

window.drawRawMemoryChart = function(scenario, inputHeadline) {
  var layout = rawChartLayout(
    scenario.name + " Raw Memory Usages" + inputHeadline,
    "Raw Memory Usages in Bytes",
    scenario.memory_usage_data.statistics
  )

  drawGraph(
    document.getElementById("raw-memory"),
    barChart(scenario.memory_usage_data.samples),
    layout
  );
};

var histogramData = function(data) {
  return [
    {
      type: "histogram",
      x: data
    }
  ];
};

window.drawRunTimeHistogram = function(scenario, inputHeadline) {
  var layout = {
    title: scenario.name + " Run Times Histogram" + inputHeadline,
    xaxis: { title: "Raw run time buckets in nanoseconds" },
    yaxis: { title: "Occurences in sample" }
  };

  drawGraph(
    document.getElementById("run-times-histogram"),
    histogramData(scenario.run_time_data.samples),
    layout
  );
};

window.drawMemoryHistogram = function(scenario, inputHeadline) {
  var layout = {
    title: scenario.name + " Memory Histogram" + inputHeadline,
    xaxis: { title: "Raw memory usage buckets in bytes" },
    yaxis: { title: "Occurences in sample" }
  };

  drawGraph(
    document.getElementById("memory-histogram"),
    histogramData(scenario.memory_usage_data.samples),
    layout
  );
};

window.toggleSystemDataInfo = function() {
  var systemDataNode = document.getElementById("system-info");
  var newState = (systemDataNode.style.display === 'block') ? 'none' : 'block';

  systemDataNode.style.display = newState;
};
