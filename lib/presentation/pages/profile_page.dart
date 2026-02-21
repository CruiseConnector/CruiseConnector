import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/pages/welcome_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void signUserOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false, 
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.account_circle,
              size: 80,
              color: Color(0xFFFF3B30),
            ),
            const SizedBox(height: 20),
            const Text(
              "Mein Profil",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFFFFF).withOpacity(0.06), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "E-Mail:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    user?.email ?? "Keine E-Mail gefunden",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Einstellungen",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Hilfe & Support",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  ListTile(
                    leading: const Icon(Icons.info, color: Color(0xFFFF3B30)),
                    title: const Text(
                      "Über CruiseConnect",
                      style: TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.white70),
                    onTap: () {},
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => signUserOut(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        "Abmelden",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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