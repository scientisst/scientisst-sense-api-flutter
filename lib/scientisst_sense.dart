library scientisst_sense;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

part 'frame.dart';
part 'exceptions.dart';

// Bluetooth timeout
const TIMEOUT_IN_SECONDS = 3;

// CRC4 check function
const CRC4TAB = [0, 3, 6, 5, 12, 15, 10, 9, 11, 8, 13, 14, 7, 4, 1, 2];

// ScientISST Sense API modes
enum ApiMode {
  BITALINO, // TODO: not implemented yet
  SCIENTISST,
  JSON, // TODO: not implemented yet
}

int _parseAPI(ApiMode api) {
  if (api == ApiMode.BITALINO)
    return 1;
  else if (api == ApiMode.SCIENTISST)
    return 2;
  else
    return 3;
}

// CHANNELS
// 12 bits
const AI1 = 1;
const AI2 = 2;
const AI3 = 3;
const AI4 = 4;
const AI5 = 5;
const AI6 = 6;
// 24 bits
const AX1 = 7;
const AX2 = 8;

class Sense {
  int _numChs = 0;
  int _sampleRate = 0;
  final List _chs = [null, null, null, null, null, null, null, null];
  final String address;
  BluetoothConnection? _connection;
  final List<int> _buffer = [];
  bool connected = false;
  bool acquiring = false;
  ApiMode _apiMode = ApiMode.BITALINO;
  int _packetSize = 0;

  /// ScientISST Device class
  ///
  /// Parameters
  /// ----------
  /// address : [String]
  ///   The device Bluetooth MAC address ("xx:xx:xx:xx:xx:xx")
  ///
  /// Exceptions
  /// ----------
  /// [INVALID_ADDRESS] : if the address is not valid
  Sense(this.address) {
    // verify given address
    final re = RegExp(
        r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|(?:[0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}|(?:[0-9a-fA-F]{2}){5}[0-9a-fA-F]{2}$');
    if (!re.hasMatch(address))
      throw SenseException(SenseErrorType.INVALID_ADDRESS);
  }

  /// Searches for Bluetooth devices in range
  ///
  /// Parameters
  /// ----------
  /// [void]
  ///
  /// Returns
  /// -------
  /// devices : [List<String>]
  ///   List of found devices addresses
  static Future<List<String>> find() async {
    final List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices
        .where((device) =>
            device.isBonded &&
            device.name!.toLowerCase().contains("scientisst"))
        .map((device) => device.address!)
        .toList();
  }

  /// Connect to the ScientISST device
  ///
  /// Parameters
  /// ----------
  /// [void]
  ///
  /// Returns
  /// -------
  /// [void]
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_FOUND] : if the device was not found or the connection was not established
  Future<void> connect({Function()? onDisconnect}) async {
    _connection = await BluetoothConnection.toAddress(address)
        .timeout(Duration(seconds: TIMEOUT_IN_SECONDS))
        .catchError(
            (_) => throw SenseException(SenseErrorType.DEVICE_NOT_FOUND));
    if (_connection == null)
      throw SenseException(SenseErrorType.CONTACTING_DEVICE_ERROR);
    _connection!.input!.listen((Uint8List data) {
      // add all incoming data to local buffer
      _buffer.addAll(data);
    }).onDone(() async {
      await disconnect();
      if (onDisconnect != null) onDisconnect();
      print('Disconnected by remote request');
    });
    connected = true;
    print("ScientISST Sense: CONNECTED");
  }

  /// Disconnects from a ScientISST device. If an aquisition is running, it is stopped
  ///
  /// Parameters
  /// ----------
  /// [void]
  ///
  /// Returns
  /// -------
  /// [void]
  Future<void> disconnect() async {
    if (connected) {
      if (acquiring) {
        await stop();
        acquiring = false;
      }
      connected = false;
      if (_connection != null) {
        await _connection!.close();
        _connection?.dispose();
        _connection = null;
      }
      // clear buffer
      _clear();
      print("ScientISST Sense: DISCONNECTED");
    }
  }

  /// Gets the device firmware version string
  ///
  /// Parameters
  /// ----------
  /// [void]
  ///
  /// Returns
  /// -------
  /// version : [String]
  ///   Firmware version
  Future<String> version() async {
    final String header = "ScientISST";
    final int headerLen = header.length;

    final int cmd = 0x07;
    await _send(cmd);

    String version = "";
    while (true) {
      final result = await _recv(1);
      if (version.length >= headerLen) {
        if (result.first == 0x00) {
          break;
        } else if (result != utf8.encode("\n")) {
          version += utf8.decode(result);
        }
      } else {
        final char = utf8.decode(result);
        if (char == header[version.length]) {
          version += char;
        } else {
          version = "";
          if (char == header[0]) {
            version += char;
          }
        }
      }
    }

    print("ScientISST version: $version");
    return version;
  }

  /// Starts a signal acquisition from the device.
  ///
  /// Parameters
  /// ----------
  /// sample_rate : [int]
  ///   Sampling rate in Hz. Accepted values are 1, 10, 100 or 1000 Hz.
  /// channels : [List<int>]
  ///   Set of channels to acquire. Accepted channels are 1...6 for inputs A1...A6.
  /// file_name : [String]
  ///   Name of the file where the live mode data will be written into.
  /// simulated : [bool]
  ///   If true, start in simulated mode. Otherwise start in live mode. Default is to start in live mode.
  /// api : [int]
  ///   The API mode, this API supports the ScientISST and JSON APIs.
  ///
  /// Returns
  /// -------
  /// [void]
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_IDLE] : if the device is already in acquisition mode.
  /// [INVALID_PARAMETER] : if no valid API value is chosen or an incorrect array of channels is provided.
  Future<void> start(int sampleRate, List<int> channels,
      {bool simulated = false, ApiMode api = ApiMode.SCIENTISST}) async {
    if (_numChs != 0) throw SenseException(SenseErrorType.DEVICE_NOT_IDLE);

    if (api != ApiMode.SCIENTISST && api != ApiMode.JSON)
      throw SenseException(SenseErrorType.INVALID_PARAMETER);

    _sampleRate = sampleRate;
    _numChs = 0;

    // Change API mode
    await _changeAPI(api);

    // Sample rate
    int sr = int.parse("01000011", radix: 2);
    sr |= _sampleRate << 8;
    await _send(sr);

    int chMask;
    if (channels.isEmpty) {
      // all 8 analog channels
      chMask = 0xFF;
    } else {
      chMask = 0;
      for (int ch in channels) {
        if (ch <= 0 || ch > 8)
          throw SenseException(SenseErrorType.INVALID_PARAMETER);

        // fill chs vector
        _chs[_numChs] = ch;

        final mask = 1 << (ch - 1);
        if (chMask & mask == 1)
          throw SenseException(SenseErrorType.INVALID_PARAMETER);
        chMask |= mask;
        _numChs++;
      }
    }

    // cleanup existing data in bluetooth buffer
    _clear();

    int cmd;

    if (simulated)
      cmd = 0x02;
    else
      cmd = 0x01;

    cmd |= chMask << 8;

    await _send(cmd);

    _packetSize = await _getPacketSize();
    acquiring = true;
  }

  /// Reads acquisition frames from the device.
  /// This method returns when all requested frames are received from the device, or when a timeout occurs.
  ///
  /// Parameters
  /// ----------
  /// num_frames : [int]
  /// Number of frames to retrieve from the device
  ///
  /// Returns
  /// -------
  /// frames : [List<Frame>]
  /// List of Frame objects retrieved from the device
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_IN_ACQUISITION] : if the device is not in acquisition mode.
  /// [NOT_SUPPORTED] : if the device API is in BITALINO mode
  /// [UNKNOWN_ERROR] : if the device stopped sending frames for some unknown reason.
  Future<List<Frame?>> read(int numFrames) async {
    //final bf = List.filled(_packetSize, null);
    final List<Frame?> frames = List.filled(numFrames, null, growable: false);

    if (_numChs == 0)
      throw SenseException(SenseErrorType.DEVICE_NOT_IN_ACQUISITION);

    bool midFrameFlag;
    List<int>? bf;
    Frame f;
    for (int it = 0; it < numFrames; it++) {
      midFrameFlag = false;
      bf = await _recv(_packetSize);

      // if CRC check failed, try to resynchronize with the next valid frame
      while (!_checkCRC4(bf, _packetSize)) {
        bf.replaceRange(0, _packetSize - 1, bf.sublist(1));
        bf.last = -1;

        //  checking with one new byte at a time
        final result = await _recv(1);
        bf[_packetSize - 1] = result.first;

        if (bf.last == -1)
          // a timeout has occurred
          return List<Frame>.from(
              frames.where((Frame? frame) => frame != null));
      }

      f = Frame();
      frames[it] = f;

      if (_apiMode == ApiMode.SCIENTISST) {
        // Get seq number and IO states
        f.seq = bf.last >> 4;
        for (int i = 0; i < 4; i++) {
          f.digital[i] = ((bf[_packetSize - 2] & (0x80 >> i)) != 0);
        }

        // Get channel values
        int currCh;
        int byteIt = 0;
        for (int i = 0; i < _numChs; i++) {
          currCh = _chs[_numChs - 1 - i];
          // If it's an AX channel
          if (currCh == AX1 || currCh == AX2) {
            f.a[currCh - 1] =
                _uint8List2int(bf.sublist(byteIt, byteIt + 4)) & 0xFFFFFF;
            byteIt += 3;
            // If it's an AI channel
          } else {
            if (!midFrameFlag) {
              f.a[currCh - 1] =
                  _uint8List2int(bf.sublist(byteIt, byteIt + 2)) & 0xFFF;
              byteIt += 1;
              midFrameFlag = true;
            } else {
              f.a[currCh - 1] =
                  _uint8List2int(bf.sublist(byteIt, byteIt + 2)) >> 4;
              byteIt += 2;
              midFrameFlag = false;
            }
          }
        }
      } else if (_apiMode == ApiMode.JSON) {
        //
      } else {
        SenseException(SenseErrorType.NOT_SUPPORTED);
      }
    }
    return frames;
  }

  /// Stops a signal acquisition.
  ///
  /// Parameters
  /// ----------
  /// [void]
  ///
  /// Returns
  /// -------
  /// [void]
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_IDLE] : if the device is not in acquisition mode.
  Future<void> stop() async {
    if (_numChs == 0) SenseException(SenseErrorType.DEVICE_NOT_IN_ACQUISITION);

    // 0  0  0  0  0  0  0  0 - Go to idle mode
    final cmd = 0x00;
    await _send(cmd);

    _numChs = 0;
    _sampleRate = 0;
    acquiring = false;

    // Cleanup existing data in bluetooth buffer
    _clear();
  }

  /// Sets the battery voltage threshold for the low-battery LED.
  ///
  /// Parameters
  /// ----------
  /// value : [int]
  ///    Battery voltage threshold. Default value is 0.
  ///    Value | Voltage Threshold
  ///    ----- | -----------------
  ///        0 |   3.4 V
  ///     ...  |   ...
  ///       63 |   3.8 V
  ///
  /// Returns
  /// -------
  /// [void]
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_IDLE] : if the device is in acquisition mode.
  /// [INVALID_PARAMETER] : if an invalid battery threshold value is given.
  Future<void> battery({int value = 0}) async {
    if (_numChs != 0) SenseException(SenseErrorType.DEVICE_NOT_IDLE);
    if (value < 0 || value > 63)
      SenseException(SenseErrorType.INVALID_PARAMETER);

    final cmd = value << 2;
    // <bat threshold> 0 0 - Set battery threshold
    await _send(cmd);
  }

  /// Assigns the digital outputs states.
  ///
  /// Parameters
  /// ----------
  /// digital_output : array
  ///   Vector of booleans to assign to digital outputs, starting at first output (O1).
  ///
  /// Returns
  /// -------
  /// [void]
  ///
  /// Exceptions
  /// ----------
  /// [INVALID_PARAMETER] : if the length of the digital_output array is different from 2.
  Future<void> trigger(List<int> digitalOutput) async {
    final length = digitalOutput.length;

    if (length != 2) throw SenseException(SenseErrorType.INVALID_PARAMETER);

    int cmd = 0xB3; // 1 0 1 1 O2 O1 1 1 - set digital outputs

    for (int i = 0; i < length; i++) {
      if (digitalOutput[i] == 1) cmd |= 4 << i;
    }

    await _send(cmd);
  }

  /// Assigns the analog (PWM) output value (%ScientISST 2 only).
  ///
  /// Parameters
  /// ----------
  /// pwm_output : int
  ///   Analog output value to set (0...255).
  ///
  /// Returns
  /// -------
  /// [void]

  /// Exceptions
  /// ----------
  /// [INVALID_PARAMETER] : if the pwm_output value is outside of its range, 0-255.
  Future<void> dac(int pwmOutput) async {
    if (pwmOutput < 0 || pwmOutput > 255)
      throw SenseException(SenseErrorType.INVALID_PARAMETER);

    int cmd = 0xA3; // 1 0 1 0 0 0 1 1 - Set dac output
    cmd |= pwmOutput << 8;

    await _send(cmd);
  }

  /// Returns current device state (%ScientISST 2 only).
  ///
  /// Parameters
  /// ----------
  /// [void]

  /// Returns
  /// -------
  /// state : [State]
  ///   Current device state
  ///
  /// Exceptions
  /// ----------
  /// [DEVICE_NOT_IDLE] : if the device is in acquisition mode.
  /// [CONTACTING_DEVICE_ERROR] : if there is an error contacting the device.
  state() async {
    // TODO
  }

  ////////////////// PRIVATE ///////////////////////

  bool _checkCRC4(List<int?> data, int length) {
    int crc = 0;
    int? b;
    for (int i = 0; i < length - 1; i++) {
      b = data[i];
      crc = CRC4TAB[crc] ^ (b! >> 4);
      crc = CRC4TAB[crc] ^ (b & 0x0F);
    }

    // CRC for last byte
    crc = CRC4TAB[crc] ^ (data.last! >> 4);
    crc = CRC4TAB[crc];
    return crc == (data.last! & 0x0F);
  }

  Future<int> _getPacketSize() async {
    int packetSize = 0;

    if (_apiMode == ApiMode.SCIENTISST) {
      int numInternActiveChs = 0;
      int numExternActiveChs = 0;

      for (int? ch in _chs as Iterable<int?>) {
        if (ch != null) {
          // Add 24bit channel's contributuion to packet size
          if (ch == AX1 || ch == AX1) {
            numExternActiveChs++;
            // Count 12bit channels
          } else {
            numInternActiveChs++;
          }
        }
      }
      //Add 24bit channel's contributuion to packet size
      packetSize = 3 * numExternActiveChs;

      // Add 12bit channel's contributuion to packet size
      // If it's an even number
      if (numInternActiveChs % 2 == 0) {
        packetSize += (numInternActiveChs * 12) ~/ 8;
      } else {
        // -4 because 4 bits can go in the I/0 byte
        packetSize += ((numInternActiveChs * 12) - 4) ~/ 8;
      }
      // for the I/Os and seq+crc bytes
      packetSize += 2;
    } else {
      SenseException(SenseErrorType.NOT_SUPPORTED);
    }
    return packetSize;
  }

  Future<void> _changeAPI(ApiMode api) async {
    if (_numChs != 0) throw SenseException(SenseErrorType.DEVICE_NOT_IDLE);

    int _api = _parseAPI(api);

    if (_api <= 0 || _api > 3)
      throw SenseException(SenseErrorType.INVALID_PARAMETER);

    _apiMode = api;
    _api <<= 4;
    _api |= int.parse("11", radix: 2);

    await _send(_api);
  }

  /// Clear the bluetooth buffer
  void _clear() {
    _buffer.clear();
  }

  /// Convert [Uint8List] to 32bit [int]
  int _uint8List2int(List<int> list, {String byteOrder = "little"}) {
    assert(byteOrder == "little" || byteOrder == "big");
    int result = 0;
    if (byteOrder == "little") {
      for (int i = 0; i < list.length; i++) {
        result += list[i] << (8 * i);
      }
    } else {
      for (int i = 0; i < list.length; i++) {
        result += list[list.length - 1 - i] << (8 * i);
      }
    }
    return result;
  }

  /// Convert 32bit [int] to [Uint8List]
  Uint8List _int2Uint8List(int value) {
    if (value == 0) return Uint8List.fromList([0]);

    final nrOfBytes = ((log(value) / log(2)) ~/ 8 + 1).floor();
    final Uint8List result = Uint8List(nrOfBytes);
    for (int i = 0; i < nrOfBytes; i++) {
      result[i] = value >> (8 * i) & 0xFF;
    }
    return result;
  }

  /// Send data
  Future<void> _send(int cmd) async {
    final Uint8List _cmd = _int2Uint8List(cmd);
    //print(_cmd.map((int) => int.toRadixString(16).padLeft(2, "0")).toList());
    _connection!.output.add(_cmd);
    await _connection!.output.allSent
        .timeout(Duration(seconds: TIMEOUT_IN_SECONDS))
        .catchError((_) =>
            throw SenseException(SenseErrorType.CONTACTING_DEVICE_ERROR));
  }

  /// Receive data
  Future<List<int>> _recv(int nrOfBytes) async {
    assert(nrOfBytes > 0);
    List<int> data;
    int timeout = TIMEOUT_IN_SECONDS * 1000 ~/ 150;
    while (timeout > 0 && _buffer.length < nrOfBytes) {
      await Future.delayed(Duration(milliseconds: 150));
      timeout--;
    }
    if (_buffer.length >= nrOfBytes) {
      data = _buffer.sublist(0, nrOfBytes);
      _buffer.removeRange(0, nrOfBytes);
    } else {
      throw SenseException(SenseErrorType.CONTACTING_DEVICE_ERROR);
    }
    return data;
  }
}
