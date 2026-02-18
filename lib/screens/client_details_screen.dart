import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';

import 'p2p_chat_screen.dart';
import 'assign_workout_screen.dart';
import 'client_history_screen.dart'; 

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

  @override
  void initState() {
    super.initState();
    _loadPrivateNote();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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
    } catch (e) {
      debugPrint("Load note error: $e");
    }
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
      debugPrint("Save note error: $e");
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
              } catch (e) { debugPrint(e.toString()); }
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
                  if (photoUrl.startsWith('http')) {
                    imageProvider = NetworkImage(photoUrl);
                  } else {
                    try { imageProvider = MemoryImage(base64Decode(photoUrl)); } catch (_) {}
                  }
                }

                return Column(
                  children: [
                    Center(
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9CD600), width: 2)),
                        child: ClipOval(
                          child: imageProvider != null
                              ? Image(image: imageProvider, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 50, color: Colors.grey))
                              : const Icon(Icons.person, size: 50, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(child: Text(widget.clientName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInfoChip('age'.tr(), age),
                        const SizedBox(width: 8),
                        _buildInfoChip('height_cm'.tr(), height),
                        const SizedBox(width: 8),
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

            Text('weight_progress'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users').doc(widget.clientId)
                  .collection('weight_history')
                  .orderBy('date', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.length < 2) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                    child: Center(
                      child: Text('chart_no_data'.tr(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return Container(
                  height: 220,
                  padding: const EdgeInsets.only(top: 24, bottom: 10, left: 10, right: 24),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false), 
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: docs.asMap().entries.map((e) {
                            final data = e.value.data() as Map<String, dynamic>;
                            double weight = (data['weight'] ?? 0.0).toDouble();
                            return FlSpot(e.key.toDouble(), weight);
                          }).toList(),
                          isCurved: true,
                          color: const Color(0xFF9CD600), 
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: const Color(0xFF9CD600).withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 40),
            Center(
              child: TextButton.icon(
                onPressed: () => _showEndCoachingDialog(context),
                icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                label: Text('end_coaching'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}