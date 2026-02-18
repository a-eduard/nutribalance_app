import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart'; // ЛОКАЛИЗАЦИЯ

import 'client_details_screen.dart'; 
import 'coach_profile_settings.dart'; 

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(backgroundColor: Colors.black);

    // ПЕРЕВОД ЗАГОЛОВКА
    final String appBarTitle = _currentIndex == 0 ? 'my_clients'.tr() : 'marketplace_profile'.tr();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          appBarTitle, 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.grey),
            tooltip: 'become_client'.tr(),
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                await FirebaseFirestore.instance.collection('users').doc(uid).set(
                  {'activeRole': 'user'}, 
                  SetOptions(merge: true)
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'logout'.tr(),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildClientsList(user.uid),
          const CoachProfileSettings(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1C1C1E))),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.black,
          selectedItemColor: const Color(0xFFCCFF00),
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.people), 
              label: 'clients_tab'.tr()
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline), 
              label: 'my_profile_tab'.tr()
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('currentCoachId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("${'error_msg'.tr()}: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 60, color: Colors.grey.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text('no_clients'.tr(), style: const TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 8),
                Text('profile_in_marketplace'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }

        final clients = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final doc = clients[index];
            final data = doc.data() as Map<String, dynamic>;
            
            final clientId = doc.id;
            final clientName = data['name']?.toString() ?? 'client_default'.tr();
            
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(
                    builder: (_) => ClientDetailsScreen(clientId: clientId, clientName: clientName)
                  )
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.person, color: Colors.grey),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        clientName, 
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFCCFF00), size: 28),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}