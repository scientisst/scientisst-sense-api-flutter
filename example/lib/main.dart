import 'package:example/chart.dart';
import 'package:flutter/material.dart';
import 'package:scientisst_sense/scientisst_sense.dart';

const WINDOW_IN_SECONDS = 10;
const FS = 10;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<SensorValue> data;
  Sense sense;
  int c = 0;

  @override
  void initState() {
    super.initState();
    data =
        List.generate(WINDOW_IN_SECONDS * FS, (index) => SensorValue(index, 0));
    connect(); //.then((_) => start());
  }

  connect() async {
    //final devices = await Sense.find();
    //print(devices);
    final address = "08:3A:F2:49:AB:DE";
    //if (devices.isNotEmpty) {
    sense = Sense(address);
    await sense.connect();
    await sense.version();
    //}
  }

  start() async {
    await sense?.start(
      FS,
      [AI3],
    );
    int numFrames = FS ~/ 5;
    List<Frame> frames;
    while (false) {
      frames = await sense.read(numFrames);
      setState(() {
        for (int i = 0; i < frames.length; i++) {
          data[c] = SensorValue(c, frames[i].a[2]);
          c++;
          if (c >= data.length) {
            c = 0;
          }
        }
      });
    }
  }

  @override
  void dispose() async {
    await sense.stop();
    await sense.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          height: 500,
          child: ChartWidget(
            data,
          ),
        ),
      ),
    );
  }
}
