part of 'scientisst_sense.dart';

// Object that stores information from the ScientISST device
class Frame {
  int seq;
  final List<int> a = List.filled(8, null, growable: false);
  final List<bool> digital = List.filled(4, false, growable: false);
}
