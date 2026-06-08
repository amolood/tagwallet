import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'tag_model.dart';

/// Simple JSON-file-backed store for saved tags. No code-gen, easy to inspect.
class TagStore {
  List<SavedTag> _tags = [];
  List<SavedTag> get tags => List.unmodifiable(_tags);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tags.json');
  }

  Future<void> load() async {
    final f = await _file();
    if (await f.exists()) {
      final s = await f.readAsString();
      if (s.trim().isNotEmpty) _tags = decodeTags(s);
    }
  }

  Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(encodeTags(_tags));
  }

  Future<void> add(SavedTag t) async {
    _tags.add(t);
    await _save();
  }

  Future<void> remove(String id) async {
    _tags.removeWhere((t) => t.id == id);
    await _save();
  }

  Future<void> rename(String id, String name) async {
    final t = _tags.firstWhere((t) => t.id == id);
    t.name = name;
    await _save();
  }
}
