import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/item.dart';
import '../providers/inventory_provider.dart';
import '../services/livekit_voice_service.dart';

/// LiveKit-backed inventory proposals. The user reviews each proposal before
/// this screen calls the normal authenticated inventory write API.
class VoiceInventoryScreen extends StatefulWidget {
  const VoiceInventoryScreen({super.key});

  @override
  State<VoiceInventoryScreen> createState() => _VoiceInventoryScreenState();
}

class _VoiceInventoryScreenState extends State<VoiceInventoryScreen>
    with SingleTickerProviderStateMixin {
  final LiveKitVoiceService _voice = LiveKitVoiceService();
  late final AnimationController _pulse;
  StreamSubscription<VoiceUiEvent>? _events;
  bool _active = false;
  bool _saving = false;
  String _status = 'TAP TO SPEAK';
  String _transcript = '';
  List<ParsedCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: .88, upperBound: 1.12);
    _events = _voice.events.listen(_onVoiceEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _pulse.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_voice.isConnecting) return;
    if (_voice.isConnected) {
      if (!_active) {
        await _voice.setMicrophoneEnabled(true);
        if (mounted) setState(() { _active = true; _status = 'LISTENING'; });
        return;
      }
      await _voice.setMicrophoneEnabled(false);
      if (mounted) setState(() { _active = false; _status = 'PROCESSING'; });
      return;
    }
    setState(() { _active = true; _status = 'CONNECTING'; _transcript = ''; _categories = []; });
    _pulse.repeat(reverse: true);
    try {
      await _voice.connect();
    } catch (_) {
      if (!mounted) return;
      _pulse.stop();
      setState(() { _active = false; _status = 'VOICE UNAVAILABLE'; });
    }
  }

  void _onVoiceEvent(VoiceUiEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'connected': setState(() => _status = 'LISTENING'); break;
      case 'user_transcript':
        final text = event.payload['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) setState(() => _transcript = text);
        break;
      case 'agent_state':
        final state = event.payload['state']?.toString();
        if (state != null && state.isNotEmpty) setState(() => _status = state.toUpperCase());
        break;
      case 'inventory_draft': _setProposal(event.payload); break;
      case 'error': setState(() => _status = 'VOICE ERROR'); break;
      case 'disconnected': break;
    }
  }

  Future<void> _setProposal(Map<String, dynamic> payload) async {
    final source = payload['categories'];
    if (source is! List) return;
    final categories = <ParsedCategory>[];
    for (final rawCategory in source.whereType<Map>()) {
      final rawItems = rawCategory['items'];
      if (rawItems is! List) continue;
      final items = rawItems.whereType<Map>().map((rawItem) => ParsedItem(
        name: rawItem['name']?.toString() ?? '',
        price: double.tryParse('${rawItem['price'] ?? 0}') ?? 0,
        unit: rawItem['unit']?.toString() ?? 'piece',
        isExisting: rawItem['is_existing'] == true,
        oldPrice: rawItem['old_price'] is num ? (rawItem['old_price'] as num).toDouble() : null,
        existingId: rawItem['existing_id']?.toString(),
        aliases: rawItem['aliases'] is List ? (rawItem['aliases'] as List).map((value) => value.toString()).toList() : [],
      )).toList();
      if (items.isNotEmpty) categories.add(ParsedCategory(name: rawCategory['name']?.toString() ?? 'Other', items: items));
    }
    await _voice.disconnect();
    if (!mounted) return;
    _pulse.stop();
    setState(() { _active = false; _status = 'REVIEW PROPOSAL'; _categories = categories; });
  }

  void _addManual() => setState(() {
    if (_categories.isEmpty) _categories.add(ParsedCategory(name: 'Other', items: []));
    _categories.first.items.add(ParsedItem(name: '', price: 0, unit: 'piece', isExisting: false, aliases: []));
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final provider = context.read<InventoryProvider>();
      for (final category in _categories) {
        for (final item in category.items) {
          if (item.name.trim().isEmpty || item.price <= 0) continue;
          final existingId = item.existingId?.trim();
          final id = existingId != null && existingId.isNotEmpty ? existingId : 'custom_${DateTime.now().microsecondsSinceEpoch}_${item.name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
          await provider.addItem(Item(id: id, names: [item.name.trim(), ...item.aliases.where((name) => name.trim().isNotEmpty)], price: item.price, unit: item.unit.trim().isEmpty ? 'piece' : item.unit.trim(), category: category.name.trim().isEmpty ? 'Other' : category.name.trim()));
        }
      }
      await provider.fetchItems();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listening = _active || _voice.isConnecting;
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Inventory')),
      floatingActionButton: _categories.isNotEmpty ? FloatingActionButton(onPressed: _addManual, child: const Icon(Icons.add)) : null,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          if (_categories.isEmpty) ...[
            const Text('Speak an item, price and unit. Review all changes before saving.', textAlign: TextAlign.center),
            const Spacer(),
            ScaleTransition(scale: listening ? _pulse : const AlwaysStoppedAnimation(1), child: GestureDetector(onTap: _saving ? null : _toggle, child: CircleAvatar(radius: 64, backgroundColor: listening ? AppColors.primaryGreen : Colors.white, child: Icon(listening ? Icons.graphic_eq : Icons.mic, size: 54, color: listening ? Colors.white : AppColors.primaryGreen)))),
            const SizedBox(height: 18), Text(_status, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 16),
            Text(_transcript.isEmpty ? 'Live transcription will appear here.' : _transcript, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textGrey)),
            const Spacer(),
          ] else ...[
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 12),
            Expanded(child: ListView(children: [for (final category in _categories) ...[
              Text(category.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              for (final item in category.items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                TextFormField(initialValue: item.name, decoration: const InputDecoration(labelText: 'Item'), onChanged: (value) => item.name = value),
                Row(children: [Expanded(child: TextFormField(initialValue: '${item.price}', keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price'), onChanged: (value) => item.price = double.tryParse(value) ?? 0)), const SizedBox(width: 12), Expanded(child: TextFormField(initialValue: item.unit, decoration: const InputDecoration(labelText: 'Unit'), onChanged: (value) => item.unit = value))]),
                if (item.isExisting) Text('Updates existing item${item.oldPrice == null ? '' : ' (old price ₹${item.oldPrice})'}', style: const TextStyle(color: AppColors.textGrey)),
              ]))),
            ])),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'SAVING…' : 'SAVE REVIEWED CHANGES'))),
          ],
        ]),
      ),
    );
  }
}

class ParsedCategory { String name; List<ParsedItem> items; ParsedCategory({required this.name, required this.items}); }
class ParsedItem { String name; double price; String unit; bool isExisting; double? oldPrice; String? existingId; List<String> aliases; ParsedItem({required this.name, required this.price, required this.unit, required this.isExisting, this.oldPrice, this.existingId, required this.aliases}); }
