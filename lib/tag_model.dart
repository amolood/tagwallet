import 'dart:convert';

/// What the phone can actually do with a scanned tag.
enum EmulateVerdict {
  /// ISO-DEP / Type-4 APDU card — emulatable via Android HCE.
  hceCapable,

  /// 13.56 MHz but identity depends on UID/MIFARE sectors the phone can't spoof.
  partialUidWontMatch,

  /// MIFARE Classic — Android cannot emulate it at all.
  notEmulatable,

  /// Unknown / couldn't classify.
  unknown,
}

extension EmulateVerdictInfo on EmulateVerdict {
  String get label => switch (this) {
        EmulateVerdict.hceCapable => 'HCE-emulatable',
        EmulateVerdict.partialUidWontMatch => 'Partial — UID won\'t match',
        EmulateVerdict.notEmulatable => 'Not emulatable on phone',
        EmulateVerdict.unknown => 'Unknown',
      };

  String get explanation => switch (this) {
        EmulateVerdict.hceCapable =>
          'This is an ISO-DEP / Type-4 (APDU) card. Android HCE can respond to a '
              'reader\'s SELECT for its AID. Works for door systems that authenticate '
              'over APDU rather than checking a fixed UID.',
        EmulateVerdict.partialUidWontMatch =>
          'The phone can talk to this tag, but most readers for it check the card\'s '
              'UID, which Android HCE cannot set. Emulation will likely NOT open the door.',
        EmulateVerdict.notEmulatable =>
          'MIFARE Classic. Android refuses to emulate its UID/sectors. A phone cannot '
              'clone this — you\'d need a Proxmark3 or Flipper Zero (and authorization).',
        EmulateVerdict.unknown =>
          'Could not classify this tag from its reported technologies.',
      };
}

class SavedTag {
  final String id;
  String name;
  final String type; // human label, e.g. "ISO-DEP (Type 4)"
  final String? uid;
  final List<String> technologies;
  final EmulateVerdict verdict;

  /// For HCE-capable tags: the AID a reader will SELECT and the response we serve.
  final String? aid;
  final String? response;

  final int createdAt;

  SavedTag({
    required this.id,
    required this.name,
    required this.type,
    required this.uid,
    required this.technologies,
    required this.verdict,
    this.aid,
    this.response,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'uid': uid,
        'technologies': technologies,
        'verdict': verdict.name,
        'aid': aid,
        'response': response,
        'createdAt': createdAt,
      };

  factory SavedTag.fromJson(Map<String, dynamic> j) => SavedTag(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        uid: j['uid'] as String?,
        technologies: (j['technologies'] as List).cast<String>(),
        verdict: EmulateVerdict.values.firstWhere(
          (v) => v.name == j['verdict'],
          orElse: () => EmulateVerdict.unknown,
        ),
        aid: j['aid'] as String?,
        response: j['response'] as String?,
        createdAt: j['createdAt'] as int,
      );

  bool get canEmulate => verdict == EmulateVerdict.hceCapable && aid != null;
}

String encodeTags(List<SavedTag> tags) =>
    jsonEncode(tags.map((t) => t.toJson()).toList());

List<SavedTag> decodeTags(String s) =>
    (jsonDecode(s) as List).map((e) => SavedTag.fromJson(e as Map<String, dynamic>)).toList();
