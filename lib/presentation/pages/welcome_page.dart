import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/pages/login_page.dart';
import 'package:cruise_connect/presentation/pages/register_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Neues, kräftigeres Rot
    final Color brandColor = const Color(0xFFEF4F4F); 

    return Scaffold(
      backgroundColor: brandColor,
      body: Stack(
        children: [
          // 1. Hintergrund (Rot)
          Container(
            height: double.infinity,
            width: double.infinity,
            color: brandColor,
          ),

          // 2. Weißer Container (Unten)
          Positioned(
            // 0.35 bedeutet: Er fängt bei 35% von oben an
            top: size.height * 0.35, 
            bottom: 0, // Geht bis ganz nach unten -> Kein roter Balken mehr!
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
            ),
          ),

          // 3. Inhalt (Scrollbar)
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // --- AUTO BILD (Im roten Bereich) ---
                    Container(
                      height: size.height * 0.18,
                      width: size.width * 0.75,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],

                      ),
                      child: const Icon(Icons.directions_car, size: 80, color: Colors.white),
                    ),

                    // --- PLATZHALTER ---
                    // Dieser Abstand drückt den Text genau in den weißen Bereich.
                    SizedBox(height: size.height * 0.10), 

                    // --- TEXTE (Im weißen Bereich) ---
                    const Text(
                      "CruiseConnect",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900, // Extra Fett
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Willkommen zurück!", // Deutsch
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // --- BUTTONS ---
                    _buildMainButton(
                      text: "Registrieren", // Deutsch
                      color: brandColor,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterPage()),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    _buildMainButton(
                      text: "Anmelden", // Deutsch
                      color: brandColor,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => LoginPage()),
                        );
                      },
                    ),

                    const SizedBox(height: 30),

                    // --- ODER ANMELDEN MIT (JETZT MIT LINIEN) ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[300])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              "- oder anmelden mit -", // Deutsch
                              style: TextStyle(
                                color: Colors.grey[400], 
                                fontSize: 14,
                                fontWeight: FontWeight.w500
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey[300])),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- SOCIAL ICONS ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSocialButton('lib/images/google.jpg'),
                        const SizedBox(width: 25),
                        _buildSocialButton('lib/images/Apple.png'),
                      ],
                    ),
                    
                    // Extra Platz unten für gutes Scrollen
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainButton({required String text, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 35),
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(String path) {
    return Container(
      padding: const EdgeInsets.all(12),
      height: 75,
      width: 75,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15), 
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Image.asset(path),
    );
  }
}