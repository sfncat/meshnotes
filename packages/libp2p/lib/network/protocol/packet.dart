import 'dart:convert';

import 'frame.dart';
import 'util.dart';

enum PacketType {
  connect,    // initialize connect from client
  connectAck, // response connect_ack from server
  connected,  // response connected from client, connection established
  data,       // send data frames
  announce,   // broadcast
  announceAck,  // broadcast ack
  bye,        // close a connection
  invalid,
}

class PacketHeader {
  PacketType type;
  int destConnectionId;
  int packetNumber;

  PacketHeader({
    required this.type,
    required this.destConnectionId,
    required this.packetNumber,
  });

  factory PacketHeader.fromBytes(List<int> bytes) {
    int _typeInt = buildBytes32(bytes, 0);
    int destConnectionId = buildBytes32(bytes, 4);
    int packetNumber = buildBytes32(bytes, 8);
    PacketType type = PacketType.invalid;
    if(_typeInt >= 0 && _typeInt < PacketType.values.length) {
      type = PacketType.values[_typeInt];
    }
    return PacketHeader(type: type, destConnectionId: destConnectionId, packetNumber: packetNumber);
  }

  void fillBytes(List<int> list) {
    if(list.length < getLength()) {
      return;
    }
    fillBytes32(list, 0, type.index);
    fillBytes32(list, 4, destConnectionId);
    fillBytes32(list, 8, packetNumber);
  }

  static int getLength() {
    return 4 + 4 + 4;
  }
}

/// Abstract class for sending and resending packets
abstract class Packet {
  PacketHeader header;

  Packet({required this.header});

  PacketType getType() {
    return header.type;
  }

  void setPacketNumber(int number) {
    header.packetNumber = number;
  }

  int getPacketNumber() {
    return header.packetNumber;
  }

  List<int> toBytes();
}

/// Packet implementation for connect/connect_ack/connected message
class PacketConnect extends Packet {
  int sourceConnectionId;

  PacketConnect({
    required super.header,
    required this.sourceConnectionId,
  });

  factory PacketConnect.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    var connectionId = buildBytes32(bytes, PacketHeader.getLength());
    return PacketConnect(sourceConnectionId: connectionId, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    fillBytes32(result, PacketHeader.getLength(), sourceConnectionId);
    return result;
  }

  static int getLength() {
    return PacketHeader.getLength() + 4;
  }
}

/// Packet implementation for data message
class PacketData extends Packet {
  List<Frame> frames;

  PacketData({
    required this.frames,
    required super.header,
  });

  factory PacketData.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    final data = bytes.sublist(PacketHeader.getLength());
    var parser = FrameParser(data: data);
    final frames = parser.parse();
    return PacketData(frames: frames, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    int t = PacketHeader.getLength();
    for(var frame in frames) {
      var bytes = frame.toBytes();
      final len = bytes.length;
      result.setRange(t, t + len, bytes);
      t += len;
    }
    return result;
  }

  int getLength() {
    int result = PacketHeader.getLength();
    for(var frame in frames) {
      result += frame.getLength();
    }
    return result;
  }
}

/// Packet implementation for hello message
/// +---------------+
/// | header        |
/// +---------------+
/// | IP(4)         |
/// +---------------+
/// | port(2)       |
/// +---------------+
/// | deviceId      |
/// +---------------+
class PacketAnnounce extends Packet {
  int address;
  int port;
  String deviceId;

  PacketAnnounce({
    required this.address,
    required this.port,
    required this.deviceId,
    required super.header,
  });

  factory PacketAnnounce.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    int start = PacketHeader.getLength();
    int address = buildBytes32(bytes, start);
    start += 4;
    int port = buildBytes16(bytes, start);
    start += 2;
    String deviceId = utf8.decode(bytes.sublist(start));
    return PacketAnnounce(address: address, port: port, deviceId: deviceId, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    int start = PacketHeader.getLength();
    fillBytes32(result, start, address);
    start += 4;
    fillBytes16(result, start, port);
    start += 2;
    var bytes = utf8.encode(deviceId);
    result.setRange(start, start + bytes.length, bytes);
    return result;
  }

  int getLength() {
    int headerLength = PacketHeader.getLength();
    int deviceIdLength = utf8.encode(deviceId).length;
    return headerLength + 4 + 2 + deviceIdLength; // IP(4) + port(2) + deviceId
  }

  static bool isValid(List<int> data) {
    int headerLength = PacketHeader.getLength();
    return data.length > headerLength + 4 + 2;
  }
}

/// Packet implementation for bye message
/// +---------------+
/// | header        |
/// +---------------+
/// | tag(4)        |
/// +---------------+
class PacketBye extends Packet {
  int tag;
  static const tagBye = 0;
  static const tagByeAck = 1;
  PacketBye({
    required this.tag,
    required super.header,
  });

  factory PacketBye.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    int start = PacketHeader.getLength();
    int tag = buildBytes32(bytes, start);
    return PacketBye(tag: tag, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    int start = PacketHeader.getLength();
    fillBytes32(result, start, tag);
    return result;
  }

  int getLength() {
    int headerLength = PacketHeader.getLength();
    return headerLength + 4;
  }

  static bool isValid(List<int> data) {
    int headerLength = PacketHeader.getLength();
    return data.length == headerLength + 4;
  }
}

class PacketFactory {
  List<int> data;
  int _type;

  PacketFactory({required this.data}): _type = buildBytes32(data, 0);

  /// Check whether packet data is valid, based on the packet type and data length
  bool isValid() {
    if(_type < 0 || _type >= PacketType.values.length) {
      return false;
    }
    var packetType = PacketType.values[_type];
    int length = data.length;
    switch(packetType) {
      case PacketType.connect:
      case PacketType.connectAck:
      case PacketType.connected:
        return length == PacketConnect.getLength();
      case PacketType.data:
        return true;
      case PacketType.announce:
      case PacketType.announceAck:
        return PacketAnnounce.isValid(data);
      case PacketType.bye:
        return PacketBye.isValid(data);
      case PacketType.invalid:
        return false;
    }
  }

  PacketType getType() {
    if(!isValid()) {
      return PacketType.invalid;
    }
    return PacketType.values[_type];
  }

  PacketConnect getPacketConnect() {
    return PacketConnect.fromBytes(data);
  }

  PacketData getPacketData() {
    return PacketData.fromBytes(data);
  }

  PacketAnnounce getPacketAnnounce() {
    return PacketAnnounce.fromBytes(data);
  }

  PacketBye getPacketBye() {
    return PacketBye.fromBytes(data);
  }

  Packet? getAbstractPacket() {
    final type = getType();
    switch(type) {
      case PacketType.connect:
      case PacketType.connectAck:
      case PacketType.connected:
        return getPacketConnect();
      case PacketType.data:
        return getPacketData();
      case PacketType.announce:
        return getPacketAnnounce();
      case PacketType.announceAck:
        return getPacketAnnounce();
      case PacketType.bye:
        return getPacketBye();
      case PacketType.invalid:
        return null;
    }
  }
}