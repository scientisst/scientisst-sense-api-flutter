part of 'scientisst_sense.dart';

// Object that stores information from the ScientISST device
class Frame {
  int seq = -1;
  late List<int?> a;
  final List<bool> digital = List.filled(4, false, growable: false);

  Frame(int nrOfChannels)
      : assert(nrOfChannels > 0),
        this.a = List.filled(nrOfChannels, 0, growable: false);

  String toString() {
    return {"seq": seq, "digital": digital, "a": a}.toString();
  }
}
