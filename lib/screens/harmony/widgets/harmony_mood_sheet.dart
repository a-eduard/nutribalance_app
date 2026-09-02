// Файл: lib/screens/harmony/widgets/harmony_mood_sheet.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HarmonyMoodSheet extends StatefulWidget {
  final DateTime selectedDay;
  final List<String> currentMoods;
  final Function(List<String>) onSave;

  const HarmonyMoodSheet({
    super.key,
    required this.selectedDay,
    required this.currentMoods,
    required this.onSave,
  });

  static void show({
    required BuildContext context,
    required DateTime selectedDay,
    required List<String> currentMoods,
    required Function(List<String>) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => HarmonyMoodSheet(
        selectedDay: selectedDay,
        currentMoods: currentMoods,
        onSave: onSave,
      ),
    );
  }

  @override
  State<HarmonyMoodSheet> createState() => _HarmonyMoodSheetState();
}

class _HarmonyMoodSheetState extends State<HarmonyMoodSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Set<String> _selectedMoods;
  List<String> _filteredMoods = [];

  final List<String> _allMoods = [
    'Авантюризм', 'Беспокойная', 'Бессильная', 'Боль', 'Больная', 'Влюбленная', 
    'Возбужденная', 'Впечатлительная', 'Гордая', 'Грустная', 'Забывчивая', 'Игривая', 
    'Испуганная', 'Кокетливая', 'Любопытная', 'Мечтательная', 'Нейтральная', 
    'Неуверенная', 'Неуравновешенная', 'Одинокая', 'Плаксивая', 'Подавлена', 
    'Полна надежд', 'Потерянная', 'Раздраженная', 'Раздражительная', 'Разочарованная', 
    'Растерянная', 'Ревнивая', 'Решительная', 'Сексуальная', 'Сердитая', 'Скучающая', 
    'Сладкая страсть', 'Сонная', 'Сосредоточенная', 'Спокойная', 'Счастливая', 
    'Творческая', 'Угрюмая', 'Удовлетворена', 'Усталая', 'Эмоциональная', 'Энергичная'
  ];

  @override
  void initState() {
    super.initState();
    _selectedMoods = Set.from(widget.currentMoods);
    _filteredMoods = List.from(_allMoods);
    
    for (var mood in _selectedMoods) {
      if (!_allMoods.contains(mood)) _allMoods.add(mood);
    }
  }

  String _getEmojiForMood(String mood) {
    final m = mood.toLowerCase();
    if (m.contains('счастлив') || m.contains('удовлетв') || m.contains('радост')) return '😊';
    if (m.contains('груст') || m.contains('плак') || m.contains('одинок') || m.contains('подавл')) return '😢';
    if (m.contains('зл') || m.contains('сердит') || m.contains('раздраж') || m.contains('угрюм')) return '😡';
    if (m.contains('сонн') || m.contains('устал') || m.contains('бессил')) return '😴';
    if (m.contains('влюблен') || m.contains('страсть') || m.contains('сексуал') || m.contains('кокет')) return '😍';
    if (m.contains('тревог') || m.contains('беспокой') || m.contains('испуг') || m.contains('растерян')) return '😰';
    if (m.contains('энерг') || m.contains('творч') || m.contains('авантюр')) return '⚡';
    if (m.contains('спокой') || m.contains('нейтрал') || m.contains('сосредоточ')) return '😌';
    return '🎭';
  }

  void _filterSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMoods = List.from(_allMoods);
      } else {
        _filteredMoods = _allMoods.where((m) => m.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  void _toggleMood(String mood) {
    setState(() {
      if (_selectedMoods.contains(mood)) {
        _selectedMoods.remove(mood);
      } else {
        _selectedMoods.add(mood);
      }
    });
  }

  Future<void> _saveAndClose() async {
    final list = _selectedMoods.toList();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final String docId = "${widget.selectedDay.year}-${widget.selectedDay.month.toString().padLeft(2, '0')}-${widget.selectedDay.day.toString().padLeft(2, '0')}";
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'moods': list, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
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
              Text("Настроение", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
              TextButton(onPressed: _saveAndClose, child: Text("Готово", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _searchController,
            onChanged: _filterSearch,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: "Поиск настроения...",
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
              itemCount: _filteredMoods.length + (_searchController.text.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredMoods.length) {
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), child: Icon(Icons.add, color: theme.colorScheme.primary)),
                    title: Text('Добавить "${_searchController.text}"', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    onTap: () {
                      final newMood = _searchController.text.trim();
                      setState(() {
                        _allMoods.add(newMood);
                        _selectedMoods.add(newMood);
                        _searchController.clear();
                        _filterSearch('');
                      });
                      FocusScope.of(context).unfocus();
                    },
                  );
                }

                final mood = _filteredMoods[index];
                final bool isSelected = _selectedMoods.contains(mood);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: Text(_getEmojiForMood(mood), style: const TextStyle(fontSize: 24)),
                  title: Text(mood, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  trailing: isSelected 
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : Icon(Icons.circle_outlined, color: theme.colorScheme.onSurfaceVariant),
                  onTap: () => _toggleMood(mood),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}