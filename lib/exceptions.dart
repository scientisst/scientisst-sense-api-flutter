part of 'scientisst_sense.dart';

enum SenseErrorType {
  INVALID_ADDRESS,
  DEVICE_NOT_FOUND,
  CONTACTING_DEVICE_ERROR,
  DEVICE_NOT_IDLE,
  DEVICE_NOT_IN_ACQUISITION,
  INVALID_PARAMETER,
  NOT_SUPPORTED,
  UNKNOWN_ERROR,
}

class SenseException implements Exception {
  String? msg;
  final SenseErrorType? type;

  SenseException([this.type, this.msg]) {
    switch (type) {
      case SenseErrorType.INVALID_ADDRESS:
        msg = "The device address must not be null nor empty.";
        return;
      case SenseErrorType.DEVICE_NOT_FOUND:
        msg = "The device could not be found.";
        return;
      case SenseErrorType.CONTACTING_DEVICE_ERROR:
        msg = "Lost communication with the device.";
        return;
      case SenseErrorType.DEVICE_NOT_IDLE:
        msg = "The device is not idle.";
        return;
      case SenseErrorType.DEVICE_NOT_IN_ACQUISITION:
        msg = "The device is not in acquisition mode.";
        return;
      case SenseErrorType.INVALID_PARAMETER:
        msg = "Invalid parameter.";
        return;
      case SenseErrorType.NOT_SUPPORTED:
        msg = "Operation not supported by the device.";
        return;
      case SenseErrorType.UNKNOWN_ERROR:
        msg = "Unknown error.";
        return;
      default:
        msg = "Undefined exception.";
        return;
    }
  }

  String toString() => 'SenseException: $type - $msg';
}
