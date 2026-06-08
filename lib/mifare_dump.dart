import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

/// Common default MIFARE Classic keys. Many access fobs never change these.
/// Only meaningful for cards you are authorized to dump.
const List<String> kDefaultKeys = [
  'FFFFFFFFFFFF',
  'A0A1A2A3A4A5',
  'D3F7D3F7D3F7',
  '000000000000',
  'B0B1B2B3B4B5',
  '4D3A99C351DD',
  '1A982C7E459A',
  'AABBCCDDEEFF',
  '714C5C886E97',
  '587EE5F9350F',
  'A0478CC39091',
  '533CB6C723F6',
  '8FD0A4F256E9',
];

class SectorDump {
  final int sector;
  final bool authenticated;
  final String? keyUsed; // hex of the key that worked (A side)
  final List<String> blocks; // hex per block, or "??" if unreadable
  SectorDump(this.sector, this.authenticated, this.keyUsed, this.blocks);
}

class ClassicDump {
  final String uid;
  final int sectorCount;
  final List<SectorDump> sectors;
  ClassicDump(this.uid, this.sectorCount, this.sectors);

  int get readableSectors => sectors.where((s) => s.authenticated).length;

  /// Flat 16-byte-per-line hex dump (Proxmark-style), '?' for unreadable bytes.
  String toHexDump() {
    final b = StringBuffer();
    for (final s in sectors) {
      for (final blk in s.blocks) {
        b.writeln(blk);
      }
    }
    return b.toString();
  }
}

/// Dumps a MIFARE Classic tag using default keys. Must be called inside an
/// active session (after poll, before finish). [tag] is the polled tag.
class MifareDumper {
  Future<ClassicDump> dump(NFCTag tag) async {
    final info = tag.mifareInfo;
    // Derive sector count: prefer reported sectorCount, else infer from size.
    final sectorCount = info?.sectorCount ??
        _inferSectorCount(info?.size ?? 1024);
    final sectors = <SectorDump>[];

    for (var sec = 0; sec < sectorCount; sec++) {
      String? workingKey;
      for (final key in kDefaultKeys) {
        final ok = await FlutterNfcKit.authenticateSector<String>(sec, keyA: key);
        if (ok) {
          workingKey = key;
          break;
        }
      }
      if (workingKey == null) {
        sectors.add(SectorDump(sec, false, null,
            List.filled(_blocksInSector(sec), '?? unreadable')));
        continue;
      }
      // Authenticated: read each block in the sector.
      final firstBlock = _firstBlockOfSector(sec);
      final n = _blocksInSector(sec);
      final blocks = <String>[];
      for (var i = 0; i < n; i++) {
        try {
          final data = await FlutterNfcKit.readBlock(firstBlock + i);
          blocks.add(_hex(data));
        } catch (_) {
          blocks.add('?? read error');
        }
      }
      sectors.add(SectorDump(sec, true, workingKey, blocks));
    }
    return ClassicDump(tag.id, sectorCount, sectors);
  }

  // MIFARE Classic 1K: 16 sectors x 4 blocks. 4K: first 32 sectors x4, last 8 x16.
  int _inferSectorCount(int size) => size >= 4096 ? 40 : 16;

  int _blocksInSector(int sector) => sector < 32 ? 4 : 16;

  int _firstBlockOfSector(int sector) {
    if (sector < 32) return sector * 4;
    return 128 + (sector - 32) * 16;
  }

  String _hex(Uint8List d) =>
      d.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}
