import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

/// Read and write NDEF messages. Clone = read from one tag, hold a blank
/// writable NTAG, write the same records. Only do this with tags you own.
class NdefOps {
  /// Reads NDEF records from a tag in the current session. Returns raw payloads
  /// as a human summary plus the records for re-writing.
  Future<NdefRead> read(NFCTag tag) async {
    if (tag.ndefAvailable != true) {
      return NdefRead(records: const [], summary: 'No NDEF data on this tag.');
    }
    final records = await FlutterNfcKit.readNDEFRecords(cached: false);
    final lines = <String>[];
    for (final r in records) {
      lines.add(_describe(r));
    }
    return NdefRead(
      records: records,
      summary: lines.isEmpty ? 'Empty NDEF.' : lines.join('\n'),
    );
  }

  /// Writes the given records to the tag in the current session.
  Future<void> write(List<ndef.NDEFRecord> records) async {
    await FlutterNfcKit.writeNDEFRecords(records);
  }

  String _describe(ndef.NDEFRecord r) {
    if (r is ndef.UriRecord) return 'URI: ${r.uriString}';
    if (r is ndef.TextRecord) return 'Text(${r.language}): ${r.text}';
    final tnf = r.tnf;
    final type = r.type == null ? '' : String.fromCharCodes(r.type!);
    final len = r.payload?.length ?? 0;
    return 'Record tnf=$tnf type=$type payload=${len}B';
  }
}

class NdefRead {
  final List<ndef.NDEFRecord> records;
  final String summary;
  NdefRead({required this.records, required this.summary});

  bool get isEmpty => records.isEmpty;
}
