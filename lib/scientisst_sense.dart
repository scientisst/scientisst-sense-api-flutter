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
  BITALINO, // not implemented yet
  SCIENTISST,
  JSON, // not implemented yet
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
  BluetoothConnection _connection;
  final List<int> _buffer = [];
  bool connected = false;
  bool acquiring = false;
  ApiMode _apiMode = ApiMode.BITALINO;
  int _packetSize;

  Sense(this.address) {
    final re = RegExp(
        r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|(?:[0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}|(?:[0-9a-fA-F]{2}){5}[0-9a-fA-F]{2}$');
    if (!re.hasMatch(address))
      throw SenseException(SenseErrorType.INVALID_ADDRESS);
  }

  /// Searches for Bluetooth devices in range
  static Future<List<String>> find() async {
    final List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices
        .where((device) =>
            device.isBonded && device.name.toLowerCase().contains("scientisst"))
        .map((device) => device.address)
        .toList();
  }

  Future<void> connect() async {
    _connection = await BluetoothConnection.toAddress(address)
        .timeout(Duration(seconds: TIMEOUT_IN_SECONDS))
        .catchError(
            (_) => throw SenseException(SenseErrorType.DEVICE_NOT_FOUND));
    _connection.input.listen((Uint8List data) {
      //debugPrint('Data incoming: $data');
      _buffer.addAll(data);
    }).onDone(() {
      disconnect();
      print('Disconnected by remote request');
    });
    connected = true;
    print("ScientISST Sense: CONNECTED");
  }

  Future<void> disconnect() async {
    if (connected) {
      acquiring = false;
      connected = false;
      if (_connection != null) {
        await _connection.close();
        _connection?.dispose();
        _connection = null;
      }
      _clear();
      print("ScientISST Sense: DISCONNECTED");
    }
  }

  Future<String> version() async {
    final String header = "ScientISST";
    final int headerLen = header.length;

    final int cmd = 0x07;
    await _send(cmd);

    String version = "";
    while (true) {
      final result = await _recv(1);
      if (result != null) {
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
      } else {
        return null;
      }
    }

    print("ScientISST version: $version");
    return version;
  }

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
      chMask = 0xFF;
    } else {
      chMask = 0;
      for (int ch in channels) {
        if (ch < 0 || ch > 8)
          throw SenseException(SenseErrorType.INVALID_PARAMETER);

        _chs[_numChs] = ch;

        final mask = 1 << (ch - 1);
        if (chMask & mask == 1)
          throw SenseException(SenseErrorType.INVALID_PARAMETER);
        chMask |= mask;
        _numChs++;
      }
    }
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

  Future<List<Frame>> read(int numFrames) async {
    //final bf = List.filled(_packetSize, null);
    final List<Frame> frames = List.filled(numFrames, null, growable: false);

    if (_numChs == 0)
      throw SenseException(SenseErrorType.DEVICE_NOT_IN_ACQUISITION);

    bool midFrameFlag;
    List<int> bf;
    Frame f;
    for (int it = 0; it < numFrames; it++) {
      midFrameFlag = false;
      bf = await _recv(_packetSize);
      if (bf == null)
        throw SenseException(SenseErrorType.UNKNOWN_ERROR,
            "Esp stopped sending frames -> It stopped live mode on its own \n(probably because it can't handle this number of channels + sample rate)");

      while (!_checkCRC4(bf, _packetSize)) {
        bf.replaceRange(0, _packetSize - 1, bf.sublist(1));
        bf.last = null;

        final result = await _recv(1);
        bf[_packetSize - 1] = result.first;

        if (bf.last == null)
          return List<Frame>.from(frames.where((Frame frame) => frame != null));
      }

      f = Frame();
      frames[it] = f;

      if (_apiMode == ApiMode.SCIENTISST) {
        f.seq = bf.last >> 4;
        for (int i = 0; i < 4; i++) {
          f.digital[i] = ((bf[_packetSize - 2] & (0x80 >> i)) != 0);
        }

        // Get channel values
        int currCh;
        int byteIt = 0;
        for (int i = 0; i < _numChs; i++) {
          currCh = _chs[_numChs - 1 - i];
          if (currCh == AX1 || currCh == AX2) {
            f.a[currCh - 1] =
                _uint8List2int(bf.sublist(byteIt, byteIt + 4)) & 0xFFFFFF;
            byteIt += 3;
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
      } else {
        SenseException(SenseErrorType.NOT_SUPPORTED);
      }
    }
    return frames;
  }

  Future<void> stop() async {
    if (_numChs == 0) SenseException(SenseErrorType.DEVICE_NOT_IN_ACQUISITION);

    final cmd = 0x00;
    await _send(cmd);

    _numChs = 0;
    _sampleRate = 0;
    acquiring = false;

    _clear();
  }

  Future<void> battery({int value = 0}) async {
    if (_numChs != 0) SenseException(SenseErrorType.DEVICE_NOT_IDLE);
    if (value < 0 || value > 63)
      SenseException(SenseErrorType.INVALID_PARAMETER);

    final cmd = value << 2;
    await _send(cmd);
  }

  Future<void> trigger(List<int> digitalOutput) async {
    final length = digitalOutput.length;

    if (length != 2) throw SenseException(SenseErrorType.INVALID_PARAMETER);

    int cmd = 0xB3; // 1 0 1 1 O2 O1 1 1 - set digital outputs

    for (int i = 0; i < length; i++) {
      if (digitalOutput[i] == 1) cmd |= 4 << i;
    }

    await _send(cmd);
  }

  Future<void> dac(int pwmOutput) async {
    if (pwmOutput < 0 || pwmOutput > 255)
      throw SenseException(SenseErrorType.INVALID_PARAMETER);

    int cmd = 0xA3; // 1 0 1 0 0 0 1 1 - Set dac output
    cmd |= pwmOutput << 8;

    await _send(cmd);
  }

  state() async {
    // TODO
  }

  ////////////////// PRIVATE ///////////////////////

  bool _checkCRC4(List<int> data, int length) {
    int crc = 0;
    int b;
    for (int i = 0; i < length - 1; i++) {
      b = data[i];
      crc = CRC4TAB[crc] ^ (b >> 4);
      crc = CRC4TAB[crc] ^ (b & 0x0F);
    }

    crc = CRC4TAB[crc] ^ (data.last >> 4);
    crc = CRC4TAB[crc];
    return crc == (data.last & 0x0F);
  }

  Future<int> _getPacketSize() async {
    int packetSize = 0;

    if (_apiMode == ApiMode.SCIENTISST) {
      int numInternActiveChs = 0;
      int numExternActiveChs = 0;

      for (int ch in _chs) {
        if (ch != null) {
          // Add 24bit channel's contributuion to packet size
          if (ch == AX1 || ch == AX1) {
            numExternActiveChs++;
          } else {
            numInternActiveChs++;
          }
        }
      }
      //Add 24bit channel's contributuion to packet size
      packetSize = 3 * numExternActiveChs;

      if (numInternActiveChs % 2 == 0) {
        packetSize += (numInternActiveChs * 12) ~/ 8;
      } else {
        packetSize += ((numInternActiveChs * 12) - 4) ~/ 8;
      }
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

  void _clear() {
    _buffer.clear();
  }

  int _uint8List2int(var list, {String byteOrder = "little"}) {
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

  Uint8List _int2Uint8List(int value) {
    if (value == 0) return Uint8List.fromList([0]);

    final nrOfBytes = ((log(value) / log(2)) ~/ 8 + 1).floor();
    final Uint8List result = Uint8List(nrOfBytes);
    for (int i = 0; i < nrOfBytes; i++) {
      result[i] = value >> (8 * i) & 0xFF;
    }
    return result;
  }

  Future<void> _send(int cmd) async {
    final Uint8List _cmd = _int2Uint8List(cmd);
    //print(_cmd.map((int) => int.toRadixString(16).padLeft(2, "0")).toList());
    _connection.output.add(_cmd);
    await _connection.output.allSent
        .timeout(Duration(seconds: TIMEOUT_IN_SECONDS))
        .catchError((_) =>
            throw SenseException(SenseErrorType.CONTACTING_DEVICE_ERROR));
  }

  Future<List<int>> _recv(int nrOfBytes) async {
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
