import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../../services/database_service.dart';

class HarmonySymptomsSheet extends StatefulWidget {
  final DateTime selectedDay;
  final Map<String, int> currentSymptoms;
  final Function(Map<String, int>) onSave;

  const HarmonySymptomsSheet({
    super.key,
    required this.selectedDay,
    required this.currentSymptoms,
    required this.onSave,
  });

  static void show({
    required BuildContext context,
    required DateTime selectedDay,
    required Map<String, int> currentSymptoms,
    required Function(Map<String, int>) onSave,
  }) {
    final theme = Theme.of(context); // Адаптация цвета шторки
    
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface, // ИСПРАВЛЕНО
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => HarmonySymptomsSheet(
        selectedDay: selectedDay,
        currentSymptoms: currentSymptoms,
        onSave: onSave,
      ),
    );
  }

  @override
  State<HarmonySymptomsSheet> createState() => _HarmonySymptomsSheetState();
}

class _HarmonySymptomsSheetState extends State<HarmonySymptomsSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Map<String, int> _selectedSymptoms;
  List<String> _filteredSymptoms = [];

  final List<String> _allSymptoms = [
    'Абсцесс', 'Аллергия', 'Аппетит', 'Аритмия', 'Бедренные судороги', 'Беспокойные ноги', 'Бессонница', 
    'Болезненность груди', 'Болезненные менструации', 'Болезненный половой акт', 'Боли в горле', 
    'Боли в мышцах/суставах', 'Боли в плечах', 'Боли в спине', 'Боли в теле', 'Боли при овуляции', 
    'Боли при овуляции (левая сторона)', 'Боль в груди', 'Боль в грудной клетке', 'Боль в животе', 
    'Боль в кисте левого яичника', 'Боль в кисте правого яичника', 'Боль в крестцовом отделе', 
    'Боль в паху', 'Боль в пояснице', 'Боль в сосках', 'Боль во время мочеиспускания', 'Больное горло', 
    'Бруксизм', 'Вагинальные выделения', 'Вагинальные газы', 'Вагинальный микоз', 'Вздутие живота', 
    'Воспаление яичников', 'Вспышка герпеса', 'Выделения из сосков', 'Высокое кровяное давление', 
    'Высокое содержание сахара в крови', 'Газообразование', 'Геморрой', 'Генитальный герпес', 'Герпес', 
    'Головные боли', 'Головокружение', 'Горький привкус', 'Давление в области мочевого пузыря', 'Дрожь', 
    'Железный привкус', 'Железодефицитная анемия', 'Жжение во рту', 'Жирные волосы', 'Забывчивость', 
    'Заложенность носа', 'Замедленный пульс в состоянии покоя', 'Замутненность сознания', 'Запах тела', 
    'Запор', 'Затрудненное мочеиспускание', 'Затылочная невралгия', 'Зубная боль', 'Зуд', 
    'Избыточные жировые отложения', 'Изжога', 'Изменения вкуса', 'Изменения настроения', 
    'Ингибированное сексуальное желание', 'Истончение волос', 'Кандидоз', 'Качество голоса', 'Кашель', 
    'Кислый привкус во рту', 'Кишечная боль', 'Кишечные газы', 'Колики', 'Красные пятна', 
    'Кремово-белые выделения', 'Кровотечение из носа', 'Кровоточащие десны', 'Кровяные выделения/кровотечение', 
    'Либидо', 'Липедема (болезненное ожирение)', 'Лихорадка', 'Ломкие волосы', 'Ломкие ногти', 
    'Масляная/жирная кожа', 'Менструальный поток', 'Мигрень', 'Мигрень с аурой', 'Миома', 
    'Мышечная скованность', 'Мышечные спазмы', 'Навязчивые/обсессивные мысли', 'Нарушенный сон', 
    'Насморк', 'Недержание мочи', 'Недомогание', 'Нерегулярная менструация', 'Неуклюжесть', 
    'Низкий сахар в крови', 'Низкий уровень энергии', 'Низкое кровяное давление', 'Низкое либидо', 
    'Ночная потливость', 'Обезвоживание', 'Обильные менструации', 'Обморок', 'Озноб', 
    'Оргазмическая головная боль', 'Отек (голеностоп)', 'Отек (лицо)', 'Отек (рука)', 'Отек вокруг влагалища', 
    'Отек кожи', 'Отек ног', 'Отек стоп', 'Отечные суставы', 'Отсутствие аппетита', 'Отсутствие оргазма', 
    'Ощущение жжения в области малого таза', 'Ощущение жжения во время мочеиспускания', 'Ощущение подавленности', 
    'Ощущение удара током', 'ПМС (предменструальный синдром)', 'Паническая атака и паническое расстройство', 
    'Перинеальная боль', 'Периоральный дерматит', 'Периорбитальная отечность', 'Плач, слезы', 'Плохая концентрация', 
    'Поверхностное дыхание', 'Повышенная жажда', 'Повышенная чувствительность к запахам', 'Подмышечная боль', 
    'Покалывание в конечностях', 'Поллиноз', 'Понос', 'Послеродовая депрессия/тревога', 'Потеря веса', 
    'Потные ладони', 'Потоотделение', 'Предменструальное дисфорическое расстройство (ПМДР)', 'Преэклампсия', 
    'Приливы жара', 'Припухлость груди', 'Проблемы со сном', 'Провалы памяти', 'Прорывное кровотечение', 
    'Психоз', 'Радикулит', 'Раздражение на ногах', 'Раздражительность', 'Разрыв тканей влагалища', 
    'Расстройство желудка', 'Регулярный стул', 'Ректальная боль', 'Розовые выделения', 'Сбивчивое дыхание', 
    'Сгустки крови', 'Сердцебиение', 'Серые выделения', 'Синусит', 'Сладкий привкус во рту', 'Сонливость', 
    'Спазмы в тазовой области', 'Странные сны и кошмары', 'Страх', 'Стресс', 'Судороги (эпилепсия)', 
    'Судороги в голени', 'Судороги ног', 'Сухая кожа', 'Сухость влагалища', 'Сухость во рту', 'Сухость губ', 'Сыпь', 
    'Тазовое давление', 'Тошнота/рвота', 'Тревога', 'Туманное зрение', 'Тяга (овощи)', 'Тяга (острая пища)', 
    'Тяга (фрукты)', 'Тяга (сладкая еда)', 'Тяга (соленая еда)', 'Увеличение веса', 'Увеличенные лимфатические узлы', 
    'Угревая сыпь', 'Укачивание', 'Усталость', 'Утренняя тошнота', 'Учащенное сердцебиение', 'Учащенный пульс в состоянии покоя', 
    'Ушная боль', 'Хейлит', 'Холод в конечностях', 'Холод в теле', 'Цистит', 'Частота мочеиспускания', 'Чихание', 
    'Чувствительность к свету', 'Чувствительность к холоду и теплу', 'Чувствительность груди', 'Шум в ушах', 
    'Эйфория', 'Экстрасистолия', 'Язвы', 'Ярко-красная, отечная вульва'
  ];

  @override
  void initState() {
    super.initState();
    _selectedSymptoms = Map.from(widget.currentSymptoms);
    _filteredSymptoms = List.from(_allSymptoms);
    
    for (var key in _selectedSymptoms.keys) {
      if (!_allSymptoms.contains(key)) {
        _allSymptoms.add(key);
      }
    }
  }

  // ИСПРАВЛЕНО: Добавлен обязательный dispose
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getEmojiForSymptom(String symptom) {
    final s = symptom.toLowerCase();
    if (s.contains('бол') || s.contains('мигрень') || s.contains('спазм') || s.contains('колик') || s.contains('судорог')) return '⚡';
    if (s.contains('выделен') || s.contains('кров') || s.contains('моч')) return '💧';
    if (s.contains('настроен') || s.contains('депрес') || s.contains('тревог') || s.contains('страх') || s.contains('плач') || s.contains('эмоц') || s.contains('панич') || s.contains('стресс') || s.contains('эйфория') || s.contains('раздраж')) return '🧠';
    if (s.contains('сон') || s.contains('бессон')) return '💤';
    if (s.contains('тяга') || s.contains('аппетит') || s.contains('вкус') || s.contains('тошнот') || s.contains('рвот') || s.contains('живот') || s.contains('запор') || s.contains('газ') || s.contains('изжог') || s.contains('желуд') || s.contains('понос') || s.contains('стул')) return '🍎';
    if (s.contains('отек') || s.contains('вздутие')) return '🎈';
    if (s.contains('груд') || s.contains('соск')) return '🍒';
    if (s.contains('жар') || s.contains('пот') || s.contains('лихорад')) return '🔥';
    if (s.contains('холод') || s.contains('озноб')) return '❄️';
    return '🌸';
  }

  void _filterSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSymptoms = List.from(_allSymptoms);
      } else {
        _filteredSymptoms = _allSymptoms.where((s) => s.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  void _showIntensityPicker(String symptom) {
    int currentScore = _selectedSymptoms[symptom] ?? 5;
    final theme = Theme.of(context); // Получаем текущую тему

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface, // ИСПРАВЛЕНО
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (pickerCtx) => StatefulBuilder(
        builder: (context, setPickerState) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(symptom, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_getHintForScore(currentScore), style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                
                SizedBox(
                  height: 120,
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(initialItem: currentScore - 1),
                    itemExtent: 48,
                    selectionOverlay: Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 1.5), bottom: BorderSide(color: theme.colorScheme.primary, width: 1.5)))),
                    onSelectedItemChanged: (idx) => setPickerState(() => currentScore = idx + 1),
                    children: List.generate(10, (index) => Center(child: Text("${index + 1}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)))),
                  ),
                ),
                
                const SizedBox(height: 32),
                Row(
                  children: [
                    if (_selectedSymptoms.containsKey(symptom)) ...[
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: () {
                            setState(() => _selectedSymptoms.remove(symptom));
                            Navigator.pop(pickerCtx);
                          },
                          child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: theme.colorScheme.primary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: () {
                          setState(() => _selectedSymptoms[symptom] = currentScore);
                          Navigator.pop(pickerCtx);
                        },
                        child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        }
      )
    );
  }

  String _getHintForScore(int score) {
    if (score <= 3) return "Легкий дискомфорт";
    if (score <= 6) return "Умеренно, но терпимо";
    if (score <= 8) return "Сильно мешает";
    return "Невыносимо, нужна помощь";
  }

  Future<void> _saveAndClose() async {
    await DatabaseService().saveDailySymptoms(widget.selectedDay, _selectedSymptoms);
    widget.onSave(_selectedSymptoms);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // Получаем текущую тему

    return Padding(
      padding: EdgeInsets.only(top: 24, left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Симптомы", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
              TextButton(onPressed: _saveAndClose, child: Text("Готово", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 16),
          
          // Строка поиска (Адаптированная)
          TextField(
            controller: _searchController,
            onChanged: _filterSearch,
            style: TextStyle(color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: "Поиск симптома...",
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05), // Легкий фон в зависимости от темы
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 16),

          // Список симптомов
          Expanded(
            child: ListView.builder(
              itemCount: _filteredSymptoms.length + (_searchController.text.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _filteredSymptoms.length) {
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.05), child: Icon(Icons.add, color: theme.colorScheme.primary)),
                    title: Text('Добавить "${_searchController.text}"', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    onTap: () {
                      final newSymptom = _searchController.text.trim();
                      setState(() {
                        _allSymptoms.add(newSymptom);
                        _searchController.clear();
                        _filterSearch('');
                      });
                      FocusScope.of(context).unfocus();
                      _showIntensityPicker(newSymptom);
                    },
                  );
                }

                final symptom = _filteredSymptoms[index];
                final bool isSelected = _selectedSymptoms.containsKey(symptom);
                final int score = _selectedSymptoms[symptom] ?? 0;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: Text(_getEmojiForSymptom(symptom), style: const TextStyle(fontSize: 24)),
                  title: Text(symptom, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  trailing: isSelected 
                    ? Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                        child: Text(score.toString(), style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                      )
                    : Icon(Icons.add_circle_outline, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  onTap: () => _showIntensityPicker(symptom),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}