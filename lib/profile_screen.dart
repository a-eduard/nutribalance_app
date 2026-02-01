import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'paywall_screen.dart'; // Если нужно будет навигироваться

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 20),
              
              // 1. USER INFO
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFF1C1C1E),
                      child: Text(
                        user?.email?.substring(0, 1).toUpperCase() ?? "U",
                        style: const TextStyle(fontSize: 30, color: Color(0xFFCCFF00), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.email ?? "User",
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Free Plan",
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 2. STATS ROW
              Row(
                children: [
                  _buildStatCard("0", "ТРЕНИРОВОК"),
                  const SizedBox(width: 16),
                  _buildStatCard("0 кг", "ОБЩИЙ ВЕС"),
                ],
              ),

              const SizedBox(height: 24),

              // 3. PREMIUM BANNER
              GestureDetector(
                onTap: () {
                   // Навигация на Paywall
                   // Navigator.push(context, MaterialPageRoute(builder: (context) => const PaywallScreen()));
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFCCFF00), Color(0xFFAACC00)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFCCFF00).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))
                    ]
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("IRON PRO", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
                          SizedBox(height: 4),
                          Text("Разблокируй AI-функции", style: TextStyle(color: Colors.black, fontSize: 12)),
                        ],
                      ),
                      Icon(Icons.arrow_forward, color: Colors.black),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 4. MENU ITEMS
              _buildMenuItem(Icons.settings, "Настройки", () {}),
              _buildMenuItem(Icons.support_agent, "Поддержка", () {}),
              _buildMenuItem(Icons.privacy_tip, "Политика конфиденциальности", () {}),
              
              const SizedBox(height: 20),
              
              // 5. LOGOUT
              TextButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  // StreamBuilder в main.dart сам вернет нас на экран входа
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text("Выйти из аккаунта", style: TextStyle(color: Colors.red)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white.withOpacity(0.5)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
      contentPadding: EdgeInsets.zero,
    );
  }
}