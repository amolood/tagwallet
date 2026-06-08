import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'tag_model.dart';
import 'tag_store.dart';
import 'nfc_service.dart';
import 'exporters.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keep the native splash up until the first frame is ready.
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  runApp(const TagWalletApp());
}

class TagWalletApp extends StatelessWidget {
  const TagWalletApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TagWallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = TagStore();
  final _nfc = NfcService();
  String _nfcStatus = '...';
  String? _activeTagId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _store.load();
    final status = await _nfc.nfcStatus();
    setState(() {
      _nfcStatus = status;
      _loading = false;
    });
    FlutterNativeSplash.remove();
  }

  Color get _statusColor => switch (_nfcStatus) {
        'enabled' => Colors.green,
        'disabled' => Colors.orange,
        _ => Colors.red,
      };

  String get _statusText => switch (_nfcStatus) {
        'enabled' => 'NFC on',
        'disabled' => 'NFC off — enable it in settings',
        'absent' => 'No NFC hardware',
        _ => _nfcStatus,
      };

  Future<void> _scan() async {
    final result = await showDialog<ScanResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScanDialog(nfc: _nfc),
    );
    if (result == null || !mounted) return;
    await _showClassifyAndSave(result);
  }

  Future<void> _showClassifyAndSave(ScanResult r) async {
    final nameCtrl = TextEditingController();
    final aidCtrl = TextEditingController(text: 'F0010203040506');
    final respCtrl = TextEditingController();
    final canHce = r.verdict == EmulateVerdict.hceCapable;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16, right: 16, top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.type, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('UID: ${r.uid}', style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 12),
              _VerdictBanner(verdict: r.verdict),
              const SizedBox(height: 12),
              ...r.technologies.map((t) => Text('• $t', style: const TextStyle(fontSize: 12))),
              const Divider(height: 24),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name (e.g. "Office door")'),
              ),
              if (canHce) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: aidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'AID (hex) the reader SELECTs',
                    helperText: 'Default is a safe proprietary AID. Set the real one if known.',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: respCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Response payload (hex, optional)',
                    helperText: 'Bytes returned after SELECT (before 9000).',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save to wallet'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    final tag = SavedTag(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: nameCtrl.text.trim().isEmpty ? r.type : nameCtrl.text.trim(),
      type: r.type,
      uid: r.uid,
      technologies: r.technologies,
      verdict: r.verdict,
      aid: canHce ? aidCtrl.text.trim() : null,
      response: canHce ? respCtrl.text.trim() : null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.add(tag);
    setState(() {});
  }

  Future<void> _toggleEmulate(SavedTag t) async {
    if (_activeTagId == t.id) {
      await _nfc.clearActiveTag();
      setState(() => _activeTagId = null);
      return;
    }
    final ok = await _nfc.setActiveTag(t);
    if (!mounted) return;
    if (ok) {
      setState(() => _activeTagId = t.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Emulating "${t.name}". Hold phone to the reader.'),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This tag type cannot be emulated on the phone.'),
      ));
    }
  }

  void _openTools() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tools — phone can do these',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Dump MIFARE Classic'),
              subtitle: const Text('Read sectors with default keys (read-only)'),
              onTap: () { Navigator.pop(ctx); _runDump(); },
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Read NDEF'),
              subtitle: const Text('Read NDEF records from any tag'),
              onTap: () { Navigator.pop(ctx); _runReadNdef(); },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Clone NDEF to blank tag'),
              subtitle: const Text('Read source, then write to a blank NTAG you own'),
              onTap: () { Navigator.pop(ctx); _runCloneNdef(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<T?> _withSpinner<T>(String msg, Future<T> Function() op) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(msg)),
        ]),
      ),
    );
    try {
      final r = await op();
      if (mounted) Navigator.pop(context);
      return r;
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
      return null;
    }
  }

  Future<void> _runDump() async {
    final dump = await _withSpinner(
        'Hold the MIFARE Classic card to the phone…', () => _nfc.dumpClassic());
    if (dump == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dump: ${dump.readableSectors}/${dump.sectorCount} sectors'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(dump.toHexDump(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final f = await Exporters.save(
                  'dump_${dump.uid}.nfc', Exporters.flipperNfc(dump));
              await SharePlus.instance.share(ShareParams(
                  files: [XFile(f.path)],
                  text: 'Flipper .nfc — emulate on Flipper/Proxmark'));
            },
            child: const Text('Export Flipper'),
          ),
          TextButton(
            onPressed: () async {
              final f = await Exporters.save(
                  'dump_${dump.uid}.txt', Exporters.proxmarkHex(dump));
              await SharePlus.instance.share(ShareParams(
                  files: [XFile(f.path)], text: 'Proxmark hex dump'));
            },
            child: const Text('Export Proxmark'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _runReadNdef() async {
    final r = await _withSpinner('Hold the tag to the phone…', () => _nfc.readNdef());
    if (r == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NDEF'),
        content: SingleChildScrollView(child: Text(r.summary)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _runCloneNdef() async {
    final src = await _withSpinner(
        'Step 1/2 — hold the SOURCE tag…', () => _nfc.readNdef());
    if (src == null || !mounted) return;
    if (src.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Source has no NDEF to clone.')));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Source read'),
        content: Text('${src.summary}\n\nNow hold a BLANK writable NTAG you own.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _withSpinner('Step 2/2 — hold the BLANK target tag…',
        () => _nfc.writeNdef(src.records.cast<ndef.NDEFRecord>()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clone written.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _store.tags;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TagWallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build),
            tooltip: 'Tools',
            onPressed: _nfcStatus == 'absent' ? null : _openTools,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Icon(Icons.circle, size: 10, color: _statusColor),
              const SizedBox(width: 6),
              Text(_statusText, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nfcStatus == 'absent' ? null : _scan,
        icon: const Icon(Icons.nfc),
        label: const Text('Scan tag'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : tags.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: tags.length,
                  itemBuilder: (_, i) {
                    final t = tags[i];
                    final active = _activeTagId == t.id;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(
                          t.canEmulate ? Icons.contactless : Icons.block,
                          color: t.canEmulate ? Colors.indigo : Colors.grey,
                        ),
                        title: Text(t.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.type, style: const TextStyle(fontSize: 12)),
                            Text(t.verdict.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: t.canEmulate ? Colors.green : Colors.orange)),
                          ],
                        ),
                        trailing: t.canEmulate
                            ? Switch(value: active, onChanged: (_) => _toggleEmulate(t))
                            : const SizedBox.shrink(),
                        onLongPress: () async {
                          await _store.remove(t.id);
                          if (active) await _nfc.clearActiveTag();
                          setState(() => _activeTagId = active ? null : _activeTagId);
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class _ScanDialog extends StatefulWidget {
  final NfcService nfc;
  const _ScanDialog({required this.nfc});
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  String _msg = 'Hold your tag to the back of the phone…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final r = await widget.nfc.scanOnce();
      await widget.nfc.finish(alert: 'Read OK');
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      await widget.nfc.finish(error: 'Read failed');
      if (mounted) setState(() => _msg = 'No tag read.\n($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.nfc, size: 48, color: Colors.indigo),
          const SizedBox(height: 16),
          Text(_msg, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.nfc.finish();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  final EmulateVerdict verdict;
  const _VerdictBanner({required this.verdict});
  @override
  Widget build(BuildContext context) {
    final ok = verdict == EmulateVerdict.hceCapable;
    final color = ok
        ? Colors.green
        : verdict == EmulateVerdict.notEmulatable
            ? Colors.red
            : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ok ? Icons.check_circle : Icons.warning, color: color, size: 18),
            const SizedBox(width: 6),
            Text(verdict.label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text(verdict.explanation, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nfc, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No tags yet', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'Tap "Scan tag" and hold a fob you own to the phone. '
              'TagWallet will identify it and tell you whether the phone can emulate it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
