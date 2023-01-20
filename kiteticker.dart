import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:collection/collection.dart';

const WSSURL="wss://ws.kite.trade?api_key=:api_key:&access_token=:access_token:";

const MODE_LTP = 'ltp';
const MODE_QUOTE = 'quote';
const MODE_FULL = 'full';

const Map<String, int> EXCHANGE_MAP = {
  "nse": 1,
  "nfo": 2,
  "cds": 3,
  "bse": 4,
  "bfo": 5,
  "bcd": 6,
  "mcx": 7,
  "mcxsx": 8,
  "indices": 9,
  // bsecds is replaced with it's official segment name bcd
  // so,bsecds key will be depreciated in next version
  "bsecds": 6,
};

class KiteTicker {
  late WebSocketChannel _channel;
  late StreamController<dynamic> _streamController;

  KiteTicker({required String apikey,required String accesstoken}) {
    _streamController = StreamController<dynamic>();

    this._channel = WebSocketChannel.connect(
      Uri.parse(WSSURL.replaceFirst(RegExp(r':api_key:'), apikey).replaceFirst(RegExp(r':access_token:'), accesstoken)),
    )..stream.listen((bin) {
        if (!(bin is String)) {
          try {
            var data = _parse_binary(bin);
            if (data.length > 0) {
              _streamController.add(data);
            }
          } catch (e) {
            print(e);
          }
        }
      });
  }

  Stream get stream => _streamController.stream;

  subscribe(List<String> instrumenttoken, {String mode: "full"}) {
    var instrument = instrumenttoken.map((e) => num.parse(e).toInt()).toList();
    var subscribemessage = {"a": "subscribe", "v": instrument};
    _channel.sink.add(jsonEncode(subscribemessage));
    var modemessage = {
      "a": "mode",
      "v": [mode, instrument]
    };
    _channel.sink.add(jsonEncode(modemessage));
  }

  unsubscribe(List<String> instrument) {
    var unsubscribemessage = {"a": "unsubscribe", "v": instrument};
    _channel.sink.add(jsonEncode(unsubscribemessage));
  }

  int _unpack_int(packets, start, end, {bool isheader = false}) {
    Uint8List data = packets.sublist(start, end);
    var bytes = data.buffer.asByteData();
    if (isheader) {
      return bytes.getUint16(0);
    }
    return bytes.getUint32(0);
  }

  List _parse_binary(bin) {
    var packets = _splitPackets(bin);
    List data = [];
    packets.forEach((packet) {
      var instrument_token = _unpack_int(packet, 0, 4);
      var segment = instrument_token & 0xff;
      print(instrument_token);
      print(segment);

      num divisor = 100.0;
      if (segment == EXCHANGE_MAP["cds"])
        divisor = 10000000.0;
      else if (segment == EXCHANGE_MAP["bcd"])
        divisor = 10000.0;
      else
        divisor = 100.0;

      bool tradable = !(segment == EXCHANGE_MAP["indices"]);

      if (packet.length == 8) {
        data.add({
          "tradable": tradable,
          "mode": MODE_LTP,
          "instrument_token": instrument_token,
          "last_price": _unpack_int(packet, 4, 8) / divisor
        });
      }
      //Indices quote and full mode
      else if ((packet.length == 28) || (packet.length == 32)) {
        var mode = (packet.length == 28) ? MODE_QUOTE : MODE_FULL;

        Map<String, dynamic> d = {
          "tradable": tradable,
          "mode": mode,
          "instrument_token": instrument_token,
          "last_price": _unpack_int(packet, 4, 8) / divisor,
          "ohlc": {
            "high": _unpack_int(packet, 8, 12) / divisor,
            "low": _unpack_int(packet, 12, 16) / divisor,
            "open": _unpack_int(packet, 16, 20) / divisor,
            "close": _unpack_int(packet, 20, 24) / divisor
          }
        };

        // Compute the change price using close price and last price
        d["change"] = 0;
        if (d["ohlc"]["close"] != 0)
          d["change"] =
              (d["last_price"] - d["ohlc"]["close"]) * 100 / d["ohlc"]["close"];

        // Full mode with timestamp
        if (packet.length == 32) {
          var timestamp;
          try {
            timestamp = (_unpack_int(packet, 28, 32) + 19800) * 1000;
          } catch (_) {
            timestamp = null;
          }

          d["exchange_timestamp"] = timestamp;
        }

        data.add(d);
      }
      // for ()

      else if ((packet.length == 44) || (packet.length == 184)) {
        var mode = packet.length == 44 ? MODE_QUOTE : MODE_FULL;

        Map<String, dynamic> d = {
          "tradable": tradable,
          "mode": mode,
          "instrument_token": instrument_token,
          "last_price": _unpack_int(packet, 4, 8) / divisor,
          "last_quantity": _unpack_int(packet, 8, 12),
          "average_price": _unpack_int(packet, 12, 16) / divisor,
          "volume": _unpack_int(packet, 16, 20),
          "buy_quantity": _unpack_int(packet, 20, 24),
          "sell_quantity": _unpack_int(packet, 24, 28),
          "ohlc": {
            "open": _unpack_int(packet, 28, 32) / divisor,
            "high": _unpack_int(packet, 32, 36) / divisor,
            "low": _unpack_int(packet, 36, 40) / divisor,
            "close": _unpack_int(packet, 40, 44) / divisor
          }
        };

        // Compute the change price using close price and last price
        d["change"] = 0;
        if (d["ohlc"]["close"] != 0)
          d["change"] =
              (d["last_price"] - d["ohlc"]["close"]) * 100 / d["ohlc"]["close"];

        // Parse full mode
        if (packet.length == 184) {
          var last_trade_time;
          try {
            last_trade_time = (_unpack_int(packet, 44, 48) + 19800) * 1000;
          } catch (_) {
            last_trade_time = null;
          }
          var timestamp;

          try {
            timestamp = (_unpack_int(packet, 60, 64) + 19800) * 1000;
          } catch (_) {
            timestamp = null;
          }

          d["last_trade_time"] = last_trade_time;
          d["oi"] = _unpack_int(packet, 48, 52);
          d["oi_day_high"] = _unpack_int(packet, 52, 56);
          d["oi_day_low"] = _unpack_int(packet, 56, 60);
          d["exchange_timestamp"] = timestamp;

          // Market depth entries.
          Map<String, dynamic> depth = {"buy": [], "sell": []};
          print("hi");
          // Compile the market depth lists.
          Iterable<int>.generate(((packet.length - 64) / 12).toInt(),
              ((index) => (index * 12 + 64).toInt())).forEachIndexed((i, p) {
            depth[i >= 5 ? "sell" : "buy"].add({
              "quantity": _unpack_int(packet, p, p + 4),
              "price": _unpack_int(packet, p + 4, p + 8) / divisor,
              "orders": _unpack_int(packet, p + 8, p + 10, isheader: true)
            });
          });

          d["depth"] = depth;
        }

        data.add(d);
      }
    });

    print(data);
    return data;
  }

  _splitPackets(bin) {
    if (bin.length < 2) return [];
    int number_of_packets = _unpack_int(bin, 0, 2, isheader: true);
    List packets = [];

    int j = 2;
    Iterable<int>.generate(number_of_packets).toList().forEach((e) {
      int packet_length = _unpack_int(bin, j, j + 2, isheader: true);
      packets.add(bin.sublist(j + 2, j + 2 + packet_length));
      j = j + 2 + packet_length;
    });

    return packets; // if (bin.length < 2) return [];
  }

  void dispose() {
    _channel.sink.close();
    _streamController.sink.close();
  }
}
