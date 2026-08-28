import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../vpn/app_controller.dart';

class ServerProfileSettingsScreen extends StatefulWidget {
  const ServerProfileSettingsScreen({
    required this.server,
    required this.controller,
    super.key,
  });

  final ServerInfo server;
  final AppController controller;

  @override
  State<ServerProfileSettingsScreen> createState() =>
      _ServerProfileSettingsScreenState();
}

class _ServerProfileSettingsScreenState
    extends State<ServerProfileSettingsScreen> {
  late final TextEditingController _fingerprint;
  late final TextEditingController _cipherSuites;
  late final TextEditingController _finalMask;
  bool _saving = false;
  String? _finalMaskError;

  @override
  void initState() {
    super.initState();
    _fingerprint = TextEditingController(text: widget.server.fingerprint);
    _cipherSuites = TextEditingController(text: widget.server.cipherSuites);
    _finalMask = TextEditingController(text: widget.server.finalMask);
  }

  @override
  void dispose() {
    _fingerprint.dispose();
    _cipherSuites.dispose();
    _finalMask.dispose();
    super.dispose();
  }

  String? _validateFinalMask() {
    final value = _finalMask.text.trim();
    if (value.isEmpty) return null;
    try {
      if (jsonDecode(value) is! Map) return context.s('finalMaskObjectError');
    } on FormatException {
      return context.s('invalidJson');
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validateFinalMask();
    setState(() => _finalMaskError = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateServerProfile(widget.server.id, {
        'fp': _fingerprint.text,
        'cs': _cipherSuites.text,
        'fm': _finalMask.text,
      });
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyShareLink() async {
    final link = await widget.controller.exportServerShareLink(
      widget.server.id,
    );
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s('shareLinkCopied'))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.s('profileTlsSettings'))),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          widget.server.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fingerprint,
          decoration: InputDecoration(
            labelText: context.s('fingerprint'),
            helperText: 'chrome, firefox, safari, edge, random, unsafe',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cipherSuites,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: context.s('cipherSuites'),
            helperText: context.s('cipherSuitesHint'),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _finalMask,
          minLines: 7,
          maxLines: 16,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontFamily: 'Consolas'),
          onChanged: (_) {
            if (_finalMaskError != null) {
              setState(() => _finalMaskError = _validateFinalMask());
            }
          },
          decoration: InputDecoration(
            labelText: 'FinalMask JSON',
            alignLabelWithHint: true,
            helperText: context.s('finalMaskHint'),
            errorText: _finalMaskError,
          ),
        ),
        if (widget.server.allowInsecure) ...[
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.s('allowInsecureUnsupported')),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _copyShareLink,
              icon: const Icon(Icons.copy_rounded),
              label: Text(context.s('copyShareLink')),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(context.s('save')),
            ),
          ],
        ),
      ],
    ),
  );
}
