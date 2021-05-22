import 'package:charts_common/common.dart';
import 'package:charts_flutter/flutter.dart' as charts;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChartWidget extends StatelessWidget {
  final List<SensorValue> data;
  final List<SensorValue> peaks;
  final int offset;

  ChartWidget(this.data, {this.peaks, this.offset = 0});

  @override
  Widget build(BuildContext context) {
    List<charts.Series<dynamic, int>> _series = [
      charts.Series<SensorValue, int>(
        id: 'Values',
        colorFn: (_, __) => charts.Color.fromHex(code: "#5cbdd7"),
        domainFn: (SensorValue values, _) => values.x,
        measureFn: (SensorValue values, _) => values.y + this.offset,
        data: data,
      ),
    ];
    if (peaks != null) {
      _series.add(
        charts.Series<SensorValue, int>(
          id: 'Peaks',
          colorFn: (_, __) => charts.Color.fromHex(code: "#EED3FF"),
          domainFn: (SensorValue value, _) => value.x,
          measureFn: (SensorValue value, _) => value.y + this.offset,
          data: peaks,
        )..setAttribute(charts.rendererIdKey, 'customPoint'),
      );
    }
    return new charts.LineChart(
      _series,
      defaultRenderer:
          new LineRendererConfig(includeArea: true, strokeWidthPx: 3),
      customSeriesRenderers: [
        new charts.PointRendererConfig(
            // ID used to link series to this renderer.
            customRendererId: 'customPoint')
      ],
      animate: false,
      behaviors: [
        new charts.LinePointHighlighter(
            showHorizontalFollowLine:
                charts.LinePointHighlighterFollowLineType.none,
            showVerticalFollowLine:
                charts.LinePointHighlighterFollowLineType.none),
        new charts.SelectNearest(eventTrigger: null),
      ],
      primaryMeasureAxis: charts.NumericAxisSpec(
        tickProviderSpec: NumericEndPointsTickProviderSpec(),
        renderSpec: NoneRenderSpec(),
        showAxisLine: false,
      ),
      domainAxis: NumericAxisSpec(
        showAxisLine: false,
        renderSpec: NoneRenderSpec(),
      ),
      layoutConfig: charts.LayoutConfig(
          leftMarginSpec: MarginSpec.fixedPixel(0),
          rightMarginSpec: MarginSpec.fixedPixel(0),
          topMarginSpec: MarginSpec.fixedPixel(0),
          bottomMarginSpec: MarginSpec.fixedPixel(0)),
    );
  }
}

class SensorValue {
  final int x;
  final int y;

  SensorValue(this.x, this.y);
}
