import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

import '../widgets/base_background.dart'; 
import 'p2p_chat_screen.dart';
import 'coach_profile_screen.dart';

class CoachListScreen extends StatefulWidget {
  const CoachListScreen({super.key});

  @override
  State<CoachListScreen> createState() => _CoachListScreenState();
}

class _CoachListScreenState extends State<CoachListScreen> {
  int _selectedPriceIndex = -1; 

  @override
  Widget build(BuildContext context) {
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('marketplace'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: Colors.transparent,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildPriceChip('category_all'.tr(), -1),
                    const SizedBox(width: 8),
                    _buildPriceChip('filter_price_1'.tr(), 0),
                    const SizedBox(width: 8),
                    _buildPriceChip('filter_price_2'.tr(), 1),
                    const SizedBox(width: 8),
                    _buildPriceChip('filter_price_3'.tr(), 2),
                    const SizedBox(width: 8),
                    _buildPriceChip('filter_price_4'.tr(), 3),
                  ],
                ),
              ),
            ),
            
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('coaches').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text('coaches_not_found'.tr(), style: const TextStyle(color: Colors.grey)));

                  final filteredCoaches = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    int price = 0;
                    if (data['price'] != null && data['price'].toString().isNotEmpty) {
                      String cleanPrice = data['price'].toString().replaceAll(RegExp(r'[^0-9]'), '');
                      price = int.tryParse(cleanPrice) ?? 0;
                    }
                    if (price == 0) return true; 
                    if (_selectedPriceIndex == -1) return true;
                    if (_selectedPriceIndex == 0) return price <= 1000;
                    if (_selectedPriceIndex == 1) return price > 1000 && price <= 3000;
                    if (_selectedPriceIndex == 2) return price > 3000 && price <= 5000;
                    if (_selectedPriceIndex == 3) return price > 5000;
                    return true;
                  }).toList();

                  if (filteredCoaches.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(height: 16),
                          Text('no_coaches_criteria'.tr(), style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  // ОПТИМИЗИРОВАННЫЙ СПИСОК
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredCoaches.length,
                    itemBuilder: (context, index) {
                      final doc = filteredCoaches[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return CoachCard(coachId: doc.id, data: data);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceChip(String label, int index) {
    final isSelected = _selectedPriceIndex == index;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: const Color(0xFF9CD600),
      backgroundColor: Colors.black.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? const Color(0xFF9CD600) : Colors.white12)),
      onSelected: (bool selected) => setState(() => _selectedPriceIndex = selected ? index : -1),
    );
  }
}

class CoachCard extends StatelessWidget {
  final String coachId;
  final Map<String, dynamic> data;

  const CoachCard({super.key, required this.coachId, required this.data});

  @override
  Widget build(BuildContext context) {
    final String name = data['name']?.toString().trim() ?? 'coach'.tr();
    final String exp = data['specialization']?.toString().trim() ?? '';
    final String priceStr = data['price']?.toString() ?? '0';
    int price = 0;
    if (priceStr.isNotEmpty) price = int.tryParse(priceStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final String photoUrl = data['photoUrl'] ?? '';

    return GestureDetector(
      onTap: () {
        final Map<String, dynamic> coachDataToPass = Map.from(data);
        coachDataToPass['id'] = coachId;
        Navigator.push(context, MaterialPageRoute(builder: (context) => CoachProfileScreen(coachData: coachDataToPass)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9CD600), width: 1.5)),
              child: ClipOval(
                child: photoUrl.isNotEmpty
                    ? (photoUrl.startsWith('http') 
                        ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 40, color: Colors.grey))
                        : Image.memory(base64Decode(photoUrl), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 40, color: Colors.grey)))
                    : const Icon(Icons.person, size: 40, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.fitness_center, color: Colors.grey, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(exp, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: price > 0 ? const Color(0xFF9CD600).withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          price > 0 ? "$price ${'per_session'.tr()}" : 'price_negotiable'.tr(),
                          style: TextStyle(color: price > 0 ? const Color(0xFF9CD600) : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: coachId, otherUserName: name))),
                        child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF9CD600), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.chat_bubble, color: Colors.black, size: 16)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}