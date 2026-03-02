import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import 'p2p_chat_screen.dart';
import 'assign_workout_screen.dart';
import 'client_history_screen.dart'; 
import 'coach_client_programs_screen.dart'; 
import '../services/database_service.dart';

class ClientDetailsScreen extends StatefulWidget {
  final String clientId;
  final String clientName;

  const ClientDetailsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen> {
  final TextEditingController _notesController = TextEditingController();
  bool _isSavingNote = false;
  
  int _selectedRating = 0;
  bool _hasRatedClient = false;
  bool _isLoadingRating = true;
  bool _isSubmittingRating = false;

  @override
  void initState() {
    super.initState();
    _loadPrivateNote();
    _checkIfRated(); 
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _checkIfRated() async {
    final coachId = FirebaseAuth.instance.currentUser?.uid;
    if (coachId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('coaches').doc(coachId)
          .collection('rated_clients').doc(widget.clientId)
          .get();
          
      if (doc.exists && mounted) {
        setState(() {
          _hasRatedClient = true;
          _selectedRating = doc.data()?['rating'] ?? 5;
        });
      }
    } catch (e) {
      debugPrint("Ошибка проверки рейтинга: $e");
    } finally {
      if (mounted) setState(() => _isLoadingRating = false);
    }
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) return;
    final coachId = FirebaseAuth.instance.currentUser?.uid;
    if (coachId == null) return;

    setState(() => _isSubmittingRating = true);
    try {
      await DatabaseService().rateAthleteHidden(widget.clientId, _selectedRating, "Оценка дисциплины");
      
      await FirebaseFirestore.instance
          .collection('coaches').doc(coachId)
          .collection('rated_clients').doc(widget.clientId)
          .set({
            'rated': true,
            'rating': _selectedRating,
            'timestamp': FieldValue.serverTimestamp(),
          });
          
      if (mounted) {
        setState(() => _hasRatedClient = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Оценка успешно сохранена!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
            backgroundColor: Color(0xFF9CD600)
          )
        );
      }
    } catch (e) {
      debugPrint("Ошибка сохранения рейтинга: $e");
    } finally {
      if (mounted) setState(() => _isSubmittingRating = false);
    }
  }

  Future<void> _loadPrivateNote() async {
    final coachId = FirebaseAuth.instance.currentUser?.uid;
    if (coachId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(coachId)
          .collection('client_notes').doc(widget.clientId)
          .get();
          
      if (doc.exists && mounted) {
        setState(() {
          _notesController.text = doc.data()?['note'] ?? '';
        });
      }
    } catch (e) {}
  }

  Future<void> _savePrivateNote() async {
    final coachId = FirebaseAuth.instance.currentUser?.uid;
    if (coachId == null) return;

    setState(() => _isSavingNote = true);
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(coachId)
          .collection('client_notes').doc(widget.clientId)
          .set({
        'note': _notesController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('data_saved'.tr()), backgroundColor: const Color(0xFF9CD600)));
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  Future<void> _showEndCoachingDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text('end_coaching'.tr(), style: const TextStyle(color: Colors.white)),
        content: Text('end_coaching_confirm'.tr(), style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr(), style: const TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('users').doc(widget.clientId).update({'currentCoachId': FieldValue.delete()});
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('client_disconnected'.tr()), backgroundColor: const Color(0xFF9CD600)));
                }
              } catch (e) {}
            },
            child: Text('yes_remove'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.clientName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(widget.clientId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                
                final String photoUrl = data['photoUrl'] ?? '';
                final String age = data['age']?.toString() ?? '—';
                final String height = data['height']?.toString() ?? '—';
                final String weight = data['weight']?.toString() ?? '—';

                ImageProvider? imageProvider;
                if (photoUrl.isNotEmpty) {
                  if (photoUrl.startsWith('http')) imageProvider = NetworkImage(photoUrl);
                  else { try { imageProvider = MemoryImage(base64Decode(photoUrl)); } catch (_) {} }
                }

                return Column(
                  children: [
                    Center(
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9CD600), width: 2)),
                        child: ClipOval(
                          child: imageProvider != null
                              ? Image(image: imageProvider, width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 50, color: Colors.grey))
                              : const Icon(Icons.person, size: 50, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(child: Text(widget.clientName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 16),
                    
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8.0, 
                      runSpacing: 8.0, 
                      children: [
                        _buildInfoChip('age'.tr(), age),
                        _buildInfoChip('height_cm'.tr(), height),
                        _buildInfoChip('weight_kg'.tr(), weight),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9CD600),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text('chat_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: widget.clientId, otherUserName: widget.clientName))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9CD600),
                      side: const BorderSide(color: Color(0xFF9CD600)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_task),
                    label: Text('program_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignWorkoutScreen(clientId: widget.clientId, clientName: widget.clientName))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
              tileColor: const Color(0xFF1C1C1E),
              leading: const Icon(Icons.list_alt, color: Colors.white),
              title: const Text('Отправленные программы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoachClientProgramsScreen(clientId: widget.clientId, clientName: widget.clientName))),
            ),
            const SizedBox(height: 12),

            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white12)),
              tileColor: const Color(0xFF1C1C1E),
              leading: const Icon(Icons.history, color: Colors.white),
              title: Text('history_workouts_btn'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientHistoryScreen(clientId: widget.clientId, clientName: widget.clientName))),
            ),
            const SizedBox(height: 32),

            Text('private_notes'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'notes_hint_coach'.tr(),
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isSavingNote ? null : _savePrivateNote,
                child: _isSavingNote 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF9CD600), strokeWidth: 2))
                  : Text('save_note'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            // ЗАДАЧА 2: Компактный текстовый виджет веса вместо громоздкого графика
            Text('weight_progress'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(widget.clientId)
                  .collection('weight_history')
                  .orderBy('date', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Container(
                    width: double.infinity, padding: const EdgeInsets.all(20), 
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)), 
                    child: Center(child: Text('chart_no_data'.tr(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)))
                  );
                }

                final docs = snapshot.data!.docs;
                double initialWeight = (docs.first.data() as Map<String, dynamic>)['weight']?.toDouble() ?? 0.0;
                double currentWeight = (docs.last.data() as Map<String, dynamic>)['weight']?.toDouble() ?? 0.0;
                double diff = currentWeight - initialWeight;
                
                String diffStr = diff > 0 ? '+${diff.toStringAsFixed(1)}' : diff.toStringAsFixed(1);
                Color diffColor = diff > 0 ? Colors.redAccent : (diff < 0 ? const Color(0xFF9CD600) : Colors.grey);

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E), 
                    borderRadius: BorderRadius.circular(16), 
                    border: Border.all(color: Colors.white.withOpacity(0.05))
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text("Начальный", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 4),
                            Text("${initialWeight.toStringAsFixed(1)} кг", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 30, color: Colors.white10),
                      Expanded(
                        child: Column(
                          children: [
                            const Text("Текущий", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 4),
                            Text("${currentWeight.toStringAsFixed(1)} кг", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 30, color: Colors.white10),
                      Expanded(
                        child: Column(
                          children: [
                            const Text("Изменение", style: TextStyle(color: Colors.grey, fontSize: 11)),
                            const SizedBox(height: 4),
                            Text("$diffStr кг", style: TextStyle(color: diffColor, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            
            const Divider(color: Colors.white10, height: 64),
            const Text('ОЦЕНИ КЛИЕНТА', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E), 
                borderRadius: BorderRadius.circular(16), 
                border: Border.all(color: Colors.white.withOpacity(0.05))
              ),
              child: _isLoadingRating 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)))
                : Column(
                    children: [
                      Text(
                        _hasRatedClient ? "Оценка выставлена и сохранена" : "Оценка видна только другим тренерам", 
                        style: TextStyle(color: _hasRatedClient ? const Color(0xFF9CD600) : Colors.grey, fontSize: 11)
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) => IconButton(
                          icon: Icon(
                            index < _selectedRating ? Icons.star_rounded : Icons.star_outline_rounded, 
                            color: index < _selectedRating ? const Color(0xFF9CD600).withOpacity(_hasRatedClient ? 1.0 : 0.6) : Colors.white24, 
                            size: 32
                          ),
                          onPressed: _hasRatedClient ? null : () {
                            setState(() => _selectedRating = index + 1);
                          },
                        )),
                      ),
                      if (!_hasRatedClient) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_selectedRating > 0 && !_isSubmittingRating) ? _submitRating : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9CD600),
                              disabledBackgroundColor: Colors.white10,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            child: _isSubmittingRating 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                : const Text('СОХРАНИТЬ ОЦЕНКУ', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ]
                    ],
                  ),
            ),
            const SizedBox(height: 40),

            Center(
              child: OutlinedButton.icon(
                onPressed: () => _showEndCoachingDialog(context),
                icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                label: Text('end_coaching'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.redAccent.withOpacity(0.05),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}