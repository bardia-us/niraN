import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/operation_error.dart';
import '../../core/widgets/niran_toast.dart';
import '../../core/widgets/profile_choice_field.dart';
import '../../core/widgets/detail_page_header.dart';
import '../../core/widgets/clay_surface.dart';
import '../../core/widgets/interactive_depth.dart';
import '../vpn/app_controller.dart';

class ServerProfileSettingsScreen extends StatefulWidget {
  const ServerProfileSettingsScreen({
    required this.server,
    required this.controller,
    this.embedded = false,
    super.key,
  });

  final ServerInfo server;
  final AppController controller;
  final bool embedded;

  @override
  State<ServerProfileSettingsScreen> createState() =>
      _ServerProfileSettingsScreenState();
}

class _ServerProfileSettingsScreenState
    extends State<ServerProfileSettingsScreen> {
  late final TextEditingController _fingerprint;
  late final TextEditingController _cipherSuites;
  late final TextEditingController _finalMask;
  late final TextEditingController _sni;
  late final TextEditingController _ech;
  String _alpn = '';
  static const fingerprints = [
    '',
    'chrome',
    'firefox',
    'safari',
    'ios',
    'android',
    'edge',
    '360',
    'qq',
    'random',
    'randomized',
    'unsafe',
  ];
  bool _saving = false;
  String? _finalMaskError;
  String? _fingerprintError;

  bool get _isReality => widget.server.security.toLowerCase() == 'reality';

  @override
  void initState() {
    super.initState();
    _fingerprint = TextEditingController(text: widget.server.fingerprint);
    _cipherSuites = TextEditingController(text: widget.server.cipherSuites);
    _finalMask = TextEditingController(text: widget.server.finalMask);
    _sni = TextEditingController(text: widget.server.sni);
    _ech = TextEditingController(text: widget.server.echConfigList);
    _alpn = widget.server.alpn;
  }

  @override
  void dispose() {
    _fingerprint.dispose();
    _cipherSuites.dispose();
    _finalMask.dispose();
    _sni.dispose();
    _ech.dispose();
    super.dispose();
  }

  String? _validateFinalMask() {
    if (_isReality) return null;
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
    final fingerprintError =
        _isReality && _fingerprint.text.trim().toLowerCase() == 'unsafe'
        ? context.s('realityFingerprintUnsupported')
        : null;
    setState(() {
      _finalMaskError = error;
      _fingerprintError = fingerprintError;
    });
    if (error != null || fingerprintError != null) return;
    setState(() => _saving = true);
    try {
      await widget.controller.updateServerProfile(widget.server.id, {
        'fp': _fingerprint.text,
        // The native API replaces all three options. Preserve fields that the
        // Reality editor does not expose instead of clearing subscription data.
        'cs': _isReality ? widget.server.cipherSuites : _cipherSuites.text,
        'fm': _isReality ? widget.server.finalMask : _finalMask.text,
        'sni': _sni.text,
        if (!_isReality) 'alpn': _alpn,
        if (!_isReality) 'echConfigList': _ech.text,
      });
      if (mounted) {
        if (widget.embedded) {
          showNiranToast(context, context.s('save'));
        } else {
          Navigator.pop(context);
        }
      }
    } on Object catch (error) {
      if (mounted) await showOperationError(context, error);
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
      showNiranToast(
        context,
        context.s('shareLinkCopied'),
        icon: Icons.copy_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      if (!widget.embedded)
        Text(
          widget.server.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      if (!widget.embedded) const SizedBox(height: 16),
      if (_isReality) ...[
        Text(context.s('realityProfileHint')),
        const SizedBox(height: 14),
      ],
      TextField(
        controller: _sni,
        decoration: const InputDecoration(labelText: 'Server name (SNI)'),
      ),
      const SizedBox(height: 14),
      ProfileChoiceField(
        key: const Key('profile-fingerprint'),
        label: context.s('fingerprint'),
        errorText: _fingerprintError,
        value: _isReality && _fingerprint.text == 'unsafe'
            ? ''
            : _fingerprint.text,
        values: {
          ...fingerprints.where((value) => !_isReality || value != 'unsafe'),
          if (!fingerprints.contains(_fingerprint.text) &&
              _fingerprint.text.isNotEmpty)
            _fingerprint.text,
        },
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _fingerprint.text = value;
                _fingerprintError = null;
              }),
      ),
      if (!_isReality) ...[
        const SizedBox(height: 14),
        ProfileChoiceField(
          key: const Key('profile-alpn'),
          value: _alpn,
          label: 'ALPN',
          values: {'', 'h2', 'http/1.1', 'h2,http/1.1', _alpn},
          onChanged: _saving ? null : (value) => setState(() => _alpn = value),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ech,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'ECH Config List',
            helperText: 'Base64 / udp://resolver / domain+udp://resolver',
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
          key: const Key('profile-finalmask'),
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
      ],
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
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 10,
        runSpacing: 8,
        children: [
          InteractiveDepth(
            tiltEnabled: false,
            hoverLift: 2,
            radius: 20,
            child: ClaySurface(
              radius: 20,
              child: TextButton.icon(
                onPressed: _copyShareLink,
                icon: const Icon(Icons.copy_rounded),
                label: Text(context.s('copyShareLink')),
              ),
            ),
          ),
          InteractiveDepth(
            tiltEnabled: false,
            hoverLift: 2,
            radius: 20,
            child: ClaySurface(
              radius: 20,
              selected: true,
              child: TextButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(context.s('save')),
              ),
            ),
          ),
        ],
      ),
    ];
    final editor = widget.embedded
        ? Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields,
            ),
          )
        : ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              kToolbarHeight + MediaQuery.paddingOf(context).top + 18,
              18,
              18,
            ),
            children: fields,
          );
    return widget.embedded
        ? editor
        : Scaffold(
            extendBodyBehindAppBar: true,
            appBar: DetailPageHeader(title: context.s('profileTlsSettings')),
            body: editor,
          );
  }
}
