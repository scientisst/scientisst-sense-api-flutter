library scientisst_sense;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

const TIMEOUT_IN_SECONDS = 3;

enum ApiMode {
  BITALINO,
  SCIENTISST,
  JSON,
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
const AI1 = 1;
const AI2 = 2;
const AI3 = 3;
const AI4 = 4;
const AI5 = 5;
const AI6 = 6;
const AX1 = 7;
const AX2 = 8;

class Sense {
  int _numChs = 0;
  int _sampleRate;
  final List _chs = [null, null, null, null, null, null, null, null];
  final String address;
  BluetoothConnection _connection;
  final List<int> _buffer = [];
  bool _connected = false;
  ApiMode _apiMode = ApiMode.BITALINO;
  int _packetSize;

  Sense(this.address);

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
    _connection = await BluetoothConnection.toAddress(address);
    _connection.input.listen((Uint8List data) {
      debugPrint('Data incoming: $data');
      _buffer.addAll(data);
    }).onDone(() {
      disconnect();
      print('Disconnected by remote request');
    });
    _connected = true;
    print("ScientISST Sense: CONNECTED");
  }

  Future<void> disconnect() async {
    if (_connected) {
      _connected = false;
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
    if (_numChs != 0) {
      return;
    }

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
        if (ch < 0 || ch > 8) {
          return;
        }
        _chs[_numChs] = ch;

        final mask = 1 << (ch - 1);
        if (chMask & mask == 1) {
          return;
        }
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

    _packetSize = _getPacketSize();
  }

  ////////////////// PRIVATE ///////////////////////

  Future<void> _changeAPI(ApiMode api) async {
    if (_numChs != 0) return;

    _apiMode = api;
    int _api = _parseAPI(api);
    _api <<= 4;
    _api |= int.parse("11", radix: 2);

    await _send(_api);
  }

  int _getPacketSize() {
    return 0;
  }

  void _clear() {
    _buffer.clear();
  }

  Uint8List _int2Uint8List(int value) {
    final nrOfBytes = ((log(value) / log(2)) ~/ 8 + 1).floor();
    final Uint8List result = Uint8List(nrOfBytes);
    for (int i = 0; i < nrOfBytes; i++) {
      result[i] = value >> (8 * i) & 0xFF;
    }
    return result;
  }

  Future<void> _send(int cmd) async {
    final Uint8List _cmd = _int2Uint8List(cmd);
    print(_cmd.map((int) => int.toRadixString(16).padLeft(2, "0")).toList());
    _connection.output.add(_cmd);
    await _connection.output.allSent;
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
    }
    return data;
  }
}
