import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/pages/home_page.dart'; // Import Home Page

class LoginPage extends StatelessWidget {
  LoginPage({super.key});

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    // Farbe angepasst an Welcome Page (einheitliches Rot)
    final Color brandColor = const Color(0xFFEF4F4F);

    // Wir definieren die Höhe des roten Bereichs fix auf 35%
    final double headerHeight = size.height * 0.35;

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

          // 2. Weißer Container (unten)
          Positioned(
            top: headerHeight, // Startet exakt nach den 35%
            bottom: 0,
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

          // 3. Inhalt
          SingleChildScrollView(
            child: Column(
              children: [
                // --- ROTER BEREICH (Header + Logo) ---
                // Dieser Container ist exakt so groß wie der rote Hintergrund-Teil.
                Container(
                  height: headerHeight,
                  width: double.infinity,
                  padding: EdgeInsets.only(
                    top: padding.top,
                  ), // Beachtet die Statusbar
                  child: Column(
                    children: [
                      // Header Zeile
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 0,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            const Text(
                              "CruiseConnect",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 50),
                          ],
                        ),
                      ),

                      // LOGO ZENTRIERUNG:
                      // Beispiel: Logo nach unten verschieben NICHT BERÜHREN
                      const SizedBox(height: 22.5),

                      Container(
                        height: 132, // +10% GRÖSSER (vorher 120)
                        width: 220, // +10% GRÖSSER (vorher 200)
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],

                        ),
                        child: const Icon(
                          Icons.directions_car,
                          size: 66,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // --- WEISSER BEREICH (Formular) ---
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          height: 40,
                        ), // Abstand zum oberen Rand der weißen Box
                        // Titel zentriert
                        const Center(
                          child: Text(
                            "Willkommen zurück",
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Center(
                          child: Text(
                            "Melde dich an, um fortzufahren",
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        ),

                        const SizedBox(height: 35),

                        // Username Feld
                        _buildLabel("E-Mail Adresse"),
                        _buildTextField(
                          usernameController,
                          false,
                          Icons.email_outlined,
                        ),

                        const SizedBox(height: 20),

                        // Password Feld
                        _buildLabel("Passwort"),
                        _buildTextField(
                          passwordController,
                          true,
                          Icons.lock_outline,
                        ),

                        const SizedBox(height: 10),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {},
                            child: Text(
                              "Passwort vergessen?",
                              style: TextStyle(
                                color: brandColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // --- BUTTON ---
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HomePage(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandColor,
                              foregroundColor: Colors.white,
                              elevation: 5,
                              shadowColor: brandColor.withOpacity(0.4),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              "Anmelden",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // --- REGISTER LINK ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Noch kein Konto? ",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                // TODO: Zur Registrierung
                              },
                              child: Text(
                                "Jetzt registrieren",
                                style: TextStyle(
                                  color: brandColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Puffer unten
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Label Helper
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          fontSize: 14,
        ),
      ),
    );
  }

  // TextField Helper
  Widget _buildTextField(
    TextEditingController controller,
    bool obscure,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.transparent),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}
