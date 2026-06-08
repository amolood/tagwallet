import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'tag_model.dart';
import 'mifare_dump.dart';
import 'ndef_ops.dart';

/// Wraps tag reading/classification and the native HCE channel.
class NfcService {
  static const _channel = MethodChannel('tagwallet/hce');

  /// "enabled" | "disabled" | "absent"
  Future<String> nfcStatus() async {
    try {
      return await _channel.invokeMethod<String>('nfcStatus') ?? 'absent';
    } on PlatformException {
      return 'absent';
    }
  }

  Future<NFCAvailability> kitAvailability() => FlutterNfcKit.nfcAvailability;

  /// Polls for one tag and classifies it. Caller should run within a try/finally
  /// that calls [finish].
  Future<ScanResult> scanOnce() async {
    final tag = await FlutterNfcKit.poll(
      timeout: const Duration(seconds: 12),
      iosAlertMessage: 'Hold your tag near the phone',
    );

    final techs = <String>[];
    // flutter_nfc_kit reports a normalized type + transport hints.
    techs.add('type: ${tag.type.name}');
    if (tag.standard.isNotEmpty) techs.add('standard: ${tag.standard}');
    if (tag.atqa != null && tag.atqa!.isNotEmpty) techs.add('ATQA: ${tag.atqa}');
    if (tag.sak != null && tag.sak!.isNotEmpty) techs.add('SAK: ${tag.sak}');
    if (tag.historicalBytes != null && tag.historicalBytes!.isNotEmpty) {
      techs.add('hist: ${tag.historicalBytes}');
    }
    if (tag.ndefAvailable == true) techs.add('NDEF present');

    final verdict = _classify(tag);
    final typeLabel = _typeLabel(tag);

    return ScanResult(
      uid: tag.id,
      type: typeLabel,
      technologies: techs,
      verdict: verdict,
      ndefAvailable: tag.ndefAvailable ?? false,
    );
  }

  Future<void> finish({String? alert, String? error}) async {
    try {
      await FlutterNfcKit.finish(iosAlertMessage: alert, iosErrorMessage: error);
    } catch (_) {}
  }

  EmulateVerdict _classify(NFCTag tag) {
    final t = tag.type;
    // ISO 14443-4 / ISO-DEP exposes APDU — the one thing HCE can stand in for.
    if (t == NFCTagType.iso7816 || t == NFCTagType.iso15693) {
      return EmulateVerdict.hceCapable;
    }
    if (t == NFCTagType.mifare_classic) {
      return EmulateVerdict.notEmulatable;
    }
    if (t == NFCTagType.mifare_ultralight ||
        t == NFCTagType.mifare_desfire ||
        t == NFCTagType.mifare_plus) {
      // Type-2/DESFire/Plus: phone can read; readers usually key off UID/crypto HCE can't match.
      return EmulateVerdict.partialUidWontMatch;
    }
    // Has APDU transport even if generic?
    if (tag.standard.contains('14443-4')) return EmulateVerdict.hceCapable;
    return EmulateVerdict.unknown;
  }

  String _typeLabel(NFCTag tag) => switch (tag.type) {
        NFCTagType.iso7816 => 'ISO-DEP / Type-4 (APDU)',
        NFCTagType.mifare_classic => 'MIFARE Classic',
        NFCTagType.mifare_ultralight => 'MIFARE Ultralight (Type 2)',
        NFCTagType.mifare_desfire => 'MIFARE DESFire',
        NFCTagType.iso15693 => 'ISO 15693 (vicinity)',
        NFCTagType.iso18092 => 'ISO 18092 / FeliCa',
        NFCTagType.mifare_plus => 'MIFARE Plus',
        _ => 'Unknown (${tag.type.name})',
      };

  /// Poll a MIFARE Classic tag and dump it with default keys. Self-manages session.
  Future<ClassicDump> dumpClassic() async {
    final tag = await FlutterNfcKit.poll(
      timeout: const Duration(seconds: 12),
      iosAlertMessage: 'Hold the MIFARE Classic card',
    );
    try {
      if (tag.type != NFCTagType.mifare_classic) {
        throw 'Not a MIFARE Classic tag (got ${tag.type.name}).';
      }
      return await MifareDumper().dump(tag);
    } finally {
      await finish(alert: 'Dump done');
    }
  }

  /// Poll any tag and read its NDEF. Self-manages session.
  Future<NdefRead> readNdef() async {
    final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 12));
    try {
      return await NdefOps().read(tag);
    } finally {
      await finish(alert: 'NDEF read');
    }
  }

  /// Poll a writable tag and write the given NDEF records (clone target).
  Future<void> writeNdef(List<ndef.NDEFRecord> records) async {
    await FlutterNfcKit.poll(timeout: const Duration(seconds: 12));
    try {
      await NdefOps().write(records);
    } finally {
      await finish(alert: 'Written');
    }
  }

  // ---- HCE control ----

  Future<bool> setActiveTag(SavedTag t) async {
    if (!t.canEmulate) return false;
    final ok = await _channel.invokeMethod<bool>('setActiveTag', {
      'aid': t.aid,
      'response': t.response ?? '',
    });
    return ok ?? false;
  }

  Future<void> clearActiveTag() => _channel.invokeMethod('clearActiveTag');
}

class ScanResult {
  final String uid;
  final String type;
  final List<String> technologies;
  final EmulateVerdict verdict;
  final bool ndefAvailable;

  ScanResult({
    required this.uid,
    required this.type,
    required this.technologies,
    required this.verdict,
    required this.ndefAvailable,
  });
}
