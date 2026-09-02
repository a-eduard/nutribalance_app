// Файл: lib/screens/harmony/widgets/harmony_meds_sheet.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HarmonyMedsSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<String> currentMeds;
  final Function(List<String>) onSave;

  const HarmonyMedsSheet({
    super.key,
    required this.selectedDay,
    required this.currentMeds,
    required this.onSave,
  });

  static void show({
    required BuildContext context,
    required DateTime selectedDay,
    required List<String> currentMeds,
    required Function(List<String>) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => HarmonyMedsSheet(
        selectedDay: selectedDay,
        currentMeds: currentMeds,
        onSave: onSave,
      ),
    );
  }

  @override
  State<HarmonyMedsSheet> createState() => _HarmonyMedsSheetState();
}

class _HarmonyMedsSheetState extends State<HarmonyMedsSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Set<String> _selectedMeds;
  List<String> _filteredMeds = [];

  final List<String> _allMeds = [
    'Аварийная противозачаточная таблетка', 'Антибиотики', 'Антидепрессант', 
    'Без названия', 'Биотин', 'Витамин D', 'Витамин B12', 'Витамины для беременных', 
    'Гормональная противозачаточная таблетка', 'Диоксид кремния', 'Изжога / желудочная кислота', 
    'Обезболивающее', 'Поливитаминная таблетка', 'Примолют-Нор', 'Пробиотики', 
    'Прогестерон', 'Противовирусные', 'Противовоспалительные', 'Слабительное', 
    'Снотворное', 'Таблетка от головной боли', 'Таблетка от мигрени', 'Таблетки для похудения', 
    'Таблетки от аллергии', 'Таблетки от кровяного давления', 'Транквилизаторы', 
    'Щитовидная железа', 'Эсмия', 'Эстроген', 'Вагинальный эстроген', 'Имплантат ЗГТ', 
    'Прогестероновый пластырь', 'Таблетка ЗГТ', 'Тестостероновый гель', 'Эстрогеновый гель', 
    'Эстрогеновый пластырь'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMeds = Set.from(widget.currentMeds);
    _filteredMeds = List.from(_allMeds);
    
    for (var med in _selectedMeds) {
      if (!_allMeds.contains(med)) _allMeds.add(med);
    }
  }

  String _getEmojiForMed(String med) {
    final m = med.toLowerCase();
    if (m.contains('витамин') || m.contains('биотин')) return '💊';
    if (m.contains('гель') || m.contains('крем') || m.contains('вагинальн')) return '🧴';
    if (m.contains('пластырь')) return '🩹';
    if (m.contains('противозачат')) return '🛡️';
    if (m.contains('имплантат')) return '💉';
    if (m.contains('снотворн') || m.contains('транквилиз') || m.contains('антидепр')) return '🌙';
    if (m.contains('обезбол') || m.contains('мигрен') || m.contains('головн')) return '🤕';
    return '💊';
  }

  void _filterSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMeds = List.from(_allMeds);
      } else {
        _filteredMeds = _allMeds.where((m) => m.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  void _toggleMed(String med) {
    setState(() {
      if (_selectedMeds.contains(med)) {
        _selectedMeds.remove(med);
      } else {
        _selectedMeds.add(med);
      }
    });
  }

  Future<void> _saveAndClose() async {
    final list = _selectedMeds.toList();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final String docId = "${widget.selectedDay.year}-${widget.selectedDay.month.toString().padLeft(2, '0')}-${widget.selectedDay.day.toString().padLeft(2, '0')}";
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'meds': list, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    widget.onSave(list);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: EdgeInsets.only(top: 24, left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Медикаменты", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
              TextButton(onPressed: _saveAndClose, child: Text("Готово", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _searchController,
            onChanged: _filterSearch,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: "Поиск препарата...",
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView.builder(
              itemCount: _filteredMeds.length + (_searchController.text.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredMeds.length) {
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), child: Icon(Icons.add, color: theme.colorScheme.primary)),
                    title: Text('Добавить "${_searchController.text}"', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    onTap: () {
                      final newMed = _searchController.text.trim();
                      setState(() {
                        _allMeds.add(newMed);
                        _selectedMeds.add(newMed);
                        _searchController.clear();
                        _filterSearch('');
                      });
                      FocusScope.of(context).unfocus();
                    },
                  );
                }

                final med = _filteredMeds[index];
                final bool isSelected = _selectedMeds.contains(med);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: Text(_getEmojiForMed(med), style: const TextStyle(fontSize: 24)),
                  title: Text(med, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  trailing: isSelected 
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : Icon(Icons.circle_outlined, color: theme.colorScheme.onSurfaceVariant),
                  onTap: () => _toggleMed(med),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}