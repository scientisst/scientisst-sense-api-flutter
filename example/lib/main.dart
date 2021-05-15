import 'package:flutter/material.dart';
import 'package:scientisst_sense/scientisst_sense.dart';

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
  @override
  void initState() {
    super.initState();
  }

  test() async {
    final devices = await Sense.find();
    if (devices.isNotEmpty) {
      final sense = Sense(devices.first);
      await sense.connect();
      await sense.version();
      await Future.delayed(Duration(seconds: 1));
      await sense.start(
        5000,
        [AI3],
      );
      await Future.delayed(Duration(seconds: 5));
      await sense.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    test();
    return Scaffold(
      body: Container(),
    );
  }
}
