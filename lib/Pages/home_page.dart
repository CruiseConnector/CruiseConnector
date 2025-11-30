import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cruise_connect/pages/welcome_page.dart'; // Import Welcome Page für Navigation nach Logout

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Funktion zum Ausloggen
  void signUserOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    
    // Nach dem Ausloggen zur Welcome Page zurückkehren
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
    // Den aktuellen Benutzer abrufen
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[300], 
      appBar: AppBar(
        backgroundColor: const Color(0xFFEC5953), // Dein Brand-Rot
        title: const Text(
          "Home", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        automaticallyImplyLeading: false, // KEIN Zurück-Pfeil automatisch
        leading: null,                    // Zur Sicherheit explizit null
        actions: [
          IconButton(
            onPressed: () => signUserOut(context),
            icon: const Icon(Icons.logout, color: Colors.white),
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 20),
            
            const Text(
              "Angemeldet als:", // Auf Deutsch
              style: TextStyle(fontSize: 20, color: Colors.grey),
            ),
            
            const SizedBox(height: 10),
            
            // EMAIL ANZEIGEN
            Text(
              user?.email ?? "Keine E-Mail gefunden", 
              style: const TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.black87
              ),
            ),
            
            const SizedBox(height: 50),
            
            const Text(
              "Willkommen bei CruiseConnect!", // Auf Deutsch
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}